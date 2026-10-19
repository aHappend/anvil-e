"""Source-style and source-bound synthesized timing-hazard checks, not STA."""
import hashlib
import json
from pathlib import Path
import re


def code_only(text):
    """Keep line positions while ignoring comments and string contents."""
    return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"',
                  lambda match: re.sub(r"[^\n]", " ", match.group()), text)


def clocked_assignments(text):
    code = code_only(text)
    regions = []
    for match in re.finditer(
            r"\b(?:always|always_ff)\s*@\s*\([^)]*\b(?:posedge|negedge)\b[^)]*\)",
            code):
        tokens = list(re.finditer(r"\b(?:begin|end)\b|;", code[match.end():]))
        if not tokens or tokens[0].group() != "begin":
            raise AssertionError("timing checker requires an explicit clocked begin/end block")
        depth = 0
        for token in tokens:
            if token.group() == "begin":
                depth += 1
            elif token.group() == "end":
                depth -= 1
                if depth == 0:
                    regions.append((match.start(), match.end()+token.end()))
                    break
        else:
            raise AssertionError("unterminated clocked block")
    # Tasks update sequential registers in this RTL. Check their bodies too,
    # so moving a blocking register update into a task cannot bypass the gate.
    regions.extend((match.start(), match.end()) for match in re.finditer(
        r"\btask\b[\s\S]*?\bendtask\b", code))
    hazards = []
    for begin, end in regions:
        for match in re.finditer(r"(?<![<>=!])=(?!=)", code[begin:end]):
            hazards.append(code.count("\n", 0, begin+match.start())+1)
    return {"clocked_blocks_and_tasks": len(regions),
            "blocking_assignment_lines": sorted(set(hazards))}


def assert_no_divmod(modules):
    forbidden = []
    for name, module in modules.items():
        for cell_name, cell in module["cells"].items():
            if cell["type"] in ("$div", "$mod", "$divfloor", "$modfloor"):
                forbidden.append({"module": name, "cell": cell_name,
                                  "type": cell["type"]})
    if forbidden:
        raise AssertionError(f"combinational division/modulus cells: {forbidden}")
    return 0


def verify_source_style(execution):
    # Disposable checker fixtures, not modified DUT sources or DUT executions.
    fixtures = [
        ("always @(posedge clk) begin q <= d; end", False),
        ("always_ff @(posedge clk) begin if (a == b) q <= d; end", False),
        ('always @(posedge clk) begin $display("q = d"); /* = */ q <= d; end', False),
        ("always @(posedge clk) begin if (en) begin q = d; end end", True),
        ("always_ff @(posedge clk) begin q = d; q <= 0; end", True),
        ("task automatic update; begin q = d; end endtask", True),
        ("function automatic f; input x; begin f=x; end endfunction\n"
         "always @(posedge clk) begin q <= f(d); end", False),
    ]
    for text, rejected in fixtures:
        assert bool(clocked_assignments(text)["blocking_assignment_lines"]) == rejected
    for kind in ("$div", "$mod", "$divfloor", "$modfloor"):
        try:
            assert_no_divmod({"fixture": {"cells": {"bad": {"type": kind}}}})
        except AssertionError:
            pass
        else:
            raise AssertionError(f"timing checker accepted {kind} fixture")
    assert_no_divmod({"fixture": {"cells": {"good": {"type": "$sub"}}}})
    rows = []
    for path in sorted(Path("rtl").glob("*.sv")):
        row = {"source": str(path), **clocked_assignments(path.read_text())}
        rows.append(row)
    summary = {"scope": "Clocked blocks and register-update tasks; not physical STA",
               "checker_fixtures": len(fixtures)+5, "sources": rows}
    (execution.output/"timing-source-style.json").write_text(
        json.dumps(summary, indent=2)+"\n")
    if not rows or not any(row["clocked_blocks_and_tasks"] for row in rows):
        raise AssertionError("no sequential RTL inspected")
    failures = [row for row in rows if row["blocking_assignment_lines"]]
    if failures:
        raise AssertionError(f"blocking sequential assignments: {failures}")
    return summary


def verify_timing(execution, configs):
    """Inspect fresh mandatory synthesis results without synthesizing twice."""
    if configs != ["A", "B"]:
        raise ValueError("timing requires synthesis configurations A and B")
    verify_source_style(execution)
    receipts = sorted(Path("evidence/verification/synthesis").glob("attempt-*/receipt.json"))
    if not receipts:
        raise AssertionError("fresh synthesis receipt is required before timing inspection")
    receipt_path = receipts[-1]
    receipt = json.loads(receipt_path.read_text())
    if receipt["status"] != "passed" or receipt["source_sha256"] != execution.sources:
        raise AssertionError(f"synthesis is failed or not current-source: {receipt_path}")
    ledger = []
    for config in configs:
        execution.remaining()
        netlist = receipt_path.parent/f"{config}-netlist.json"
        digest = hashlib.sha256(netlist.read_bytes()).hexdigest()
        if receipt["generated_output_sha256"].get(str(netlist)) != digest:
            raise AssertionError(f"synthesis netlist identity mismatch: {netlist}")
        modules = json.loads(netlist.read_text())["modules"]
        if "anvil_e_top" not in modules:
            raise AssertionError("synthesis netlist lacks official top")
        ledger.append({"config": config, "netlist": str(netlist), "sha256": digest,
                       "modules_inspected": len(modules),
                       "combinational_divmod_cells": assert_no_divmod(modules)})
    (execution.output/"rtl-timing-lint.json").write_text(json.dumps({
        "scope": "No combinational div/mod cells or blocking sequential assignments; "
                 "not Quartus synthesis, TimeQuest closure or physical PPA",
        "synthesis_receipt": str(receipt_path),
        "synthesis_receipt_sha256": hashlib.sha256(receipt_path.read_bytes()).hexdigest(),
        "configurations": ledger, "status": "passed"}, indent=2)+"\n")
