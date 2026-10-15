"""Direct BF16 parsing and independently evaluated, bounded official subnetworks."""
import argparse
from array import array
import copy
import hashlib
import itertools
import json
import math
from pathlib import Path
import struct
from model import (Fixture, Floating, Integer, Q, WEIGHTS, VISION)


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
            require(name == "vision_tower.patch_embedder.position_embedding_table" and
                    len(shape) == 2 and len(loaded) == 3,
                    f"{name}: unsupported JSON coordinate rank")
            loaded = [math.prod(loaded[:-1]), loaded[-1]]
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
                        "coordinates": ("leading indices of loaded tensor; position axes "
                                        "flattened with original channel stride")})
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
    gate = {
        "passed": crosscheck["passed"], "scope": "authorized bounded 55-tensor slice",
        "full_checkpoint_coverage_required": False,
        "tensor_names": sorted(tensors),
        "remapping": SLICE_POLICY,
    }
    return {"status": "input_validation_only", "direct_parser": validation,
            "coverage_gate": gate,
            "official_forward_pass_executed": False, "rtl_executed": False,
            "official_comparison_artifact_emitted": False}


SLICE_POLICY = {
    "scope": "scaled official-slice subnetwork, not native full-model inference",
    "vision_layers": "destination layers reuse official vision layer 0",
    "text_layers": "destination layer modulo 6 == 5 uses official layer 5; others layer 0",
    "framing": "public BOI 255999 uses slice row 0; public EOI 258882 uses slice row 1",
    "framing_limit": "these are explicitly remapped slice embeddings, not official BOI/EOI rows",
    "ple": "destination layer i selects available source rows i*scaled_PLE_DIM + channel",
    "heads": "packed leading source components repartitioned into scaled destination heads",
    "head_limit": "scaled heads are not separate original checkpoint heads",
    "positions": ("row axis uses loaded [0,row,channel], column axis loaded [1,col,channel]; "
                  "under the manifest contiguous range these are original axis 0 positions "
                  "row and 256+col, not original axis 1"),
    "extraction": ("manifest ranges interpreted as contiguous prefixes of original tensors; "
                   "original position coordinates recovered with original strides, not reshape"),
}


def fp32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


class OfficialFP32(Floating):
    """Binary64 reductions/math, binary32 at each published operator boundary."""

    def decode(self, value):
        return fp32(value)

    def add(self, a, b):
        return fp32(a+b)

    def mul(self, a, b):
        return fp32(a*b)

    def mat(self, w, x):
        return [fp32(sum(a*b for a, b in zip(row, x))) for row in w]

    def mean(self, xs):
        return [fp32(v) for v in super().mean(xs)]

    def norm(self, x, w=None):
        square = sum(a*a for a in x)
        denominator = math.sqrt(square if w is None else square/len(x)+1e-6)
        if denominator == 0:
            return [0.0]*len(x)
        return [fp32(a/denominator*(1.0 if w is None else 1.0+w[i]))
                for i, a in enumerate(x)]

    def scale(self, x, d, divide=False):
        return [fp32(v) for v in super().scale(x, d, divide)]

    def gelu(self, value):
        return fp32(super().gelu(value))

    def rotate(self, x, pos, theta):
        return [fp32(v) for v in super().rotate(x, pos, theta)]

    def attention(self, q, ks, vs, uniform=False):
        return [fp32(v) for v in super().attention(q, ks, vs, uniform)]


