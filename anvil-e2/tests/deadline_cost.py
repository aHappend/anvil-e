"""Bounded watchdog proof and serial cost measurement; advisory, not acceptance."""
import time

ENTRY_MONOTONIC = time.monotonic()
ENTRY_PYTHON_CPU = time.process_time()

import argparse
import hashlib
import inspect
import json
import os
from pathlib import Path
import resource
import selectors
import subprocess
import sys
import traceback
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify
from model import CONFIGS, Fixture, Integer
from scheduler_cost import capacity
from verify import ROOT, Run, execute_fixture

AGGREGATE = "evidence/preparation/q40-response-edge-aggregate-cost-001/receipt.json"


class PhaseRun(Run):
    """Observe only flushed public events; never change responder scheduling."""

    def instrument(self, tb):
        f, c = self.fixture, self.fixture.c
        layout = f.layout
        regions = list(layout)
        declarations, branches = [], []
        self.receipt["milestone_regions"] = []
        for index, region in enumerate(regions[:-1]):
            lo, hi = layout[region], layout[regions[index+1]]
            words = (hi-lo)//4
            assert words > 0
            if region in ("q", "k", "v"):
                n = len(f.ids)+c.VISION_SOFT_TOKENS+2
                ends, total = [], 0
                for layer in range(c.TEXT_LAYERS):
                    d = c.FULL_HEAD_DIM if layer % 6 == 5 else c.LOCAL_HEAD_DIM
                    heads = (c.TEXT_Q_HEADS if region == "q" else
                             c.FULL_KV_HEADS if layer % 6 == 5 else c.LOCAL_KV_HEADS)
                    ends += [total+1, total+n*heads*d]
                    total += n*heads*d
                predicate = " || ".join(f"phase_count_{index}=={x}" for x in ends)
            else:
                predicate = f"phase_count_{index}%{words}==1 || phase_count_{index}%{words}==0"
            declarations.append(f"integer phase_count_{index}=0;")
            branches.append(f"""
 if(mem_req_addr>=64'h{lo:x} && mem_req_addr<64'h{hi:x}) begin
  phase_count_{index}=phase_count_{index}+1;
  if({predicate})
   begin
    $display("PHASE WRITE {region} %0d %0d %h %0d %0d",
      phase_count_{index},cycles,mem_req_addr,requests,responses);
    $fflush();
   end
 end
""")
            self.receipt["milestone_regions"].append(
                {"region": region, "start": lo, "end": hi, "words": words})
        starts = [("patch", f.offsets["patch"]), ("vision0", f.offsets["v0.input"]),
                  ("bridge", f.offsets["bridge"]), ("ple", f.offsets["ple_model"])]
        starts += [(f"text{i}", f.offsets[f"t{i}.input"]) for i in range(c.TEXT_LAYERS)]
        starts += [("final_norm", f.offsets["norm"])]
        for index, (label, address) in enumerate(starts):
            declarations.append(f"reg phase_read_{index}=0;")
            branches.append(f"""
 if(!mem_req_write && mem_req_addr==64'h{address:x} && !phase_read_{index}) begin
  phase_read_{index}=1;
  $display("PHASE READ {label} 1 %0d %h %0d %0d",
    cycles,mem_req_addr,requests,responses);
  $fflush();
 end
""")
        text = tb.read_text()
        marker = "integer requests=0,"
        assert text.count(marker) == 1
        text = text.replace(marker, "\n".join(declarations)+"\n"+marker)
        marker = '     $display("W %h %h",mem_req_addr,mem_req_wdata);'
        assert text.count(marker) == 1
        # Region counters run only on successful scratch writes.
        writes = "".join(b for b in branches if "phase_count_" in b)
        text = text.replace(marker, marker+writes)
        marker = "   mem_rsp_rdata=read_value;"
        assert text.count(marker) == 1
        text = text.replace(marker, "".join(b for b in branches if "phase_read_" in b)+marker)
        marker = '   $display("E %0d %h %0d",emb_index,emb_data,emb_last);'
        assert text.count(marker) == 1
        text = text.replace(marker, marker+"""
   if(emb_index==0 || emb_last) begin
    $display("PHASE OUTPUT embedding %0d %0d 0 %0d %0d",
      emb_index,cycles,requests,responses); $fflush();
   end
""")
        marker = '   $display("C %0d'
        assert text.count(marker) == 1
        text = text.replace(marker, """
   $display("PHASE DONE completion 1 %0d 0 %0d %0d",
     cycles,requests,responses); $fflush();
""" + marker)
        tb.write_text(text)
        self.receipt["generated_source_sha256"] = {
            str(tb.relative_to(ROOT)): hashlib.sha256(tb.read_bytes()).hexdigest()}
        self.save()

    def command(self, argv, name, **kwargs):
        if name.endswith("-compile"):
            self.instrument(Path(argv[-1]))
        if not name.endswith("-simulate"):
            return super().command(argv, name, **kwargs)
        timeout = kwargs["timeout"]
        assert timeout == 45
        stdout, stderr = self.directory/(name+".stdout"), self.directory/(name+".stderr")
        record = {"argv": list(map(str, argv)), "cwd": str(ROOT),
                  "requested_timeout_s": timeout, "stdout": str(stdout.relative_to(ROOT)),
                  "stderr": str(stderr.relative_to(ROOT)), "started_at": time.time()}
        self.receipt["executions"].append(record)
        self.save()
        began = time.monotonic()
        effective = min(timeout, self.deadline-began)
        assert effective > 0
        stop = min(began+effective, self.deadline)
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        process = None
        samples, overhead_wall, overhead_cpu = [], 0.0, 0.0
        ticks = os.sysconf("SC_CLK_TCK")
        byte_count = 0

        def sample(fields):
            nonlocal overhead_wall, overhead_cpu
            start, cpu = time.monotonic(), time.process_time()
            raw = Path(f"/proc/{process.pid}/stat").read_text()
            # Fields after comm begin at Linux proc field 3.
            stat = raw[raw.rindex(")")+2:].split()
            samples.append({"event": fields, "observed_monotonic": start,
                            "elapsed_s": start-began, "child_user_cpu_s": int(stat[11])/ticks,
                            "child_system_cpu_s": int(stat[12])/ticks,
                            "proc_stat": raw.strip()})
            overhead_wall += time.monotonic()-start
            overhead_cpu += time.process_time()-cpu

        try:
            with stdout.open("wb") as out, stderr.open("wb") as err, selectors.DefaultSelector() as sel:
                launch = time.monotonic()
                process = subprocess.Popen(record["argv"], cwd=ROOT,
                                           stdout=subprocess.PIPE, stderr=err)
                record.update(pid=process.pid, effective_timeout_s=effective, timeout_s=effective)
                sel.register(process.stdout, selectors.EVENT_READ)
                sample(["LAUNCH"])
                pending = b""
                while sel.get_map():
                    remaining = stop-time.monotonic()
                    if remaining <= 0:
                        record["timed_out"] = True
                        raise AssertionError(f"tool timeout: {name}")
                    for key, _ in sel.select(remaining):
                        block = os.read(key.fd, 65536)
                        if not block:
                            sel.unregister(key.fileobj)
                            continue
                        io_start, io_cpu = time.monotonic(), time.process_time()
                        out.write(block)
                        byte_count += len(block)
                        assert byte_count+err.tell() <= 1048576, "diagnostic output limit"
                        pending += block
                        lines = pending.split(b"\n")
                        pending = lines.pop()
                        overhead_wall += time.monotonic()-io_start
                        overhead_cpu += time.process_time()-io_cpu
                        for line in lines:
                            if line.startswith(b"PHASE "):
                                sample(line.decode().split()[1:])
                assert not pending, "partial final simulator line"
                process.wait(timeout=max(0, stop-time.monotonic()))
                record["timed_out"] = False
                assert process.returncode == 0, f"{name}: exit {process.returncode}"
        finally:
            if process is not None:
                if process.returncode is None:
                    process.kill()
                process.wait()
                if process.stdout is not None:
                    process.stdout.close()
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            record.update(exit_code=process.returncode if process else None,
                          ended_at=time.time(), elapsed_s=time.monotonic()-began,
                          child_user_cpu_s=after.ru_utime-usage.ru_utime,
                          child_system_cpu_s=after.ru_stime-usage.ru_stime,
                          stdout_bytes=stdout.stat().st_size if stdout.exists() else 0,
                          stderr_bytes=stderr.stat().st_size if stderr.exists() else 0,
                          cleanup={"direct_child_reaped": process is not None and process.returncode is not None})
            self.receipt["phase_observations"] = samples
            self.receipt["instrumentation_overhead"] = {
                "observer_handling_wall_s": overhead_wall, "observer_handling_cpu_s": overhead_cpu,
                "simulator_instrumentation": "extra counters, comparisons, sparse displays/flushes; not isolated by this single run",
                "sampling_limits": "proc CPU ticks; pipe delivery/OS scheduling delay; intervals combine DUT and harness"}
            self.save()
        return stdout.read_text(), stderr.read_text(), process.returncode


