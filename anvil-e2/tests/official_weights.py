"""Direct BF16 checkpoint validation and mandatory-coordinate admission gate.

This is input validation, not a software forward pass or an RTL comparison.
Original-file byte ranges do not establish an absent extraction coordinate map.
"""
import argparse
from array import array
import copy
import hashlib
import itertools
import json
import math
from pathlib import Path
import struct


class CheckpointError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CheckpointError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(data):
    return json.loads(data, object_pairs_hook=unique_object)


def shape_size(shape):
    require(isinstance(shape, list) and all(
        type(n) is int and n > 0 for n in shape), f"invalid shape: {shape}")
    return math.prod(shape)


def quantize(value):
    require(math.isfinite(value), "cannot quantize nonfinite weight")
    exact = round(value * (1 << 24))
    result = min(2147483647, max(-2147483648, exact))
    return result, result != exact


def parse_checkpoint(data, manifest, expected_shapes):
    require(sha256(data) == manifest["extracted_safetensors_sha256"],
            "complete extracted safetensors SHA-256 mismatch")
    require(len(data) >= 8, "truncated header-length word")
    length, = struct.unpack_from("<Q", data)
    require(2 <= length <= len(data)-8 and length % 8 == 0,
            "invalid safetensors header length/alignment")
    header_bytes = data[8:8+length]
    require(header_bytes.startswith(b"{"), "safetensors header must start with object")
    header = read_json(header_bytes)
    require(isinstance(header, dict), "header is not an object")
    metadata = header.pop("__metadata__", {})
    require(isinstance(metadata, dict) and all(
        isinstance(k, str) and isinstance(v, str) for k, v in metadata.items()),
        "invalid safetensors metadata")
    entries = manifest["tensors"]
    require(len(entries) == manifest["tensor_count_extracted"], "manifest tensor count")
    by_name = {item["name"]: item for item in entries}
    require(len(by_name) == len(entries), "duplicate manifest tensor")
    require(set(header) == set(by_name), "manifest/header tensor name disagreement")
    payload = memoryview(data)[8+length:]
    intervals, tensors, records = [], {}, []
    original_intervals = []
    for name, info in header.items():
        item = by_name[name]
        require(name in expected_shapes, f"unknown official tensor: {name}")
        require(info["dtype"] == item["dtype"] == "BF16", f"{name}: dtype is not BF16")
        shape = info["shape"]
        elements = shape_size(shape)
        original = item["original_shape"]
        shape_size(original)
        require(shape == item["loaded_shape"], f"{name}: manifest/header shape disagreement")
        require(original == expected_shapes[name], f"{name}: authoritative original shape disagreement")
        require(len(shape) == len(original) and all(a <= b for a, b in zip(shape, original)),
                f"{name}: loaded shape exceeds original shape")
        offsets = info["data_offsets"]
        require(isinstance(offsets, list) and len(offsets) == 2 and
                all(type(n) is int for n in offsets), f"{name}: invalid data offsets")
        begin, end = offsets
        require(0 <= begin <= end <= len(payload) and begin % 2 == end % 2 == 0,
                f"{name}: payload bounds/alignment")
        require(end-begin == 2*elements, f"{name}: shape/byte length disagreement")
        intervals.append((begin, end, name))
        raw = payload[begin:end]
        digest = sha256(raw)
        require(digest == item["sha256"], f"{name}: tensor SHA-256 mismatch")
        source_range = item["hf_byte_range"]
        require(isinstance(source_range, list) and len(source_range) == 2 and
                all(type(n) is int for n in source_range), f"{name}: invalid HF range")
        first, last = source_range
        require(8+manifest["safetensors_header_bytes"] <= first <= last <
                manifest["safetensors_total_bytes"], f"{name}: original-file range bounds")
        require(first % 2 == 0 and last-first+1 == len(raw),
                f"{name}: original-file inclusive range length/alignment")
        original_intervals.append((first, last+1, name))
        values = array("f")
        saturations = 0
        for (bits,) in struct.iter_unpack("<H", raw):
            value, = struct.unpack("<f", struct.pack("<I", bits << 16))
            require(math.isfinite(value), f"{name}: nonfinite BF16 payload")
            values.append(value)
            saturations += quantize(value)[1]
        tensors[name] = (shape, values)
        records.append({
            "name": name, "dtype": "BF16", "original_shape": original,
            "loaded_shape": shape, "extracted_data_offsets_half_open": offsets,
            "extracted_file_offsets_half_open": [8+length+begin, 8+length+end],
            "original_hf_byte_range_inclusive": source_range,
            "sha256": digest, "decoded_finite_elements": elements,
            "q824_saturations": saturations,
            "original_coordinates_verified": shape == original,
        })
    cursor = 0
    for begin, end, name in sorted(intervals):
        require(begin == cursor, f"{name}: overlapping or noncontiguous payload interval")
        cursor = end
    require(cursor == len(payload), "unindexed trailing payload bytes")
    previous = 0
    for begin, end, name in sorted(original_intervals):
        require(begin >= previous, f"{name}: overlapping original-file extraction ranges")
        previous = end
    return tensors, {
        "complete_file_sha256": sha256(data), "header_bytes": length,
        "payload_bytes": len(payload), "tensor_count": len(records),
        "decoded_finite_elements": sum(r["decoded_finite_elements"] for r in records),
        "metadata": metadata, "tensors": sorted(records, key=lambda r: r["name"]),
        "provenance_limit": "Consistency with supplied manifest, not independent remote authentication",
        "decode": "little-endian BF16 bits shifted left 16 into struct IEEE754 binary32",
        "quantization": "nearest-even round(value*2^24), signed32 saturation; no memory image emitted",
    }