class OfficialVisionCoverage(OfficialFP32):
    """Observe graph operations without changing their operands or results."""

    def __init__(self, fixture):
        self.fixture = fixture
        self.phase = "patch"
        self.trace = {}
        self.rotations, self.attentions, self.pool_members = [], [], []

    def __setitem__(self, name, values):
        self.trace[name] = values
        if name == "patch":
            self.phase = "vision"
        elif name == f"vision.{self.fixture.c.VISION_LAYERS-1}":
            self.phase = "pool"
        elif name == "soft":
            self.phase = "text"

    def rotate(self, x, pos, theta):
        if self.phase == "vision":
            require(theta == 100, "official vision theta coverage")
            self.rotations.append(pos)
        return super().rotate(x, pos, theta)

    def attention(self, q, ks, vs, uniform=False):
        if self.phase == "vision":
            scores = [sum(a*b for a, b in zip(q, k))/math.sqrt(len(q)) for k in ks]
            self.attentions.append({
                "keys": len(ks), "values": len(vs),
                "distinct_keys": len({tuple(k) for k in ks}),
                "score_range": max(scores)-min(scores) if scores else 0,
                "uniform_override": uniform,
            })
        return super().attention(q, ks, vs, uniform)

    def mean(self, xs):
        if self.phase == "pool":
            self.pool_members.append(xs)
        return super().mean(xs)

    def result(self):
        f, c = self.fixture, self.fixture.c
        require((f.rows, f.cols, c.POOL_KERNEL, c.EMBED_DIM) == (4, 5, 3, 12),
                "official B predetermined geometry changed")
        require(f.seed == 17 and f.mode in (1, 2) and f.dimension == 12 and
                f.ids == ([] if f.mode == 1 else [7, 19, 31]) and
                f.positions == ([] if f.mode == 1 else [1, 4, 8]) and
                f.masks == ([] if f.mode == 1 else [1, 0, 1]),
                "official B predetermined text inputs changed")
        require(len(f.image) == 60 and min(f.image) < 0 < max(f.image),
                "official B mixed-sign RGB image missing")
        patches = [(r, col) for r in range(f.rows) for col in range(f.cols)]
        require(len(self.trace["patch"]) == 20 and
                len({tuple(v) for v in self.trace["patch"]}) > 1,
                "official distinct patch computations not observed")
        expected_rotations = [p for _ in range(c.VISION_LAYERS)
                              for r, col in patches
                              for _ in range(2*c.VISION_HEADS) for p in (r, col)]
        require(self.rotations == expected_rotations,
                "official nonzero row/column axial operations missing")
        require(len(self.attentions) == 20*c.VISION_HEADS*c.VISION_LAYERS and
                all(a["keys"] == a["values"] == 20 and a["distinct_keys"] > 1 and
                    not a["uniform_override"] for a in self.attentions) and
                any(a["score_range"] > 0 for a in self.attentions),
                "official multi-key nontrivial bidirectional attention missing")
        windows = []
        final = self.trace[f"vision.{c.VISION_LAYERS-1}"]
        for r in range(0, f.rows, c.POOL_KERNEL):
            for col in range(0, f.cols, c.POOL_KERNEL):
                indices = [a*f.cols+b
                           for a in range(r, min(r+c.POOL_KERNEL, f.rows))
                           for b in range(col, min(col+c.POOL_KERNEL, f.cols))]
                windows.append({"origin": [r, col], "patch_indices": indices,
                                "participants": len(indices)})
        require([len(m) for m in self.pool_members] == [9, 6, 3, 2],
                "official partial pooling participant counts missing")
        require(self.pool_members == [[final[i] for i in w["patch_indices"]]
                                     for w in windows],
                "official pooling did not consume the required patch vectors")
        require(len(self.trace["soft"]) == 4, "official four bridge vectors missing")
        return {
            "assertions_passed": True, "patch_positions": patches,
            "distinct_patch_vectors": len({tuple(v) for v in self.trace["patch"]}),
            "axial_rotation_calls": len(self.rotations),
            "vision_attention_calls": len(self.attentions),
            "vision_attention": self.attentions, "pooling_windows": windows,
            "pooling_participants": [w["participants"] for w in windows],
            "observation": "FP32 graph operations; RTL output and scratch histories checked independently",
        }