def phases(run):
    run.tools(("python3", "iverilog", "vvp"))
    fixture = Fixture(CONFIGS["B"], 17, 2)
    child = PhaseRun(run.directory/"B-s17-m2-d12", budget=100,
                     deadline=run.deadline, repair_of=AGGREGATE)
    child.fixture = fixture
    child.receipt["tools"] = run.receipt["tools"]
    try:
        execute_fixture(child, "B-s17-m2-d12", fixture)
        samples = child.receipt["phase_observations"]
        labels = {tuple(s["event"][:2]) for s in samples}
        required = {("READ", x) for x in
                    ["patch", "vision0", "bridge", "ple", "final_norm"]+
                    [f"text{i}" for i in range(fixture.c.TEXT_LAYERS)]}
        required |= {("WRITE", r) for r in fixture.layout if r != "end"}
        required |= {("OUTPUT", "embedding"), ("DONE", "completion")}
        assert required <= labels, f"missing phase milestones: {required-labels}"
        # Independently reconcile every region's observed write count to the
        # complete exact-oracle write histories, not implementation state.
        _, writes = fixture.run(Integer())
        for region in child.receipt["milestone_regions"]:
            expected = sum(len(v) for a, v in writes.items()
                           if region["start"] <= a < region["end"])
            actual = [int(s["event"][2]) for s in samples
                      if s["event"][:2] == ["WRITE", region["region"]]]
            assert actual and actual[-1] == expected, f"milestone extent: {region}"
        child.receipt["assertions"].append(
            "all required public phase milestones present; terminal region counts match exact write histories")
    except Exception as error:
        child.finish("failed", str(error))
        raise
    else:
        child.finish("passed")
        run.receipt["coverage"].extend(child.receipt["coverage"])
    finally:
        run.receipt["phase_receipt"] = str((child.directory/"receipt.json").relative_to(ROOT))
        run.save()


