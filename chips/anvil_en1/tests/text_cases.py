"""Source-bound independent fixtures shared by candidate and bus baseline runs."""

import hashlib
import itertools
import json
from pathlib import Path

from experiment import ROOT
from text_fixture import make_text_image
from text_reference import prefix_logits


REFERENCE_SOURCES = (
    "tests/numerical_reference.py", "tests/text_reference.py",
    "tests/text_fixture.py", "tests/text_cases.py",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(exp, models, precisions, seeds, contexts):
    images = exp.out / "checkpoint-images"
    images.mkdir()
    manifest = {
        "schema": 1,
        "reference_source_sha256": {name: digest(ROOT / name) for name in REFERENCE_SOURCES},
        "cases": [],
    }
    for model, precision, seed in itertools.product(models, precisions, seeds):
        image, tensors = make_text_image(model, precision, seed)
        stem = f"m{model}-p{precision}-s{seed}"
        image_path = images / (stem + ".bin")
        image_path.write_bytes(image)
        expectations = prefix_logits(tensors, model, seed, contexts)
        for tokens in contexts:
            name = stem + f"-n{tokens}"
            expected_path = exp.out / (name + "-expected.json")
            expected_path.write_text(json.dumps(expectations[tokens]) + "\n")
            manifest["cases"].append({
                "name": name, "model": model, "precision": precision, "seed": seed,
                "tokens": tokens,
                "image": str(image_path.relative_to(ROOT)),
                "image_sha256": digest(image_path),
                "expected": str(expected_path.relative_to(ROOT)),
                "expected_sha256": digest(expected_path),
            })
        print("PROGRESS independent prefix references=" + stem, flush=True)
    path = exp.out / "text-cases.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    exp.receipt["independent_fixture_manifest"] = {
        "path": str(path.relative_to(ROOT)), "sha256": digest(path)}
    exp.save()
    return path


def load(path, models, precisions, seeds, contexts):
    path = Path(path)
    if path.is_absolute():
        path = path.relative_to(ROOT)
    if ".." in path.parts:
        raise ValueError("fixture manifest must be project-relative")
    manifest = json.loads((ROOT / path).read_text())
    if manifest["schema"] != 1 or manifest["reference_source_sha256"] != {
            name: digest(ROOT / name) for name in REFERENCE_SOURCES}:
        raise RuntimeError("independent fixture source binding differs")
    indexed = {}
    for case in manifest["cases"]:
        key = tuple(case[field] for field in ("model", "precision", "seed", "tokens"))
        if key in indexed:
            raise RuntimeError("duplicate independent fixture cell")
        indexed[key] = case
    result = []
    for key in itertools.product(models, precisions, seeds, contexts):
        case = dict(indexed[key])
        for field in ("image", "expected"):
            artifact = Path(case[field])
            if artifact.is_absolute() or ".." in artifact.parts:
                raise ValueError("independent fixture artifact must be project-relative")
            if digest(ROOT / artifact) != case[field + "_sha256"]:
                raise RuntimeError("independent fixture hash differs: " + str(artifact))
        case["reference"] = json.loads((ROOT / case["expected"]).read_text())
        result.append(case)
    return result