def authoritative_shapes(folder):
    language = read_json((folder/"language_model_tensors.json").read_bytes())
    config = read_json((folder/"config.json").read_bytes())
    expected = dict(language["global_tensors"])
    for layer, kind in enumerate(config["text_config"]["layer_types"]):
        full = kind == "full_attention"
        key = ("full_attention_layer_template_layer_5" if full else
               "sliding_attention_layer_template_layer_0")
        old = f"language_model.layers.{5 if full else 0}."
        for name, entry in language[key].items():
            expected[name.replace(old, f"language_model.layers.{layer}.", 1)] = entry
    expected.update(read_json((folder/"vision_model_tensors.json").read_bytes()))
    return {name: entry["shape"] for name, entry in expected.items()}, config


def flatten_shaped(value, shape):
    if not shape:
        require(type(value) in (int, float), "slice leaf is not numeric")
        return [value]
    require(isinstance(value, list) and len(value) == shape[0],
            "pre-extracted JSON nested shape disagreement")
    return list(itertools.chain.from_iterable(flatten_shaped(row, shape[1:]) for row in value))


def crosscheck_slices(slices, tensors):
    records, unresolved = [], []
    for name, entry in slices.items():
        require(name in tensors, f"JSON slice missing direct tensor: {name}")
        loaded, values = tensors[name]
        shape = entry["shape"]
        shape_size(shape)
        if len(shape) != len(loaded):
            unresolved.append({
                "name": name, "json_shape": shape, "loaded_shape": loaded,
                "reason": "JSON rank differs from BF16 tensor; no extraction coordinate map supplied",
            })
            continue
        require(all(a <= b for a, b in zip(shape, loaded)),
                f"{name}: pre-extracted slice exceeds loaded tensor")
        fp = flatten_shaped(entry["fp32"], shape)
        fixed = flatten_shaped(entry["q8_24"], shape)
        strides = [math.prod(loaded[i+1:]) for i in range(len(loaded))]
        for i, coords in enumerate(itertools.product(*(range(n) for n in shape))):
            value = values[sum(c*s for c, s in zip(coords, strides))]
            require(type(fp[i]) in (int, float) and fp[i] == value,
                    f"{name}{coords}: pre-extracted FP32 mismatch")
            require(type(fixed[i]) is int and fixed[i] == quantize(value)[0],
                    f"{name}{coords}: pre-extracted Q8.24 mismatch")
        records.append({"name": name, "shape": shape, "elements": len(fp),
                        "coordinates": "leading indices of loaded tensor; not proof of original coordinates"})
    require(records, "empty pre-extracted JSON cross-check")
    return {"compared_loaded_coordinate_slices": records, "unresolved_mappings": unresolved,
            "passed": not unresolved}


