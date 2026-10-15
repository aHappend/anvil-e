"""Official provenance, deterministic reduced mapping and observed RTL comparisons."""
import hashlib
import json
import math
from pathlib import Path
import struct
import time

import model
from model import CONFIGS, Q, forward_details, inventory
from official_fp32 import forward_fp32

DIRECTORY = Path("hf_embeddinggemma2_spec/official_weights")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            h.update(block)
    return h.hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key "+key)
        result[key] = value
    return result


def load_json(text):
    return json.loads(text, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def shape_ok(shape):
    return isinstance(shape, list) and bool(shape) and all(type(v) is int and v > 0 for v in shape)


def quantize(value):
    if not math.isfinite(value):
        raise ValueError("nonfinite coefficient")
    return max(-(1 << 31), min((1 << 31)-1, round(value*Q)))


def load_official(execution):
    path = DIRECTORY/"google_embeddinggemma2_official_slice.safetensors"
    manifest = load_json((DIRECTORY/"official_weights_manifest.json").read_text())
    actual_hash = digest(path)
    assert actual_hash == manifest["extracted_safetensors_sha256"] == (
        "3a310d7733a28f533b611eb7525f597303980c2ab2f890487a9a1fcbf0366bfb")
    blob = path.read_bytes()
    if len(blob) < 8:
        raise ValueError("truncated header length")
    header_size = struct.unpack("<Q", blob[:8])[0]
    if header_size < 2 or header_size > len(blob)-8:
        raise ValueError("invalid header length")
    header = load_json(blob[8:8+header_size])
    header.pop("__metadata__", None)
    entries = manifest["tensors"]
    assert len(header) == len(entries) == manifest["tensor_count_extracted"] == 55
    assert len({e["name"] for e in entries}) == len(entries)
    assert set(header) == {e["name"] for e in entries}
    text = {}
    extents = []
    for entry in entries:
        execution.remaining()
        name = entry["name"]
        tensor = header[name]
        shape, original = entry["loaded_shape"], entry["original_shape"]
        assert shape_ok(shape) and shape_ok(original) and len(shape) == len(original)
        assert all(a <= b for a, b in zip(shape, original))
        assert tensor["shape"] == shape and tensor["dtype"] == entry["dtype"] == "BF16"
        offsets = tensor["data_offsets"]
        assert len(offsets) == 2 and all(type(v) is int for v in offsets)
        start, end = offsets
        size = 2*math.prod(shape)
        assert 0 <= start <= end <= len(blob)-8-header_size and end-start == size
        extents.append((start, end))
        payload = blob[8+header_size+start:8+header_size+end]
        assert hashlib.sha256(payload).hexdigest() == entry["sha256"], name
        first, last = entry["hf_byte_range"]
        assert all(type(v) is int for v in (first, last))
        assert 8+manifest["safetensors_header_bytes"] <= first <= last < manifest["safetensors_total_bytes"]
        assert last-first+1 == size
        if name.startswith("language_model."):
            values = [struct.unpack("<f", struct.pack("<I", bits[0] << 16))[0]
                      for bits in struct.iter_unpack("<H", payload)]
            assert all(math.isfinite(v) for v in values), name
            text[name] = (entry, values)
    ordered = sorted(extents)
    assert ordered[0][0] == 0 and ordered[-1][1] == len(blob)-8-header_size
    assert all(a[1] == b[0] for a, b in zip(ordered, ordered[1:]))
    assert len(text) == 39
    supplied = load_json((DIRECTORY/"official_hardware_slices_fp32_q824.json").read_text())
    assert set(text) <= set(supplied)
    coordinates = 0
    for name, descriptor in supplied.items():
        if not name.startswith("language_model."):
            continue
        assert name in text
        source, values = text[name]
        shape = descriptor["shape"]
        assert shape_ok(shape) and len(shape) == len(source["loaded_shape"])
        assert all(a <= b for a, b in zip(shape, source["loaded_shape"]))
        def flatten(value, dimensions):
            assert isinstance(value, list) and len(value) == dimensions[0]
            if len(dimensions) == 1:
                assert all(type(v) in (float, int) for v in value)
                return value
            return [v for row in value for v in flatten(row, dimensions[1:])]
        fp = flatten(descriptor["fp32"], shape)
        fixed = flatten(descriptor["q8_24"], shape)
        for index, (f, q) in enumerate(zip(fp, fixed)):
            source_index = index if len(shape) == 1 else (
                index//shape[1]*source["loaded_shape"][1]+index%shape[1])
            assert f == values[source_index] and type(q) is int and q == quantize(f), (name, index)
            coordinates += 1
    geometry = CONFIGS["A"]
    mapped, fixed, mapping = {}, {}, []
    inv = inventory(geometry)
    for destination in inv:
        name = destination["name"]
        source_name = name
        if name.startswith("language_model.layers."):
            fields = name.split(".")
            fields[2] = "5" if int(fields[2]) == 5 else "0"
            source_name = ".".join(fields)
        source, values = text[source_name]
        shape = destination["shape"]
        loaded = source["loaded_shape"]
        assert len(shape) == len(loaded) and all(a <= b for a, b in zip(shape, loaded))
        indices = list(range(shape[0])) if len(shape) == 1 else [
            r*loaded[1]+c for r in range(shape[0]) for c in range(shape[1])]
        selected = [values[i] for i in indices]
        mapped[name] = selected
        fixed[name] = [quantize(v) for v in selected]
        mapping.append({**destination, "source_name": source_name,
            "original_shape": source["original_shape"], "loaded_shape": loaded,
            "source_ranges_half_open": [[0, n] for n in shape],
            "source_row_stride": loaded[1] if len(loaded) == 2 else 1,
            "source_payload_sha256": source["sha256"]})
    image = execution.output/"official-weights.q824.bin"
    image.write_bytes(b"".join(struct.pack("<i", v) for e in inv for v in fixed[e["name"]]))
    hashes = {}
    for filename, data in (("official-mapping.json", mapping), ("official-inventory.json", inv)):
        p = execution.output/filename
        p.write_text(json.dumps(data, indent=2)+"\n")
        hashes[filename] = digest(p)
    hashes[image.name] = digest(image)
    provenance = {"checkpoint_sha256": actual_hash, "artifacts_sha256": hashes,
        "mapping": mapping, "text_tensors": len(text), "json_coordinates_checked": coordinates,
        "excluded_tensors": sorted(set(header)-set(text)), "audio_excluded": True,
        "local_consistency_not_remote_fetch": True,
        "layer_mapping": [0, 0, 0, 0, 0, 5],
        "weight_quantization_saturation_count": sum(quantize(v) != round(v*Q)
                                                   for values in mapped.values() for v in values)}
    (execution.output/"official-provenance.json").write_text(json.dumps(provenance, indent=2)+"\n")
    return mapped, fixed, provenance


def official_jobs(execution, raw, weights, minimal):
    g = CONFIGS["A"]
    inv = inventory(g)
    image = {}
    for e in inv:
        for i, value in enumerate(weights[e["name"]]):
            image[(0x1000+e["offset_bytes"])//4+i] = value & 0xffffffff
    cases = [([2], [7], [1]), ([2, 3], [1, 2], [1, 1]),
             ([2, 4, 7], [1, 3, 4], [1, 0, 1]),
             ([2, 3, 4, 5, 6, 7, 8, 1], [0, 1, 2, 3, 4, 5, 6, 7],
              [1, 1, 1, 1, 1, 1, 0, 0])]
    jobs = []
    for ids, positions, masks in cases[:1] if minimal else cases:
        for dim in [6] if minimal else [6, 4, 2, 1]:
            execution.remaining()
            jid = len(jobs)
            bases = [0x20000+jid*128, 0x24000+jid*128, 0x28000+jid*128]
            for base, values in zip(bases, (ids, positions, masks)):
                image.update({base//4+i: v for i, v in enumerate(values)})
            fp, details = forward_fp32(g, raw, ids, positions, masks, dim)
            before = model.SATURATION_COUNT
            integer_details = []
            oracle, _ = forward_details(g, weights, ids, positions, masks, dim, True,
                                        diagnostics=integer_details)
            saturations = model.SATURATION_COUNT-before
            jobs.append({"id": jid, "n": len(ids), "dim": dim, "wb": 0x1000,
                "bases": bases, "scratch": 0x80000, "fault": -1, "reset": 0, "error": 0,
                "fixed": oracle, "float": fp, "pre_norm": details["pre_norm"],
                "saturation": saturations > 0, "official": True,
                "tokens": ids, "positions": positions, "masks": masks,
                "fp32_diagnostics": details, "integer_diagnostics": integer_details,
                "integer_operation_saturations": saturations})
    image_path = execution.output/"official.hex"
    image_path.write_text("".join(f"@{a:x}\n{v:08x}\n" for a, v in sorted(image.items())))
    jobs_path = execution.output/"official.jobs"
    jobs_path.write_text("".join(
        f"{j['id']} {j['n']} {j['dim']} {j['wb']:x} "
        f"{j['bases'][0]:x} {j['bases'][1]:x} {j['bases'][2]:x} "
        f"{j['scratch']:x} -1 0\n" for j in jobs))
    (execution.output/"official-expected.json").write_text(json.dumps(jobs, indent=2)+"\n")
    return image_path, jobs_path, jobs


def verify_official(execution, sensitivity=False, minimal=False):
    from behavior import compile_forward, compare_trace, negative_control
    raw, weights, provenance = load_official(execution)
    binary = compile_forward(execution, "A", wrapper=True)
    image, descriptors, jobs = official_jobs(execution, raw, weights, minimal or sensitivity)
    started = time.monotonic()
    trace = execution.run("official-simulation", ["vvp", str(binary),
        f"+image={image}", f"+jobs={descriptors}", "+seed=17"])
    wall = time.monotonic()-started
    _, records, events = compare_trace(trace, jobs, CONFIGS["A"])
    results = []
    failures = []
    for job in jobs:
        rec = records[job["id"]]
        rtl = [e[3]/Q for e in rec["embeddings"]]
        fp = job["float"]
        nrtl, nfp = (math.sqrt(sum(v*v for v in vec)) for vec in (rtl, fp))
        delta = [a-b for a, b in zip(rtl, fp)]
        cosine = sum(a*b for a, b in zip(rtl, fp))/(nrtl*nfp) if nrtl*nfp else None
        metrics = {"cosine_similarity": cosine, "max_absolute_error": max(map(abs, delta)),
            "mean_absolute_error": sum(map(abs, delta))/len(delta),
            "rmse": math.sqrt(sum(v*v for v in delta)/len(delta)),
            "l2_norm_error": abs(nrtl-nfp), "rtl_norm": nrtl, "software_norm": nfp,
            "unit_norm_error": abs(nrtl-1), "exact_word_mismatches": 0}
        accepted = next(v[1] for _, k, v in events if k == "JOB" and v[0] == job["id"])
        cycles = rec["done"][0][1]-accepted
        passed = (cosine is not None and cosine >= 0.999 and
                  metrics["max_absolute_error"] <= 0.002 and
                  metrics["l2_norm_error"] <= 0.002 and metrics["unit_norm_error"] <= 0.002)
        if not passed:
            failures.append(job["id"])
        results.append({"job": job["id"], "tokens": job["tokens"], "positions": job["positions"],
            "masks": job["masks"], "output_dim": job["dim"], "fp32": fp,
            "rtl_q824": [e[3] for e in rec["embeddings"]], "rtl": rtl, "oracle_q824": job["fixed"],
            "metrics": metrics, "status": "passed" if passed else "failed",
            "integer_operation_saturations": job["integer_operation_saturations"],
            "intermediate_diagnostics": {
                "fp32": job["fp32_diagnostics"], "integer": job["integer_diagnostics"]},
            "cycles": {"descriptor_edge": accepted, "completion_edge": rec["done"][0][1],
                "completion_latency": cycles,
                "first_embedding_latency": rec["embeddings"][0][1]-accepted,
                "last_embedding_latency": rec["embeddings"][-1][1]-accepted,
                "token_count": job["n"], "valid_token_count": sum(job["masks"]),
                "cycles_per_token": cycles/job["n"],
                "cycles_per_valid_token": cycles/sum(job["masks"]),
                "tokens_per_cycle": job["n"]/cycles, "jobs_per_cycle": 1/cycles}})
    report = {"schema": 1, "producing_attempt": str(execution.output),
        "receipt": str(execution.output/"receipt.json"), "source_sha256": execution.sources,
        "labels": ["Software Layer (Official HuggingFace FP32/BF16 Weights)",
                   "Hardware RTL Output (Official HuggingFace Quantized Weights)"],
        "scope": "Reduced mapped authentic slice; not full-checkpoint/upstream executable parity, "
                 "application embedding quality or physical speed",
        "geometry": CONFIGS["A"].__dict__, "provenance": provenance,
        "thresholds": {"cosine_min": 0.999, "max_absolute_error": 0.002, "norm_error": 0.002},
        "cycle_formula": "destination accepted rising edge minus descriptor accepted edge",
        "stalls": "All memory, embedding and completion stalls included",
        "clock": "10 ns simulation convention only; no silicon frequency claim",
        "simulator_wall_seconds": wall, "jobs": results, "failed_jobs": failures,
        "aggregate": {"jobs": len(results),
            "max_absolute_error": max(r["metrics"]["max_absolute_error"] for r in results),
            "mean_absolute_error": max(r["metrics"]["mean_absolute_error"] for r in results),
            "rmse": max(r["metrics"]["rmse"] for r in results),
            "l2_norm_error": max(r["metrics"]["l2_norm_error"] for r in results),
            "exact_word_mismatches": 0,
            "min_cosine_similarity": min(
                (r["metrics"]["cosine_similarity"] for r in results
                 if r["metrics"]["cosine_similarity"] is not None), default=None)}}
    target = execution.output/"official_weights_comparison.json"
    target.write_text(json.dumps(report, indent=2)+"\n")
    if failures:
        raise AssertionError(f"official FP32 thresholds failed for jobs {failures}; see {target}")
    if sensitivity:
        negative_control(execution, trace, jobs, CONFIGS["A"])


def diagnose_official(execution, report_path):
    path = Path(report_path).resolve()
    root = Path(".").resolve()
    if not path.is_relative_to(root/"evidence"/"preparation"):
        raise ValueError("diagnostic input must be a project preparation report")
    execution.sources[str(path.relative_to(root))] = digest(path)
    report = load_json(path.read_text())
    raw, weights, _ = load_official(execution)
    results = []
    for job in report["jobs"]:
        if job["status"] != "failed":
            continue
        execution.remaining()
        diagnostic, _ = forward_details(CONFIGS["A"], weights, job["tokens"],
            job["positions"], job["masks"], job["output_dim"], False,
            floating_epsilon=17/Q)
        raw64, _ = forward_details(CONFIGS["A"], weights, job["tokens"],
            job["positions"], job["masks"], job["output_dim"], False,
            raw_weights=raw, floating_epsilon=1e-6)
        raw64_hardware_epsilon, _ = forward_details(CONFIGS["A"], weights, job["tokens"],
            job["positions"], job["masks"], job["output_dim"], False,
            raw_weights=raw, floating_epsilon=17/Q)
        results.append({"job": job["job"],
            "label": "Historical binary64 mathematical diagnostic on quantized inputs, epsilon 17/2^24; "
                     "not the required raw-weight FP32 reference",
            "diagnostic": diagnostic, "retained_rtl": job["rtl"], "required_fp32": job["fp32"],
            "diagnostic_vs_rtl_max_error": max(abs(a-b) for a, b in zip(diagnostic, job["rtl"])),
            "diagnostic_vs_fp32_max_error": max(abs(a-b) for a, b in zip(diagnostic, job["fp32"])),
            "binary64_raw_weights_epsilon_1e6": raw64,
            "binary64_raw_vs_fp32_max_error": max(abs(a-b) for a, b in zip(raw64, job["fp32"])),
            "binary64_raw_weights_epsilon_17_over_q": raw64_hardware_epsilon,
            "epsilon_only_max_difference": max(abs(a-b) for a, b in zip(raw64, raw64_hardware_epsilon)),
            "hardware_epsilon_raw_vs_rtl_max_error": max(
                abs(a-b) for a, b in zip(raw64_hardware_epsilon, job["rtl"])),
            "layer_hidden_max_differences": [
                max(abs(a-b/Q) for fa, ia in zip(f["hidden"], i["hidden_q824"])
                    for a, b in zip(fa, ia))
                for f, i in zip(job["intermediate_diagnostics"]["fp32"]["layer_hidden"],
                                job["intermediate_diagnostics"]["integer"])]})
    assert results, "no retained failed job to diagnose"
    (execution.output/"diagnosis.json").write_text(json.dumps({
        "retained_report": str(path.relative_to(root)), "retained_report_sha256": digest(path),
        "fresh_dut_execution": False, "results": results}, indent=2)+"\n")
