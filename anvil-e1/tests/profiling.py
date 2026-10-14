"""Bounded advisory cost attribution; never a functional acceptance shortcut."""
import hashlib
import json
import re
from pathlib import Path

from model import CONFIGS


def profile_synthesis(execution, configs):
    if configs != ["A"] or execution.allowance > 90:
        raise ValueError("initial sequential synthesis profile requires A and <=90 seconds")
    output = execution.output
    snapshot = output / "A-pre-proc.il"
    parameters = " ".join(f"-chparam {n} {v}"
                          for n, v in CONFIGS["A"].parameters().items())
    script = output / "derive.ys"
    script.write_text("read_verilog -sv -defer " +
        " ".join(str(p) for p in sorted(Path("rtl").glob("*.sv"))) +
        "\nhierarchy -check -top anvil_e1_top " + parameters +
        f"\nwrite_rtlil {snapshot}\nstat\n")
    execution.run("derive", ["yosys", "-s", str(script)], maximum=25)
    text = snapshot.read_text()
    modules = []
    for match in re.finditer(r"^module ([^\n]+)\n(.*?)^end\n", text,
                             re.MULTILINE | re.DOTALL):
        name, body = match.groups()
        if name.endswith(("\\anvil_e1_address", "\\anvil_e1_sequencer")):
            # hdlname is a module attribute preceding the module, so use src
            # paths in its contents to identify the parameter-derived module.
            for family in ("address", "sequencer"):
                if not name.endswith(f"\\anvil_e1_{family}"):
                    continue
                processes = []
                chunks = re.split(r"^  process ", body, flags=re.MULTILINE)[1:]
                for chunk in chunks:
                    processes.append({
                        "name": chunk.splitlines()[0],
                        "lines": len(chunk.splitlines()),
                        "switches": len(re.findall(r"^\s+switch ", chunk, re.MULTILINE)),
                        "memwr": len(re.findall(r"^\s+memwr ", chunk, re.MULTILINE)),
                        "mem2reg_write_references": chunk.count("$mem2reg_wr"),
                        "bank_references": {bank: chunk.count(bank) for bank in
                            ("xvec", "work", "temporary", "gate", "auxiliary")}})
                modules.append({"family": family, "module": name,
                                "processes": processes})
    assert len(modules) == 2 and {m["family"] for m in modules} == {
        "address", "sequencer"}, modules
    assert len({m["module"] for m in modules}) == 2
    summary = {"diagnostic_only": True, "snapshot": str(snapshot),
        "snapshot_sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
        "modules": modules, "stages": []}
    result = output / "profile-summary.json"
    result.write_text(json.dumps(summary, indent=2) + "\n")
    # Each child starts from exactly the retained parameter-derived snapshot.
    address = next(m for m in modules if m["family"] == "address")
    sequencer = next(m for m in modules if m["family"] == "sequencer")
    for module, subset in ((address, "all"), (sequencer, "combinational"),
                           (sequencer, "clocked")):
        name = module["family"] + "-" + subset
        stage_snapshot = snapshot
        if subset != "all":
            module_pattern = (r"(^module " + re.escape(module["module"]) +
                              r"\n)(.*?)(^end\n)")
            def filter_module(match):
                def filter_process(process):
                    clocked = "sync posedge \\clk" in process.group()
                    return process.group() if clocked == (subset == "clocked") else ""
                body = re.sub(r"(?:^  attribute [^\n]+\n)*^  process [^\n]+\n.*?^  end\n",
                              filter_process, match[2],
                              flags=re.MULTILINE | re.DOTALL)
                return match[1] + body + match[3]
            filtered, count = re.subn(module_pattern, filter_module, text,
                                     flags=re.MULTILINE | re.DOTALL)
            assert count == 1
            stage_snapshot = output / (name + "-isolated.il")
            stage_snapshot.write_text(filtered)
        stage = {"family": name, "status": "running"}
        stage["snapshot"] = str(stage_snapshot)
        stage["snapshot_sha256"] = hashlib.sha256(stage_snapshot.read_bytes()).hexdigest()
        summary["stages"].append(stage)
        result.write_text(json.dumps(summary, indent=2) + "\n")
        script = output / f"lower-{name}.ys"
        script.write_text(f"read_rtlil {stage_snapshot}\nselect -clear\n" +
            f"select {module['module']}\nproc\nstat\n" +
            f"write_rtlil {output / (name + '-post-proc.il')}\n")
        try:
            execution.run("lower-" + name, ["yosys", "-s", str(script)])
            stage["status"] = "completed"
        except (TimeoutError, AssertionError, RuntimeError) as error:
            stage["status"] = "failed"
            stage["detail"] = str(error)
            raise
        finally:
            stage["child"] = execution.children[-1]
            result.write_text(json.dumps(summary, indent=2) + "\n")


def profile_simulation(execution):
    from behavior import compile_forward, fixtures
    output = execution.output
    binary = compile_forward(execution, "C")
    image, jobs_path, _ = fixtures(execution, "C", 17, minimal=True)
    stages = []
    summary = {"diagnostic_only": True, "fixed_cycles": 100000,
               "stages": stages}
    result = output / "profile-summary.json"
    fixed_work = None
    for quiet, capture in ((0, 1), (1, 1), (0, 0), (1, 0)):
        replay = output / f"address-inputs-{quiet}-{capture}.txt"
        log = execution.run(f"integrated-trace-{quiet}-{capture}", ["vvp", "-v", str(binary),
            f"+image={image}", f"+jobs={jobs_path}", "+seed=17",
            "+profile_cycles=100000", f"+profile_quiet={quiet}",
            f"+profile_capture={capture}",
            f"+profile_file={replay}"], maximum=20)
        completed = re.findall(
            r"^PROFILE_COMPLETE cycles=(\d+) state_changes=(\d+) address_changes=(\d+)$",
            log.read_text(), re.MULTILINE)
        assert len(completed) == 1 and int(completed[0][0]) == 100000, completed
        if fixed_work is None:
            fixed_work = completed[0]
        assert completed[0] == fixed_work, "profile controls changed observed work"
        stages.append({"kind": "integrated", "quiet": quiet,
                       "capture": capture,
                       "observed_work": completed[0],
                       "child": execution.children[-1]})
        result.write_text(json.dumps(summary, indent=2) + "\n")
    assert (output / "address-inputs-0-1.txt").read_bytes() == (
        output / "address-inputs-1-1.txt").read_bytes(), "trace switch changed stimulus"
    g = CONFIGS["C"]
    for evaluate in (1, 0):
        replay_binary = output / f"address-replay-{evaluate}.vvp"
        argv = ["iverilog", "-g2012", "-s", "profile_address", "-o", str(replay_binary),
                f"-Pprofile_address.EVALUATE={evaluate}"]
        argv += [f"-Pprofile_address.{n}={v}" for n, v in g.parameters().items()
                 if n not in ("SLIDING_WINDOW", "MAX_SEQ_LEN")]
        argv += ["tests/profile_address.sv", "rtl/anvil_e1_address.sv"]
        execution.run(f"compile-replay-{evaluate}", argv, maximum=10)
        log = execution.run(f"address-replay-{evaluate}", ["vvp", "-v", str(replay_binary),
            f"+input={output / 'address-inputs-0-1.txt'}"], maximum=20)
        assert re.findall(r"^PROFILE_ADDRESS_COMPLETE (\d+)$", log.read_text(),
                          re.MULTILINE) == ["100000"]
        stages.append({"kind": "address-replay", "evaluate": evaluate,
                       "child": execution.children[-1]})
        result.write_text(json.dumps(summary, indent=2) + "\n")