def coverage_gate(tensors, expected, config):
    missing, partial = [], []
    for name, shape in sorted(expected.items()):
        if name not in tensors:
            missing.append({"name": name, "required_shape": shape})
        elif tensors[name][0] != shape:
            partial.append({"name": name, "required_shape": shape,
                            "loaded_shape": tensors[name][0],
                            "missing_elements_at_least": math.prod(shape)-math.prod(tensors[name][0])})
    framing = []
    for key in ("boi_token_id", "eoi_token_id"):
        row = config[key]
        loaded = tensors.get("language_model.embed_tokens.weight")
        framing.append({
            "token": key, "original_row": row,
            "required_columns": [0, config["text_config"]["hidden_size"]],
            "loaded_embedding_shape": loaded[0] if loaded else None,
            "available_in_declared_leading_rows": bool(loaded and row < loaded[0][0]),
            "coordinate_map_supplied": False,
        })
    position_name = "vision_tower.patch_embedder.position_embedding_table"
    position = tensors.get(position_name)
    ambiguity = None
    if position and position[0] != expected[position_name]:
        original, loaded = expected[position_name], position[0]
        ambiguity = {
            "name": position_name, "original_axis_stride_bytes": math.prod(original[1:])*2,
            "loaded_axis_stride_bytes": math.prod(loaded[1:])*2,
            "reason": "One contiguous original byte range cannot establish leading positions of both axes",
            "required": "authoritative original tensor base offset and per-axis extraction ranges/coordinates",
        }
    return {
        "passed": not (missing or partial or ambiguity),
        "missing_tensors": missing, "partial_tensors": partial,
        "required_framing_rows": framing, "position_mapping_ambiguity": ambiguity,
        "partial_mapping_limit": "No original tensor base offsets or multidimensional extraction map supplied",
        "mandatory_cases": [
            {"mode": mode, "output_dimension": dimension, "status": "blocked",
             "reason": "mandatory official tensor coverage/mapping unavailable"}
            for mode in (0, 1, 2) for dimension in (768, 512, 256, 128)
        ],
        "forbidden_substitutions": [
            "token aliases", "repeated or relabeled layers", "synthetic/zero fallback weights",
            "reinterpretation of loaded axis1 as original axis1", "omitted stages",
        ],
    }


def self_test():
    name = "test.weight"
    raw = struct.pack("<4H", 0x3f80, 0xbf80, 0x0001, 0x4300)
    info = {"dtype": "BF16", "shape": [2, 2], "data_offsets": [0, len(raw)]}
    entry = {"name": name, "dtype": "BF16", "loaded_shape": [2, 2],
             "original_shape": [2, 2], "hf_byte_range": [128, 135], "sha256": sha256(raw)}
    base_manifest = {"tensor_count_extracted": 1, "tensors": [entry],
                     "safetensors_header_bytes": 64, "safetensors_total_bytes": 256}

    def encode(header, payload=raw, manifest=None):
        h = json.dumps(header).encode()
        h += b" " * (-len(h) % 8)
        data = struct.pack("<Q", len(h)) + h + payload
        m = copy.deepcopy(base_manifest if manifest is None else manifest)
        m["extracted_safetensors_sha256"] = sha256(data)
        return data, m

    data, manifest = encode({name: info})
    tensors, validation = parse_checkpoint(data, manifest, {name: [2, 2]})
    require(list(tensors[name][1]) == [1.0, -1.0, 2**-133, 128.0], "BF16 known-vector decode")
    require(validation["tensors"][0]["q824_saturations"] == 1, "saturation count")
    require(quantize(2**-25)[0] == quantize(-2**-25)[0] == 0, "nearest-even zero ties")
    require(quantize(3*2**-25)[0] == 2 and quantize(-3*2**-25)[0] == -2,
            "nearest-even signed ties")
    require(quantize(-128.0) == (-2147483648, False), "negative endpoint")
    cases = []
    for field, value in (("dtype", "F32"), ("shape", [4]), ("data_offsets", [2, 10]),
                         ("data_offsets", [0, 6]), ("data_offsets", [-2, 6])):
        bad = copy.deepcopy(info)
        bad[field] = value
        cases.append((f"header-{field}-{value}", *encode({name: bad})))
    bad = copy.deepcopy(base_manifest)
    bad["tensors"][0]["sha256"] = "0"*64
    cases.append(("tensor-hash", *encode({name: info}, manifest=bad)))
    bad = copy.deepcopy(manifest)
    bad["extracted_safetensors_sha256"] = "0"*64
    cases.append(("file-hash", data, bad))
    for label, mutation in (
        ("range", lambda m: m["tensors"][0].update(hf_byte_range=[128, 137])),
        ("original-shape", lambda m: m["tensors"][0].update(original_shape=[2, 3])),
        ("count", lambda m: m.update(tensor_count_extracted=2)),
    ):
        bad = copy.deepcopy(base_manifest)
        mutation(bad)
        cases.append((label, *encode({name: info}, manifest=bad)))
    cases.append(("trailing-payload", *encode({name: info}, raw+b"\0\0")))
    bad_info = dict(info, data_offsets=[2, 10])
    cases.append(("payload-gap", *encode({name: bad_info}, b"\0\0"+raw)))
    bad_raw = struct.pack("<4H", 0x7f80, 0xbf80, 0x0001, 0x4300)
    bad = copy.deepcopy(base_manifest)
    bad["tensors"][0]["sha256"] = sha256(bad_raw)
    cases.append(("nonfinite", *encode({name: info}, bad_raw, bad)))
    h = ('{"test.weight":'+json.dumps(info)+',"test.weight":'+json.dumps(info)+'}').encode()
    h += b" " * (-len(h) % 8)
    bad_data = struct.pack("<Q", len(h))+h+raw
    bad = copy.deepcopy(manifest)
    bad["extracted_safetensors_sha256"] = sha256(bad_data)
    cases.append(("duplicate-json-key", bad_data, bad))
    rejected = []
    for label, bad_data, bad_manifest in cases:
        try:
            parse_checkpoint(bad_data, bad_manifest, {name: [2, 2]})
        except CheckpointError as error:
            rejected.append({"case": label, "rejection": str(error)})
        else:
            raise CheckpointError(f"parser accepted malformed fixture: {label}")
    return {"known_bf16_vector": True, "signed_quantization_ties_and_endpoints": True,
            "rejected_malformed_cases": rejected}


