#!/usr/bin/env python3
"""Pack the supplied pure-text BF16 tensor manifest into little-endian Q8.24."""

import argparse
import json
import os
from pathlib import Path
import struct
import tempfile


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError(f"duplicate JSON key: {name}")
        result[name] = value
    return result


def load_json(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique_object)


def expanded_manifest(spec_dir):
    config = load_json(spec_dir / "config.json")["text_config"]
    manifest = load_json(spec_dir / "language_model_tensors.json")
    tensors = dict(manifest["global_tensors"])
    ordered = sorted(tensors)
    for layer, kind in enumerate(config["layer_types"]):
        if kind == "sliding_attention":
            template = manifest["sliding_attention_layer_template_layer_0"]
            prefix = "language_model.layers.0."
        elif kind == "full_attention":
            template = manifest["full_attention_layer_template_layer_5"]
            prefix = "language_model.layers.5."
        else:
            raise ValueError(f"unsupported layer type: {kind}")
        for old_name in sorted(template):
            if not old_name.startswith(prefix):
                raise ValueError(f"invalid template name: {old_name}")
            name = f"language_model.layers.{layer}." + old_name[len(prefix):]
            tensors[name] = template[old_name]
            ordered.append(name)
    if len(ordered) != manifest["total_language_model_tensors"]:
        raise ValueError("expanded manifest count mismatch")
    return tensors, ordered


def bf16_to_q24(bits):
    sign = bits >> 15
    exponent = (bits >> 7) & 255
    fraction = bits & 127
    if exponent == 255:
        raise ValueError(f"nonfinite BF16: 0x{bits:04x}")
    significand = fraction if exponent == 0 else 128 + fraction
    shift = -109 if exponent == 0 else exponent - 110
    if shift >= 0:
        magnitude = significand << shift
    else:
        divisor = 1 << -shift
        magnitude, remainder = divmod(significand, divisor)
        halfway = divisor >> 1
        if remainder > halfway or (remainder == halfway and magnitude & 1):
            magnitude += 1
    value = -magnitude if sign else magnitude
    return min(2147483647, max(-2147483648, value))


def read_header(stream, file_size, expected):
    raw_length = stream.read(8)
    if len(raw_length) != 8:
        raise ValueError("truncated safetensors length")
    length = struct.unpack("<Q", raw_length)[0]
    if length < 2 or length > 100_000_000 or length > file_size - 8:
        raise ValueError("invalid safetensors header length")
    raw = stream.read(length)
    if not raw.startswith(b"{"):
        raise ValueError("safetensors header must begin with '{'")
    header = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    if not isinstance(header, dict):
        raise ValueError("safetensors header must be an object")
    pure_names = {name for name in header if name.startswith("language_model.")}
    if pure_names != set(expected):
        missing = sorted(set(expected) - pure_names)
        extra = sorted(pure_names - set(expected))
        raise ValueError(f"pure-text tensor mismatch; missing={missing}; unexpected={extra}")
    widths = {"BOOL": 1, "U8": 1, "I8": 1, "F8_E4M3": 1, "F8_E5M2": 1,
              "I16": 2, "U16": 2, "F16": 2, "BF16": 2,
              "I32": 4, "U32": 4, "F32": 4, "I64": 8, "U64": 8, "F64": 8}
    intervals = []
    for name, tensor in header.items():
        if name == "__metadata__":
            if not isinstance(tensor, dict) or any(
                    not isinstance(k, str) or not isinstance(v, str)
                    for k, v in tensor.items()):
                raise ValueError("invalid safetensors metadata")
            continue
        if not isinstance(tensor, dict) or set(tensor) != {"dtype", "shape", "data_offsets"}:
            raise ValueError(f"malformed tensor descriptor: {name}")
        shape = tensor["shape"]
        offsets = tensor["data_offsets"]
        if (not isinstance(shape, list) or
                any(type(d) is not int or d < 0 for d in shape) or
                not isinstance(offsets, list) or len(offsets) != 2 or
                any(type(d) is not int or d < 0 for d in offsets)):
            raise ValueError(f"invalid shape/offsets: {name}")
        dtype = tensor["dtype"]
        if dtype not in widths:
            raise ValueError(f"unsupported safetensors dtype: {dtype}")
        count = 1
        for dimension in shape:
            count *= dimension
        start, end = offsets
        if end < start or end - start != count * widths[dtype]:
            raise ValueError(f"tensor byte count mismatch: {name}")
        if end > file_size - 8 - length:
            raise ValueError(f"tensor outside file: {name}")
        if name in expected:
            if dtype != "BF16" or shape != expected[name]["shape"]:
                raise ValueError(f"BF16 dtype/authoritative shape mismatch: {name}")
        intervals.append((start, end, name))
    cursor = 0
    for start, end, name in sorted(intervals):
        if start != cursor:
            raise ValueError(f"overlapping or incomplete data region at {name}")
        cursor = end
    if cursor != file_size - 8 - length:
        raise ValueError("unclaimed or truncated safetensors payload")
    return header, 8 + length


def pack(input_path, output_path, inventory_path, spec_dir):
    expected, ordered = expanded_manifest(spec_dir)
    paths = [Path(p).resolve() for p in (input_path, output_path, inventory_path)]
    if len(set(paths)) != 3:
        raise ValueError("input, image and inventory paths must be distinct")
    output_path, inventory_path = paths[1:]
    temporary_paths = []
    try:
        with paths[0].open("rb") as source:
            header, data_base = read_header(source, os.fstat(source.fileno()).st_size, expected)
            with tempfile.NamedTemporaryFile(dir=output_path.parent, delete=False) as image:
                temporary_paths.append(Path(image.name))
                inventory = []
                offset = 0
                for name in ordered:
                    tensor = header[name]
                    start, end = tensor["data_offsets"]
                    source.seek(data_base + start)
                    remaining = end - start
                    while remaining:
                        chunk = source.read(min(remaining, 65536))
                        if not chunk or len(chunk) % 2:
                            raise ValueError(f"truncated BF16 payload: {name}")
                        image.write(b"".join(struct.pack("<i", bf16_to_q24(bits[0]))
                                             for bits in struct.iter_unpack("<H", chunk)))
                        remaining -= len(chunk)
                    size = (end - start) * 2
                    inventory.append({"name": name, "shape": tensor["shape"],
                                      "offset_bytes": offset, "size_bytes": size})
                    offset += size
            with tempfile.NamedTemporaryFile(
                    dir=inventory_path.parent, mode="w", encoding="utf-8", delete=False) as info:
                temporary_paths.append(Path(info.name))
                json.dump({"format": "signed_le32_Q8.24", "weights_bytes": offset,
                           "excluded_non_language_model_tensors": sorted(
                               name for name in header
                               if name != "__metadata__" and name not in expected),
                           "tensors": inventory}, info, indent=2)
                info.write("\n")
        os.replace(temporary_paths[0], output_path)
        os.replace(temporary_paths[1], inventory_path)
    finally:
        for path in temporary_paths:
            if path.exists():
                path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--spec-dir", type=Path,
                        default=Path(__file__).resolve().parent.parent / "hf_embeddinggemma2_spec")
    args = parser.parse_args()
    try:
        pack(args.input, args.output, args.inventory, args.spec_dir)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"pack_model: {error}\n")


if __name__ == "__main__":
    main()