def phase_analysis(run, receipt_path):
    run.receipt["analysis_python_version"] = sys.version
    path = (ROOT/receipt_path).resolve()
    assert path.is_relative_to(ROOT/"evidence/preparation")
    original = json.loads(path.read_text())
    assert original["status"] == "passed" and len(original["coverage"]) == 1
    run.receipt["analyzed_receipt"] = {
        "path": str(path.relative_to(ROOT)),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "observation_source_sha256": original["source_sha256"]}
    changes = {p for p, h in original["source_sha256"].items()
               if run.receipt["source_sha256"].get(p) != h}
    assert changes <= {"tests/deadline_cost.py"}, f"unexpected source change: {changes}"
    run.receipt["analysis_only_source_changes"] = sorted(changes)
    bindings = {}
    for execution in original["executions"]:
        for stream in ("stdout", "stderr"):
            artifact = ROOT/execution[stream]
            bindings[execution[stream]] = hashlib.sha256(artifact.read_bytes()).hexdigest()
    run.receipt["analyzed_artifact_sha256"] = bindings
    samples = original["phase_observations"]

    def event(kind, label, ordinal="1"):
        matches = [s for s in samples if s["event"][:3] == [kind, label, ordinal]]
        assert len(matches) == 1, (kind, label, ordinal)
        return matches[0]

    boundaries = [
        ("patch projection and position additions", event("READ", "patch"), event("WRITE", "v0", "160")),
        ("vision Q/K/V production", event("READ", "vision0"), event("WRITE", "vv", "160")),
        ("vision post-Q/K/V through last layer-result write",
         event("WRITE", "vv", "160"), event("WRITE", "v1", "160")),
        ("bridge including remaining spatial input reads", event("WRITE", "v1", "160"),
         event("WRITE", "soft", "12")),
        ("fusion", event("WRITE", "soft", "12"), event("WRITE", "x0", "27")),
        ("PLE", event("WRITE", "x0", "27"), event("WRITE", "ple", "162")),
    ]
    for layer in range(6):
        boundaries.append((f"text layer {layer}", event("READ", f"text{layer}"),
                           event("READ", f"text{layer+1}") if layer < 5 else
                           event("READ", "final_norm")))
    boundaries.append(("final norm/projection/pooling/L2 to first accepted output",
                       event("READ", "final_norm"), event("OUTPUT", "embedding", "0")))
    run.receipt["phase_intervals"] = [
        {"interval": label, "begin": a["event"], "end": b["event"],
         "elapsed_s": b["elapsed_s"]-a["elapsed_s"],
         "child_user_cpu_s": b["child_user_cpu_s"]-a["child_user_cpu_s"],
         "child_system_cpu_s": b["child_system_cpu_s"]-a["child_system_cpu_s"],
         "cycles": int(b["event"][3])-int(a["event"][3])}
        for label, a, b in boundaries]
    run.receipt["instrumentation_overhead"] = original["instrumentation_overhead"]
    run.receipt["interpretation"] = {
        "attribution_limit": "Intervals include DUT, responder, monitors and diagnostic instrumentation; no causal per-operator attribution.",
        "candidate": "Designer-only hypothesis: isolate anvil_e2_attention divider clock while its owner is in Q/K/V and metadata memory phases; it currently receives the attention clock even in divider IDLE.",
        "candidate_status": "Not implemented, not a demonstrated useful target or budget remedy; public phase timing cannot isolate idle-divider event cost.",
        "correctness_obligations": [
            "Registered wake ownership before SCORE/FINISH divider input acceptance; no lost or duplicate input/output.",
            "Exact Q80 dot scaling, nearest-even division, saturation and weighted normalization unchanged.",
            "Preserve first-detected errors, zero-denominator behavior, stalls, asynchronous reset and canceled jobs.",
            "No changed public pins, scratch materialization/traffic/geometry or frame-sized storage.",
            "Designer implementation followed immediately by independent Verifier arithmetic/protocol, full fixtures, sensitivity and zero-latch synthesis; measure actual budget benefit, not assumed edge-count savings."]}
    run.receipt["assertions"].append(
        "read-only interval arithmetic from a complete source-bound observation; no simulator rerun")
    run.receipt["coverage"] = original["coverage"]
    run.save()