def validate_inputs(folder):
    weights = folder/"official_weights"
    manifest_path = weights/"official_weights_manifest.json"
    manifest = read_json(manifest_path.read_bytes())
    require(manifest["source_repo"] == "google/embeddinggemma-2", "unexpected source repository")
    require(manifest["source_url"] ==
            "https://huggingface.co/google/embeddinggemma-2/resolve/main/model.safetensors",
            "unexpected source URL")
    filename = "google_embeddinggemma2_official_slice.safetensors"
    require(manifest["extracted_safetensors_file"] == filename, "unexpected extracted filename")
    expected, config = authoritative_shapes(folder)
    tensors, validation = parse_checkpoint((weights/filename).read_bytes(), manifest, expected)
    slices_path = weights/"official_hardware_slices_fp32_q824.json"
    validation["manifest_sha256"] = sha256(manifest_path.read_bytes())
    validation["preextracted_json_sha256"] = sha256(slices_path.read_bytes())
    crosscheck = crosscheck_slices(read_json(slices_path.read_bytes()), tensors)
    validation["preextracted_crosscheck"] = crosscheck
    gate = coverage_gate(tensors, expected, config)
    gate["passed"] = gate["passed"] and crosscheck["passed"]
    gate["preextracted_unresolved_mappings"] = crosscheck["unresolved_mappings"]
    return {"status": "input_validation_only", "direct_parser": validation,
            "coverage_gate": gate,
            "official_forward_pass_executed": False, "rtl_executed": False,
            "official_comparison_artifact_emitted": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), "refusing to overwrite input-validation evidence")
    result = {"status": "failed"}
    try:
        result["parser_self_tests"] = self_test()
        result.update(validate_inputs(Path(__file__).resolve().parents[1]/
                                      "hf_embeddinggemma2_vision_spec"))
    except (CheckpointError, KeyError, TypeError, ValueError, OSError) as error:
        result.update(status="failed", error=f"{type(error).__name__}: {error}")
        args.output.write_text(json.dumps(result, indent=2)+"\n")
        print(result["error"], flush=True)
        return 1
    args.output.write_text(json.dumps(result, indent=2)+"\n")
    gate = result["coverage_gate"]
    print(json.dumps({
        "direct_parser_valid": True, "coverage_gate_passed": gate["passed"],
        "decoded_tensors": result["direct_parser"]["tensor_count"],
        "missing_tensors": len(gate["missing_tensors"]),
        "partial_tensors": len(gate["partial_tensors"]),
        "position_mapping_ambiguity": gate["position_mapping_ambiguity"],
        "required_framing_rows": gate["required_framing_rows"],
        "output": str(args.output),
    }), flush=True)
    return 0 if gate["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
