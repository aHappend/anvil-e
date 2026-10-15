"""Serial cursor comparison using retained execution and independent oracles."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture
from verify import ROOT, Run, execute_fixture, rtl_files


BEFORE = ROOT / (
    "evidence/preparation/q40-response-edge-mutation-schedule-001/"
    "full-local-schedule/anvil_e2_matvec.sv")
BEFORE_SHA = "b8f9f84f2e53554a190800e83e3879d9f64dd4206f2c21f7d919fad7fa57bba9"


class ObservedRun(Run):
    def command(self, argv, name, **kwargs):
        if name.endswith("-compile"):
            tb = Path(argv[-1])
            trace = self.directory / (name.removesuffix("-compile") + ".transactions")
            text = tb.read_text()
            marker = "if(mem_req_valid && mem_req_ready) begin"
            assert text.count(marker) == 1
            text = text.replace(marker, marker + """
   $fdisplay(transaction_fd,"Q %0d %b %h %h",
             cycles,mem_req_write,mem_req_addr,mem_req_wdata);
""")
            marker = "if(mem_rsp_valid && mem_rsp_ready) begin"
            assert text.count(marker) == 1
            text = text.replace(marker, marker + """
   $fdisplay(transaction_fd,"R %0d %h %b",cycles,mem_rsp_rdata,mem_rsp_error);
""")
            text = text.replace("module tb;", f"""
module tb;
integer transaction_fd;
initial begin
 transaction_fd=$fopen("{trace}","w");
 if(!transaction_fd) $fatal(1,"TRANSACTION_FILE");