class CostRun(Run):
    def command(self, argv, name, **kwargs):
        if name.endswith("-compile"):
            tb = Path(argv[-1])
            text = tb.read_text()
            marker = '   $display("C %0d'
            assert text.count(marker) == 1
            text = text.replace(marker, '''   $display("DIAGNOSTIC_COUNTS %0d %0d %0d",
     cycles,requests,responses);
''' + marker)
            marker = "endmodule"
            assert text.count(marker) == 1
            text = text.replace(marker, """
always @(posedge clk) if(cycles>0 && cycles%10000==0) begin
 $display("DIAGNOSTIC_PROGRESS %0d %0d %0d",cycles,requests,responses);
 $fflush();
end
endmodule
""")
            tb.write_text(text)
            self.receipt.setdefault("generated_source_sha256", {})[
                str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
            self.save()
        return super().command(argv, name, **kwargs)


def production_limits(run):
    signature = inspect.signature(Run)
    assert signature.parameters["budget"].default == 110, "production default budget"
    limits = {"constructor": [], "entry_points": [], "fixture_calls": []}
    for name, kwargs in (("default", {}), ("maximum", {"budget": 110}),
                         ("inherited", {"deadline": run.deadline})):
        began = time.monotonic()
        child = Run(run.directory/("production-"+name), **kwargs)
        assert child.receipt["timeout_s"] == 110
        assert began < child.deadline <= time.monotonic()+110
        if name == "inherited":
            assert child.deadline == run.deadline, "inherited deadline renewed"
        child.receipt["assertions"].append("production 110-second constructor/deadline bound")
        child.finish("passed")
        limits["constructor"].append({"case": name, "budget_s": 110,
                                      "deadline": child.deadline})
    for index, budget in enumerate((0, -1, 110.001, 3600, 86400,
                                    float("inf"), float("nan"))):
        directory = run.directory/f"production-invalid-{index}"
        try:
            Run(directory, budget=budget)
        except AssertionError as error:
            assert str(error) == "runner budget must be bounded by 110 seconds"
            assert not directory.exists(), "invalid budget created artifacts"
        else:
            raise AssertionError(f"production accepted invalid budget: {budget}")
    limits["constructor_rejected_budgets"] = [
        "0", "-1", "110.001", "3600", "86400", "inf", "nan"]

    class Observed(BaseException):
        pass

    for argv, expected in (
            (["--probe", "A", "--output", str(run.directory/"entry-A")], 100),
            (["--probe", "startup", "--output", str(run.directory/"entry-startup")], 100),
            (["--check", "behavior"], 110),
            (["--check", "sensitivity"], 110),
            (["--check", "synthesis"], 110),
            ([], 110)):
        calls = []

        def capture_constructor(*args, **kwargs):
            bound = signature.bind(*args, **kwargs)
            bound.apply_defaults()
            calls.append(bound.arguments)
            raise Observed()

        with patch.object(verify, "Run", capture_constructor), \
                patch.object(sys, "argv", ["tests/verify.py", *argv]):
            try:
                verify.main()
            except Observed:
                pass
            else:
                raise AssertionError(f"entry point did not construct runner: {argv}")
        assert len(calls) == 1 and calls[0]["budget"] == expected, (
            f"production entry budget: {argv}: {calls}")
        assert calls[0]["deadline"] is None
        limits["entry_points"].append({"argv": argv, "budget_s": expected})

    for startup, expected in ((False, 45), (True, 30)):
        directory = run.directory/("callsite-startup" if startup else "callsite-normal")
        directory.mkdir()
        commands = []

        def capture_command(argv, name, **kwargs):
            commands.append({"argv": list(map(str, argv)), "name": name, **kwargs})
            if argv[0] == "vvp":
                raise Observed()
            assert argv[0] == "iverilog"
            return "", "", 0

        fixture = SimpleNamespace(run=lambda arithmetic: ([0], {}),
                                  dimension=1, mem={}, layout={"end": verify.SCRATCH})
        observer = SimpleNamespace(directory=directory, timing=lambda *args: None,
                                   command=capture_command)
        with patch.object(verify, "bench", return_value="endmodule\n"):
            try:
                verify.execute_fixture(observer, "production-limits", fixture,
                                       startup_diagnostic=startup)
            except Observed:
                pass
            else:
                raise AssertionError("fixture did not request simulation")
        assert len(commands) == 2
        assert commands[0]["name"] == "production-limits-compile"
        assert commands[0]["timeout"] == 20, "production compilation watchdog"
        assert commands[1]["name"] == "production-limits-simulate"
        assert commands[1]["timeout"] == expected, "production simulation watchdog"
        assert commands[1]["argv"][1:-1] == (["-v"] if startup else [])
        limits["fixture_calls"].append({"startup": startup, "commands": commands})
    run.receipt["production_limits"] = limits
    run.receipt["assertions"].append(
        "actual production constructor default/maximum and invalid budgets; preparation/normal "
        "entry-point budgets; execute_fixture compilation/normal/startup watchdog call sites "
        "executed with intercepted tool launches (no HDL compilation or simulation)")
    run.save()


def watchdog(run):
    run.tools(("python3",))
    production_limits(run)
    for name, budget, requested in (("child-limit", 4, 0.4),
                                    ("common-limit", 0.4, 4)):
        child = Run(run.directory/name, budget=budget, deadline=run.deadline,
                    repair_of=AGGREGATE)
        child.receipt["tools"] = run.receipt["tools"]
        child.save()
        code = ("import os,sys,time; "
                "print('FLUSHED_STDOUT',os.getpid(),flush=True); "
                "print('FLUSHED_STDERR',file=sys.stderr,flush=True); "
                "time.sleep(30)")
        try:
            child.command([sys.executable, "-c", code], name, timeout=requested)
        except AssertionError as error:
            record = child.receipt["executions"][-1]
            assert str(error) == f"tool timeout: {name}"
            assert record["timed_out"] and record["exit_code"] != 0
            assert record["cleanup"]["direct_child_reaped"]
            assert record["effective_timeout_s"] <= requested
            if name == "child-limit":
                assert record["effective_timeout_s"] == requested
            else:
                assert 0 < record["effective_timeout_s"] < requested
            assert record["elapsed_s"] < record["effective_timeout_s"]+1
            out = (ROOT/record["stdout"]).read_text()
            err = (ROOT/record["stderr"]).read_text()
            assert out.startswith("FLUSHED_STDOUT ") and err == "FLUSHED_STDERR\n"
            pid = int(out.split()[1])
            assert pid == record["pid"]
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError(f"child still exists: {pid}")
            child.receipt["assertions"].append(
                "binding watchdog timed out; direct child absent/reaped; both flushed outputs retained")
            child.finish("expected-timeout")
        else:
            child.finish("failed", "overlong child unexpectedly completed")
            raise AssertionError("watchdog failed to interrupt overlong child")
        run.receipt["coverage"].append({
            "case": name, "receipt": str((child.directory/"receipt.json").relative_to(ROOT)),
            "requested_timeout_s": requested,
            "effective_timeout_s": record["effective_timeout_s"],
            "elapsed_s": record["elapsed_s"], "timeout_cleanup_and_partial_output": True})
        run.save()
    assert len(run.receipt["coverage"]) == 2


def observations(run, name):
    path = run.directory/(name+"-simulate.stdout")
    if not path.exists():
        return {"simulation_launched": False}
    lines = path.read_bytes().splitlines(keepends=True)
    result = {"simulation_launched": True, "complete": False,
              "complete_write_records": 0, "embedding_records": 0,
              "last_observed_cycles_requests_responses": None,
              "partial_final_line": bool(lines and not lines[-1].endswith(b"\n"))}
    for line in lines:
        if not line.endswith(b"\n"):
            continue
        fields = line.split()
        if fields and fields[0] in (b"DIAGNOSTIC_PROGRESS", b"DIAGNOSTIC_COUNTS"):
            result["last_observed_cycles_requests_responses"] = list(map(int, fields[1:]))
        elif fields and fields[0] == b"W":
            result["complete_write_records"] += 1
        elif fields and fields[0] == b"E":
            result["embedding_records"] += 1
        elif line.strip() == b"TRANSCRIPT_COMPLETE":
            result["complete"] = True
    return result


def serial(run):
    run.tools(("python3", "iverilog", "vvp"))
    run.receipt["capacity_before"] = capacity()
    run.save()
    for label, seed in (("B", 17), ("C", 89)):
        name = f"{label}-s{seed}-m2-d12"
        began = time.monotonic(), time.process_time()
        fixture = Fixture(CONFIGS[label], seed, 2)
        run.timing(name+"-fixture-setup", began)
        child = CostRun(run.directory/name, deadline=run.deadline, repair_of=AGGREGATE)
        child.receipt["tools"] = run.receipt["tools"]
        child.save()
        began = time.monotonic(), time.process_time()
        try:
            execute_fixture(child, name, fixture)
            counts = observations(child, name)
            coverage = child.receipt["coverage"][0]
            assert counts["complete"]
            assert counts["last_observed_cycles_requests_responses"][1:] == coverage["completion"][1:3]
            assert counts["embedding_records"] == coverage["compared_components"]
        except Exception as error:
            child.receipt["public_observations"] = observations(child, name)
            child.finish("failed", str(error))
            raise
        else:
            child.receipt["public_observations"] = counts
            child.finish("passed")
            run.receipt["coverage"].extend(child.receipt["coverage"])
        finally:
            run.receipt.setdefault("case_costs", []).append({
                "case": name, "elapsed_s": time.monotonic()-began[0],
                "python_cpu_s": time.process_time()-began[1],
                "receipt": str((child.directory/"receipt.json").relative_to(ROOT)),
                "status": child.receipt["status"],
                "observations": child.receipt["public_observations"]})
            run.save()
    assert len(run.receipt["coverage"]) == 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", choices=("watchdog", "serial", "phases", "phase-analysis"), required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--watchdog-receipt")
    parser.add_argument("--phase-receipt")
    args = parser.parse_args()
    directory = (ROOT/args.output).resolve()
    assert directory.is_relative_to(ROOT/"evidence/preparation")
    budget = 12 if args.check in ("watchdog", "phase-analysis") else 100
    run = Run(directory, budget=budget, deadline=ENTRY_MONOTONIC+budget,
              repair_of=AGGREGATE)
    run.receipt["diagnostic_scope"] = {
        "acceptance_evidence": False, "absolute_budget_s": budget,
        "entry_monotonic": ENTRY_MONOTONIC,
        "predicate_candidate_adopted": False, "concurrency_adopted": False,
        "shared_throttling_deltas": "nonexclusive; not causal DUT CPU attribution",
        "planned_cases": ([] if args.check == "phase-analysis" else
                          ["child-limit", "common-limit"] if args.check == "watchdog"
                          else [["B", 17, 2]] if args.check == "phases"
                          else [["B", 17, 2], ["C", 89, 2]])}
    run.save()
    try:
        if args.check == "serial":
            assert args.watchdog_receipt, "watchdog proof required before measurement"
            path = (ROOT/args.watchdog_receipt).resolve()
            assert path.is_relative_to(ROOT/"evidence/preparation")
            receipt = json.loads(path.read_text())
            assert receipt["status"] == "passed" and len(receipt["coverage"]) == 2
            assert receipt["source_sha256"] == run.receipt["source_sha256"]
            run.receipt["watchdog_receipt"] = {
                "path": str(path.relative_to(ROOT)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            serial(run)
        elif args.check == "phase-analysis":
            assert args.phase_receipt, "retained phase receipt required"
            phase_analysis(run, args.phase_receipt)
        elif args.check == "phases":
            phases(run)
        else:
            watchdog(run)
        assert time.monotonic() < run.deadline, "absolute diagnostic deadline exceeded"
    except Exception as error:
        (directory/"diagnostic.stderr").write_text(traceback.format_exc())
        run.finish("failed", str(error))
        status = 1
    else:
        run.finish("passed")
        status = 0
    run.receipt["capacity_after"] = capacity()
    run.receipt["total_entry_elapsed_s"] = time.monotonic()-ENTRY_MONOTONIC
    run.receipt["total_entry_python_cpu_s"] = time.process_time()-ENTRY_PYTHON_CPU
    run.save()
    print(json.dumps({"status": run.receipt["status"],
                      "receipt": str((directory/"receipt.json").relative_to(ROOT)),
                      "elapsed_s": run.receipt["total_entry_elapsed_s"]}))
    return status


if __name__ == "__main__":
    sys.exit(main())
