"""Independent BF16 oracle and synthetic safetensors packer exercises."""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile

sys.path.insert(0,str(Path(__file__).resolve().parent))
from architecture import DEFAULT
from model import CONFIGS, inventory, Q


def oracle(bits):
    float_bits = bits << 16
    value = struct.unpack("<f",struct.pack("<I",float_bits))[0]
    if not math.isfinite(value):
        raise ValueError("nonfinite")
    return max(-(1<<31),min((1<<31)-1,round(value*Q)))


def verify_packing(execution):
    output = execution.output
    spec = importlib.util.spec_from_file_location("tested_packer","design/pack_model.py")
    packer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packer)
    finite = rejected = 0
    for bits in range(65536):
        if bits % 1024 == 0:
            execution.remaining()
        if bits & 0x7f80 == 0x7f80:
            try:
                packer.bf16_to_q24(bits)
            except ValueError:
                rejected += 1
            else:
                raise AssertionError(f"nonfinite accepted {bits:04x}")
        else:
            assert packer.bf16_to_q24(bits) == oracle(bits), hex(bits)
            finite += 1
    default_entries = inventory(DEFAULT)
    expected = {e["name"]:{"shape":e["shape"]} for e in default_entries}
    official = Path("hf_embeddinggemma2_spec/official_weights/"
                    "google_embeddinggemma2_official_slice.safetensors")
    with official.open("rb") as stream:
        try:
            packer.read_header(stream, official.stat().st_size, expected)
        except ValueError as error:
            (output/"official-partial-checkpoint-rejection.log").write_text(str(error)+"\n")
        else:
            raise AssertionError("partial official slice accepted as a complete checkpoint")
    def header(entries):
        result,offset = {},0
        for e in entries:
            size = e["size_bytes"]//2
            result[e["name"]] = {"dtype":"BF16","shape":e["shape"],
                                "data_offsets":[offset,offset+size]}
            offset += size
        return result,offset
    h,size = header(default_entries)
    fixtures = []
    def retain_headers():
        (output/"header-fixtures.json").write_text(json.dumps({
            "format":"safetensors header prefix followed by sparse zero payload",
            "reconstruction":"write header bytes, then truncate to logical_file_size",
            "fixtures":fixtures},indent=2)+"\n")

    def check_header(name, descriptor, reject=False):
        encoded = json.dumps(descriptor,separators=(",",":")).encode()
        prefix = struct.pack("<Q",len(encoded))+encoded
        path = output/(name+".header.bin")
        path.write_bytes(prefix)
        logical_size = len(prefix)+size
        fixture = {"header":path.name,
            "header_sha256":hashlib.sha256(prefix).hexdigest(),
            "logical_file_size":logical_size,"payload_bytes":size,
            "payload_fill_byte":0,"expected_rejection":reject}
        fixtures.append(fixture)
        retain_headers()
        # Retain reconstructible headers, not half-gigabyte logical sparse files.
        with tempfile.TemporaryFile(dir=output) as stream:
            stream.write(path.read_bytes())
            stream.truncate(logical_size)
            stream.seek(0)
            try:
                actual,base = packer.read_header(
                    stream,os.fstat(stream.fileno()).st_size,expected)
            except ValueError as error:
                fixture["observed_rejection"] = str(error)
                if not reject:
                    raise
            else:
                if reject:
                    raise AssertionError("invalid header accepted "+name)
                assert actual == descriptor and base == len(prefix)
        retain_headers()
        return fixture
    check_header("default-header",h)
    mutations = []
    first = default_entries[0]["name"]
    for kind in ("missing","extra","dtype","shape","overlap","outside"):
        changed = json.loads(json.dumps(h))
        if kind=="missing": del changed[first]
        if kind=="extra": changed["language_model.unexpected"] = changed[first]
        if kind=="dtype": changed[first]["dtype"] = "F16"
        if kind=="shape": changed[first]["shape"] = [1]
        if kind=="overlap": changed[default_entries[1]["name"]]["data_offsets"] = [0,changed[default_entries[1]["name"]]["data_offsets"][1]]
        if kind=="outside": changed[first]["data_offsets"][1] = size+2
        check_header("invalid-"+kind,changed,reject=True)
        mutations.append(kind)
    entries = inventory(CONFIGS["A"])
    small_spec = output/"synthetic-spec"
    small_spec.mkdir()
    globals_ = {e["name"]:{"dtype":"BF16","shape":e["shape"]}
                for e in entries if ".layers." not in e["name"]}
    templates = {}
    for layer,kind in ((0,"sliding_attention_layer_template_layer_0"),
                       (5,"full_attention_layer_template_layer_5")):
        templates[kind] = {e["name"]:{"dtype":"BF16","shape":e["shape"]}
            for e in entries if f".layers.{layer}." in e["name"]}
    (small_spec/"config.json").write_text(json.dumps({"text_config":{
        "layer_types":["sliding_attention"]*5+["full_attention"]}}))
    (small_spec/"language_model_tensors.json").write_text(json.dumps({
        "global_tensors":globals_,"total_language_model_tensors":len(entries),**templates}))
    h,size = header(entries)
    payload = bytearray()
    values = []
    samples = (0,0x8000,0x3f80,0xbf80,0x3f01,0x4780,0xc780,1,0x3380,0x33c0)
    for i in range(size//2):
        bits = samples[i%len(samples)]
        payload += struct.pack("<H",bits)
        values.append(oracle(bits))
    raw = json.dumps(h).encode()
    fixture = output/"synthetic.safetensors"
    fixture.write_bytes(struct.pack("<Q",len(raw))+raw+payload)
    image,info = output/"packed.bin",output/"packed.json"
    argv = ["python3","design/pack_model.py","--input",str(fixture),
            "--output",str(image),"--inventory",str(info),"--spec-dir",str(small_spec)]
    execution.run("packer-cli", argv)
    assert image.read_bytes()==b"".join(struct.pack("<i",v) for v in values)
    assert json.loads(info.read_text())["tensors"] == entries
    (output/"packing-summary.json").write_text(json.dumps({
        "finite_bf16_compared":finite,"nonfinite_rejected":rejected,
        "default_header_tensors":len(default_entries),"malformed_headers_rejected":mutations,
        "synthetic_values_compared":len(values),"cli_argv":argv,
        "cli_exit":0},indent=2)+"\n")