class OfficialFixture(Fixture):
    """The existing graph interpreter with independent FP32/quantized operands."""

    def __init__(self, config, seed, mode, dimension, tensors, manifest):
        self.parsed = tensors
        self.entries = {item["name"]: item for item in manifest["tensors"]}
        self.mapping, self.float_tensors = [], {}
        super().__init__(config, seed, mode, dimension)
        self.float_image = [value/Q for value in self.image]

    def source_name(self, name):
        globals_ = {
            "embed": "language_model.embed_tokens.weight",
            "projection": "language_model.embedding_projection.weight",
            "norm": "language_model.norm.weight",
            "ple_model": "language_model.ple.per_layer_model_projection.weight",
            "ple_norm": "language_model.ple.per_layer_projection_norm.weight",
            "patch": "vision_tower.patch_embedder.input_proj.weight",
            "position": "vision_tower.patch_embedder.position_embedding_table",
            "bridge": "embed_vision.embedding_projection.weight",
        }
        if name in globals_:
            return globals_[name]
        layer, suffix = name.split(".")
        vision = layer[0] == "v"
        source_layer = 0 if vision or int(layer[1:]) % 6 != 5 else 5
        prefix = (f"vision_tower.encoder.layers.{source_layer}." if vision else
                  f"language_model.layers.{source_layer}.")
        norm_names = {
            "input": "input_layernorm.weight", "post_att": "post_attention_layernorm.weight",
            "post_ff": "post_feedforward_layernorm.weight",
            "pre_ff": "pre_feedforward_layernorm.weight", "scalar": "layer_scalar",
            "qnorm": "self_attn.q_norm.weight", "knorm": "self_attn.k_norm.weight",
            "ple_gate": "ple_block.per_layer_input_gate.weight",
            "ple_proj": "ple_block.per_layer_projection.weight",
            "ple_post": "ple_block.post_per_layer_input_norm.weight",
        }
        if suffix in norm_names:
            return prefix+norm_names[suffix]
        family = "self_attn" if suffix in ("q", "k", "v", "o") else "mlp"
        return prefix+family+"."+suffix+"_proj."+("linear." if vision else "")+"weight"

    def allocate(self, name, base, offset, rows, cols=1, scalar=False, table=False):
        source = self.source_name(name)
        shape, values = self.parsed[source]
        entry = self.entries[source]
        original = entry["original_shape"]
        self.offsets[name] = base+4*offset
        records = []
        saturations = 0

        def select(coords):
            nonlocal saturations
            require(len(coords) == len(shape) and all(0 <= i < n for i, n in zip(coords, shape)),
                    f"{name}: unavailable loaded coordinates {coords}")
            index = sum(i*math.prod(shape[j+1:]) for j, i in enumerate(coords))
            value = values[index]
            q, saturated = quantize(value)
            saturations += saturated
            # The supplied position range is a contiguous original prefix:
            # loaded axis 1 is original row-axis position 256, not column-axis 0.
            original_coords = []
            remaining = index
            for axis in range(len(original)):
                stride = math.prod(original[axis+1:])
                component, remaining = divmod(remaining, stride)
                original_coords.append(component)
            records.append((list(coords), original_coords, index))
            return value, q

        if table or name == "position":
            dest_rows = sorted(set(self.ids+[255999, 258882])) if table else (
                list(range(self.rows))+
                [self.c.POSITION_EMBEDDING_SIZE+i for i in range(self.cols)])
            floating, integer = {}, {}
        else:
            dest_rows = range(rows)
            floating, integer = [], []
        for row in dest_rows:
            floats, ints = [], []
            for col in range(cols):
                if table:
                    source_row = {255999: 0, 258882: 1}.get(row, row)
                    coords = (source_row, col)
                elif name == "position":
                    axis, pos = divmod(row, self.c.POSITION_EMBEDDING_SIZE)
                    coords = (axis, pos, col)
                elif len(shape) == 1:
                    coords = (row,)
                elif name == "patch":
                    ch, pixel = divmod(col, self.c.PATCH_SIZE**2)
                    dy, dx = divmod(pixel, self.c.PATCH_SIZE)
                    coords = (row, ch*256+dy*16+dx)
                else:
                    coords = (row, col)
                value, q = select(coords)
                floats.append(value)
                ints.append(q)
                self.mem[base+4*(offset+row*cols+col)] = q
            if table or name == "position":
                floating[row], integer[row] = floats, ints
            else:
                floating.append(floats if cols != 1 else floats[0])
                integer.append(ints if cols != 1 else ints[0])
        self.float_tensors[name], self.tensors[name] = floating, integer
        self.mapping.append({
            "destination_tensor": name, "source_tensor": source,
            "source_sha256": entry["sha256"], "original_shape": original,
            "loaded_shape": shape, "destination_shape": [rows, cols],
            "destination_base": base, "destination_word_offset": offset,
            "destination_rows": list(dest_rows),
            "loaded_coordinates": [r[0] for r in records],
            "original_coordinates_under_contiguous_prefix": [r[1] for r in records],
            "original_file_byte_offsets": [entry["hf_byte_range"][0]+2*r[2] for r in records],
            "original_hf_byte_range_inclusive": entry["hf_byte_range"],
            "quantization": "nearest-even value*2^24, signed32 saturation",
            "saturation_count": saturations,
        })
        return offset+rows*cols

    def matrix(self, name, ops):
        if not isinstance(ops, OfficialFP32):
            if name == "position":
                return {k: [ops.decode(v) for v in row] for k, row in self.tensors[name].items()}
            return super().matrix(name, ops)
        data = self.float_tensors[name]
        if name == "position":
            return data
        if data and not isinstance(data[0], list):
            return [[x] for x in data]
        return data

    def vector(self, name, ops):
        return (self.float_tensors[name] if isinstance(ops, OfficialFP32) else
                super().vector(name, ops))

    def run(self, ops, alteration=None, trace=None):
        if not isinstance(ops, OfficialFP32):
            return super().run(ops, alteration, trace)
        if isinstance(ops, OfficialVisionCoverage):
            require(trace is None, "official coverage owns its graph trace")
            trace = ops
        # Only the floating interpreter sees raw checkpoint tensors and FP32
        # inputs. No Q24 intermediate or weight image is decoded in this path.
        integer_tensors, integer_image = self.tensors, self.image
        self.tensors, self.image = self.float_tensors, self.float_image
        try:
            return super().run(ops, alteration, trace)
        finally:
            self.tensors, self.image = integer_tensors, integer_image


def load_official(folder):
    result = validate_inputs(folder)
    require(result["coverage_gate"]["passed"], "official slice coordinate cross-check failed")
    expected, _ = authoritative_shapes(folder)
    weights = folder/"official_weights"
    manifest = read_json((weights/"official_weights_manifest.json").read_bytes())
    tensors, _ = parse_checkpoint(
        (weights/"google_embeddinggemma2_official_slice.safetensors").read_bytes(),
        manifest, expected)
    result["parser_self_tests"] = self_test()
    return tensors, manifest, result


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
        "scope": gate["scope"],
        "output": str(args.output),
    }), flush=True)
    return 0 if gate["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