end
""", 1)
            tb.write_text(text)
            self.receipt.setdefault("generated_source_sha256", {})[
                str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
            self.save()
        return super().command(argv, name, **kwargs)


def paired(run, implementation="matvec", configuration=None):
    before = BEFORE
    before_sha = BEFORE_SHA
    if implementation == "attention":
        before = ROOT / (
            "evidence/preparation/q40-cursor-serial-paired-001/"
            "before-rtl/anvil_e2_attention.sv")
        before_sha = "628391f3c0f69d8d4ebaf2e1176718ef30bd0f6a84e430b5024e733d47baa575"
    if implementation == "attention-divider":
        before = ROOT / (
            "evidence/preparation/q40-attention-cursor-mutation-schedule-001/"
            "full-local-schedule/anvil_e2_attention.sv")
        before_sha = "b19740f06fe41517f8f72b83880007befeb8cfff14b52b50046fd5805025327a"
    assert hashlib.sha256(before.read_bytes()).hexdigest() == before_sha
    baseline = run.directory / "before-rtl"
    baseline.mkdir()
    for source in rtl_files():
        shutil.copyfile(before if source.name == before.name else source,
                        baseline / source.name)
    if implementation == "attention-divider":
        path = baseline / before.name
        text = path.read_text()
        mutation = "else if (full_mode && VISION)"
        assert text.count(mutation) == 1
        path.write_text(text.replace(mutation, "else if (full_mode)"))
        assert hashlib.sha256(path.read_bytes()).hexdigest() == (
            "20dffa09c1b2999fbe6017d509cae4efd54e43d45eb298e613ee95cd7e58c2ab")
        run.receipt["baseline_reconstruction"] = {
            "restored_disposable_schedule_mutation": mutation,
            "required_original_sha256": "20dffa09c1b2999fbe6017d509cae4efd54e43d45eb298e613ee95cd7e58c2ab",
            "identity_receipt": "evidence/preparation/q40-public-phase-cost-b17-analysis-001/receipt.json",
        }
    run.receipt["comparison_sources"] = {
        "before_origin": str(before.relative_to(ROOT)),
        "before_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted(baseline.glob("*.sv"))},
        "only_replaced_implementation": before.name,
        "accepted_rtl_unchanged": True,
        "acceptance_evidence": False,
        "concurrency_adopted": False,
    }
    run.receipt["related_evidence"] = [
        "evidence/preparation/q40-cursor-serial-paired-001/receipt.json",
        "evidence/preparation/q40-projection-attention-b17-001/receipt.json",
    ]
    run.save()
    results = []
    for label, seed in (("B", 17), ("C", 89)):
        if configuration is not None and label != configuration:
            continue
        arms = []
        for arm, directory in (("before", baseline), ("after", None)):
            name = f"{arm}-{label}-s{seed}-m2-d12"
            child = ObservedRun(run.directory / name, deadline=run.deadline)
            child.receipt["tools"] = run.receipt["tools"]
            child.receipt["compiled_source_sha256"] = {
                str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in rtl_files(directory)}
            start = time.monotonic()
            try:
                execute_fixture(child, name, Fixture(CONFIGS[label], seed, 2),
                                directory=directory)
            except Exception as error:
                child.finish("failed", str(error))
                raise
            child.finish("passed")
            trace = child.directory / (name + ".transactions")
            data = trace.read_bytes()
            records = data.splitlines()
            coverage = child.receipt["coverage"][0]
            assert sum(r.startswith(b"Q ") for r in records) == coverage["completion"][1]
            assert sum(r.startswith(b"R ") for r in records) == coverage["completion"][2]
            arms.append({
                "arm": arm, "elapsed_s": time.monotonic()-start,
                "receipt": str((child.directory / "receipt.json").relative_to(ROOT)),
                "transactions_sha256": hashlib.sha256(data).hexdigest(),
                "transaction_records": len(records),
                "simulation_s": child.receipt["executions"][-1]["ended_at"]
                                - child.receipt["executions"][-1]["started_at"],
                "coverage": coverage,
            })
            run.receipt["coverage"].extend(child.receipt["coverage"])
            run.receipt.setdefault("completed_arms", []).append(arms[-1])
            run.save()
        identical_cycles = arms[0]["transactions_sha256"] == arms[1]["transactions_sha256"]
        if implementation == "attention-divider":
            records = []
            for arm in arms:
                trace = ROOT / arm["receipt"]
                trace = trace.parent / (trace.parent.name + ".transactions")
                records.append([line.split()[:1] + line.split()[2:]
                                for line in trace.read_bytes().splitlines()])
            assert records[0] == records[1], "request/response order or payload changed"
        else:
            assert identical_cycles, "request/response cycle, order or payload changed"
        outputs = []
        compared_prefixes = (b"W ", b"E ") if implementation == "attention-divider" else (
            b"W ", b"E ", b"C ")
        for arm in arms:
            path = ROOT / arm["coverage"]["transcript"]
            outputs.append([line for line in path.read_bytes().splitlines()
                            if line.startswith(compared_prefixes)
                            or line == b"TRANSCRIPT_COMPLETE"])
        assert outputs[0] == outputs[1], "complete scratch/output history changed"
        results.append({"configuration": label, "seed": seed, "mode": 2,
                        "arms": arms, "identical_complete_histories": True,
                        "identical_request_response_order_and_payloads": True,
                        "identical_request_response_cycles": identical_cycles})
        run.receipt["paired_comparison"] = results
        run.save()
    before = sum(r["arms"][0]["elapsed_s"] for r in results)
    after = sum(r["arms"][1]["elapsed_s"] for r in results)
    run.receipt["timing_observation"] = {
        "before_s": before, "after_s": after, "saved_s": before-after,
        "single_measurement_not_causal": True,
        "aggregate_headroom_established": False,
        "reason": "Two fixtures alone do not establish full-suite budget compliance.",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--implementation", choices=("matvec", "attention", "attention-divider"),
                        default="matvec")
    parser.add_argument("--configuration", choices=("B", "C"))
    parser.add_argument("--repair-of")
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    run = Run(directory, repair_of=args.repair_of)
    try:
        run.tools(("python3", "iverilog", "vvp"))
        paired(run, args.implementation, args.configuration)
    except Exception as error:
        (directory / "diagnostic.stderr").write_text(traceback.format_exc())
        run.finish("failed", str(error))
        traceback.print_exc()
        return 1
    run.finish("passed")
    print(json.dumps(run.receipt["timing_observation"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
