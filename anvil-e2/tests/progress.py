"""Bounded, explicitly incomplete public-pin execution-cost probe."""
import argparse
import dataclasses
import hashlib
import json
import re
import sys
import threading
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import CONFIGS, Fixture, Floating, Integer, Q, SCRATCH
from verify import ROOT, Run, bench, rtl_files


PUBLIC_FIELDS = (
    ("job_ready", 1), ("mem_req_valid", 1), ("mem_req_write", 1),
    ("mem_req_addr", 64), ("mem_req_wdata", 32), ("mem_rsp_ready", 1),
    ("emb_valid", 1), ("emb_data", 32), ("emb_index", 16), ("emb_last", 1),
    ("done_valid", 1), ("done_error", 4), ("busy", 1),
)


def playback_cost(run, reference, retained_results=None, refresh_controls=False):
    """Nonfunctional playback control; exact readable records, never digests."""
    reference = (ROOT/reference).resolve()
    assert reference.is_relative_to(ROOT/"evidence/preparation")
    receipt = json.loads((reference/"receipt.json").read_text())
    assert receipt["status"] == "diagnostic-incomplete"
    assert receipt["prefix_counts"]["public_samples"] == 300004
    assert receipt["prefix_counts"]["compared_prefix_writes"] == 696
    bindings = ("public-changes.mem", "public-samples.mem", "host-lean.sv",
                "host-monitored.sv", "host-lean-simulate.stdout",
                "host-monitored-simulate.stdout")
    run.receipt["reference_artifacts"] = {
        str((reference/name).relative_to(ROOT)): hashlib.sha256(
            (reference/name).read_bytes()).hexdigest() for name in bindings}
    run.receipt["reference_receipt"] = str((reference/"receipt.json").relative_to(ROOT))
    run.receipt["equivalence_method"] = (
        "Exact readable output-pin records at every observation, not hashes. "
        "Control is nonfunctional: no DUT, responder, stimulus generation or monitors. "
        "Reference retains its unchanged responder, stimulus, monitors and observation points.")
    durations = {}
    artifacts = run.directory
    if retained_results:
        artifacts = (ROOT/retained_results).resolve()
        assert artifacts.is_relative_to(ROOT/"evidence/preparation")
        retained = json.loads((artifacts/"receipt.json").read_text())
        assert retained["reference_receipt"] == run.receipt["reference_receipt"]
        assert all(retained["source_sha256"][name] == digest
                   for name, digest in run.receipt["source_sha256"].items()
                   if name != "tests/progress.py"), "CHANGED_DIAGNOSTIC_INPUTS"
        run.receipt["retained_execution_receipt"] = str(
            (artifacts/"receipt.json").relative_to(ROOT))
        run.receipt["retained_execution_durations_s"] = retained["durations_s"]

    def measured(name, operation):
        start = time.monotonic()
        try:
            return operation()
        finally:
            durations[name] = time.monotonic()-start
            run.receipt["durations_s"] = durations
            run.save()

    narrow = [int(line, 16) for line in
              (reference/"public-changes.mem").read_text().splitlines()]
    wide = [int(line, 16) for line in
            (reference/"public-samples.mem").read_text().splitlines()
            if not line.startswith("//")]
    samples = receipt["prefix_counts"]["public_samples"]
    assert len(narrow) == 36743 and len(wide) == 81305
    assert narrow[0] >> 156 == 0 and wide[0] >> 853 == 0
    assert narrow[0] & ((1 << 156)-1) == 0
    for values, shift in ((narrow, 156), (wide, 853)):
        assert all(a >> shift < b >> shift for a, b in zip(values, values[1:]))
        assert values[-1] >> shift < samples
    public = "{"+",".join(name for name, _ in PUBLIC_FIELDS)+"}"
    header = "index time cycle clk rst_n "+" ".join(name for name, _ in PUBLIC_FIELDS)
    record_format = "%0d %0d %0d %b %b "+" ".join("%h" for _ in PUBLIC_FIELDS)
    record_args = ",".join(name for name, _ in PUBLIC_FIELDS)

    def recording(path):
        return f"""
integer stream_fd;
initial begin
 stream_fd=$fopen("{path}","w");
 if(!stream_fd) $fatal(1,"STREAM_FILE");
 $fdisplay(stream_fd,"{header}");
end
task automatic record_sample;
begin
 $fdisplay(stream_fd,"{record_format}",
           sample_count,$time,cycles,clk,rst_n,{record_args});
end
endtask
"""

    # The existing lean replay is the narrow-stream monitored reference. Only
    # recording is inserted; its stimulus, responder and assertions stay intact.
    lean = (reference/"host-lean.sv").read_text()
    marker = " sample_count=sample_count+1;"
    assert lean.count(marker) == 2
    monitored = lean.replace(marker, " record_sample();\n"+marker)
    monitored = monitored.replace("module tb;", "module tb;\n"+recording(
        run.directory/"monitored.records"))
    monitored = monitored.replace(
        '$display("DIAGNOSTIC_STOP_INCOMPLETE");',
        '$fclose(stream_fd);\n'
        '$display("TERMINAL %0d %0d %0d %0d",$time,cycles,sample_count,change_index);\n'
        '$display("DIAGNOSTIC_STOP_INCOMPLETE");')

    control = f"""
module tb;
reg clk=0,rst_n=0;
always #5 clk=~clk;
integer cycles=0,sample_count=0,change_index=0;
reg [187:0] changes[0:{len(narrow)-1}];
reg [155:0] held_public;
{chr(10).join(f"reg [{width-1}:0] {name};" for name, width in PUBLIC_FIELDS)}
initial $readmemh("{reference/'public-changes.mem'}",changes);
task automatic capture;
begin
 if(change_index<{len(narrow)} && changes[change_index][187:156]==sample_count) begin
  held_public=changes[change_index][155:0]; change_index=change_index+1;
 end
 {public}=held_public;
 RECORD_SAMPLE
 sample_count=sample_count+1;
end
endtask
initial begin
 #0; capture(); #1; capture();
 #11; rst_n=1;
end
always @(posedge clk) begin
 capture();
 if(rst_n) begin #1; capture(); end
end
always @(negedge clk) begin
 capture();
 if(rst_n) cycles=cycles+1;
 if(rst_n && cycles>=100000) begin
  if(sample_count!={samples} || change_index!={len(narrow)})
   $fatal(1,"CONTROL_INCOMPLETE");
  CLOSE_STREAM
  $display("TERMINAL %0d %0d %0d %0d",$time,cycles,sample_count,change_index);
  $finish;
 end
end
endmodule
"""
    # Match the retained lean replay's inlined playback statements. A new
    # automatic task per observation would add a different scheduling cost.
    capture_start = control.index("task automatic capture;\nbegin")
    capture_end = control.index("endtask", capture_start)+len("endtask")
    capture_body = control[
        capture_start+len("task automatic capture;\n"):capture_end-len("endtask")]
    control = (control[:capture_start]+control[capture_end:]).replace(
        "capture();", capture_body)
    recorded = control.replace("module tb;", "module tb;\n"+recording(
        run.directory/"control.records"))
    recorded = recorded.replace("RECORD_SAMPLE", "record_sample();").replace(
        "CLOSE_STREAM", "$fclose(stream_fd);")
    unrecorded = control.replace("RECORD_SAMPLE", "").replace("CLOSE_STREAM", "")
    load_only = f"""
module tb;
reg [187:0] changes[0:{len(narrow)-1}];
initial begin
 $readmemh("{reference/'public-changes.mem'}",changes);
 if(changes[0]!==188'h{narrow[0]:047x} ||
    changes[{len(narrow)-1}]!==188'h{narrow[-1]:047x})
   $fatal(1,"LOAD_ENDPOINTS");
 $display("LOADING_ONLY records={len(narrow)} time=%0d",$time);
 $finish;
end
endmodule
"""
    results = {}
    variants = [("monitored-recorded", monitored), ("control-recorded", recorded),
                ("control-unrecorded", unrecorded), ("control-loading", load_only)]
    if refresh_controls:
        assert retained_results, "refresh controls requires a retained checked reference"
        variants.append(("monitored-unrecorded", lean))
    for name, text in variants:
        if retained_results and (not refresh_controls or name in (
                "monitored-recorded", "control-loading")):
            results[name] = ((artifacts/(name+"-simulate.stdout")).read_text(),
                             (artifacts/(name+"-simulate.stderr")).read_text(), 0)
            execution = next(e for e in retained["executions"]
                             if e["stdout"].endswith(name+"-simulate.stdout"))
            assert execution["exit_code"] == 0 and not execution["timed_out"]
            continue
        tb, exe = run.directory/(name+".sv"), run.directory/(name+".vvp")
        tb.write_text(text)
        measured(name+"-compile", lambda: run.command(
            ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", exe, tb],
            name+"-compile", timeout=10))
        results[name] = measured(name+"-simulation", lambda: run.command(
            ["vvp", "-v", exe], name+"-simulate", timeout=20))

    def compare():
        tags = ("T ", "W ", "PROGRESS ", "SAMPLES ", "DIAGNOSTIC_STOP_")
        old = (reference/"host-lean-simulate.stdout").read_text()
        checked = (reference/"host-monitored-simulate.stdout").read_text()
        transcript = lambda text: [line for line in text.splitlines()
                                   if line.startswith(tags)]
        assert transcript(results["monitored-recorded"][0]) == transcript(old)
        assert transcript(old) == transcript(checked), "CHECKED_REFERENCE_PREFIX"
        if refresh_controls:
            assert transcript(results["monitored-unrecorded"][0]) == transcript(old)
        terminal = "TERMINAL 1000010 100000 300004 36743"
        for name in ("monitored-recorded", "control-recorded", "control-unrecorded"):
            assert results[name][0].splitlines().count(terminal) == 1
        assert "LOADING_ONLY records=36743 time=0" in results["control-loading"][0]
        wi = ni = 0
        previous = None
        control_artifacts = run.directory if refresh_controls else artifacts
        with (artifacts/"monitored.records").open() as left, (
                control_artifacts/"control.records").open() as right:
            assert next(left).rstrip() == next(right).rstrip() == header
            for index in range(samples):
                a, b = left.readline(), right.readline()
                assert a and a == b, f"SAMPLED_STREAM_MISMATCH index={index}"
                fields = a.split()
                assert len(fields) == 5+len(PUBLIC_FIELDS)
                actual_index, stamp, cycle, clock, reset = map(int, fields[:5])
                if index < 4:
                    expected_time, expected_cycle = ((0, 0), (1, 0), (5, 0), (10, 0))[index]
                else:
                    group, phase = divmod(index-4, 3)
                    expected_time, expected_cycle = 15+10*group+(0, 1, 5)[phase], group
                assert (actual_index, stamp, cycle, clock, reset) == (
                    index, expected_time, expected_cycle,
                    int(expected_time % 10 in (5, 6)), int(expected_time >= 12))
                if wi < len(wide) and wide[wi] >> 853 == index:
                    word = wide[wi]
                    assert (word >> 789) & ((1 << 64)-1) == stamp
                    assert (word >> 757) & ((1 << 32)-1) == cycle
                    previous = word & ((1 << 156)-1)
                    wi += 1
                if ni < len(narrow) and narrow[ni] >> 156 == index:
                    held = narrow[ni] & ((1 << 156)-1)
                    ni += 1
                observed = 0
                for value, (_, width) in zip(fields[5:], PUBLIC_FIELDS):
                    parsed = int(value, 16)
                    assert 0 <= parsed < 1 << width
                    observed = (observed << width) | parsed
                assert observed == previous == held, f"HELD_PUBLIC index={index}"
            assert left.readline() == right.readline() == "", "EXTRA_OBSERVATIONS"
        assert wi == len(wide) and ni == len(narrow), "UNCONSUMED_CHANGES"
        run.receipt["assertions"].append({
            "exact_readable_records_compared": samples, "held_observations_included": True,
            "wide_change_records_consumed": wi, "public_change_records_consumed": ni,
            "matching_time_zero_initialization": True, "no_missing_or_extra_observations": True,
            "terminal_time": 1000010, "terminal_cycle": 100000,
            "identical_retained_request_cycles_payloads_and_write_histories": True,
            "compared_prefix_writes": 696, "complete_inference": False,
        })

    measured("exact-record-comparison", compare)
    events = {}
    for name, (stdout, stderr, _) in results.items():
        events[name] = {kind: int(count) for count, kind in re.findall(
            r"(\d+)\s+(time steps|thread schedule events|assign events|other events)",
            stdout+"\n"+stderr)}
        assert "thread schedule events" in events[name] and "assign events" in events[name], (
            f"MISSING_SIMULATOR_EVENTS {name}")
    run.receipt["simulator_event_counts"] = events
    run.receipt["limitations"] = (
        "Loading-only timing includes simulator startup/elaboration, not isolated readmemh CPU. "
        "Playback timing includes loading; readable recording adds file IO. Exact Python "
        "record comparison is timed separately. Unlike executions are not subtracted to "
        "infer causal DUT or responder CPU cost. Output-pin records cover all 13 selected "
        "public outputs plus clock/reset, time and observation/cycle indices; control has "
        "no functional host input generation. No production optimization is adopted here.")
    run.save()


def inline_public_monitor(text):
    """Preserve each observation while avoiding automatic task scheduling."""
    start = text.index("task automatic known;\nbegin")
    end = text.index("endtask", start)+len("endtask")
    body = text[start+len("task automatic known;\n"):end-len("endtask")]
    return (text[:start]+text[end:]).replace("known();", body)


def monitored_prefix(text, directory, cycles, replay_samples=None, baseline=False):
    """Replay every observation through the unchanged responder and monitors."""
    public = ("{job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata,"
              "mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy}")
    inputs = ("{rst_n,job_valid,job_mode,job_tokens,job_patch_rows,job_patch_cols,"
              "job_output_dim,weights_base,vision_weights_base,image_base,tokens_base,"
              "positions_base,mask_base,scratch_base,mem_req_ready,mem_rsp_valid,"
              "mem_rsp_rdata,mem_rsp_error,emb_ready,done_ready}")
    path = directory/"public-samples.mem"
    capacity = replay_samples or (cycles*3+16)
    declarations = f"""
localparam PUBLIC_BITS=156, INPUT_BITS=601;
localparam SAMPLE_BITS=32+64+32+INPUT_BITS+PUBLIC_BITS;
reg [SAMPLE_BITS-1:0] samples[0:{capacity-1}];
integer sample_count=0,record_count=0,write_count=0,read_count=0;
reg [63:0] latest_address=0;
reg [INPUT_BITS+PUBLIC_BITS-1:0] previous_sample;
task automatic capture;
begin
"""
    if replay_samples:
        declarations += f"""
 if(record_count<{capacity} &&
    samples[record_count][SAMPLE_BITS-1 -: 32]==sample_count) begin
  if(samples[record_count][SAMPLE_BITS-33:PUBLIC_BITS] !==
     {{$time,32'(cycles),{inputs}}}) $fatal(1,"REPLAY_STIMULUS sample=%0d",sample_count);
  previous_sample=samples[record_count][INPUT_BITS+PUBLIC_BITS-1:0];
  record_count=record_count+1;
 end
 if(previous_sample[INPUT_BITS+PUBLIC_BITS-1:PUBLIC_BITS] !== {inputs})
  $fatal(1,"REPLAY_HELD_INPUT sample=%0d",sample_count);
 {public}=previous_sample[PUBLIC_BITS-1:0];
"""
    else:
        declarations += f"""
 if(sample_count==0 || previous_sample !== {{{inputs},{public}}}) begin
  if(record_count>={capacity}) $fatal(1,"SAMPLE_OVERFLOW");
  samples[record_count]={{32'(sample_count),$time,32'(cycles),{inputs},{public}}};
  previous_sample={{{inputs},{public}}};
  record_count=record_count+1;
 end
"""
    declarations += """
 sample_count=sample_count+1;
end
endtask
"""
    if baseline:
        declarations = """
integer sample_count=0,record_count=0,write_count=0,read_count=0;
reg [63:0] latest_address=0;
"""
    text = text.replace("task automatic known;", declarations+"\ntask automatic known;")
    if not baseline:
        text = text.replace("task automatic known;\nbegin", "task automatic known;\nbegin\n capture();")
        text = text.replace("  #1;\n  if(active)", "  #1; capture();\n  if(active)")
    text = text.replace("   pending=1; response_at=",
                        "   latest_address=mem_req_addr;\n"
                        "   if(mem_req_write) write_count=write_count+1;\n"
                        "   else read_count=read_count+1;\n"
                        "   pending=1; response_at=")
    text = text.replace("   mem_rsp_rdata=read_value;", """
   mem_rsp_rdata=read_value;
   $display("T %0d %h %0d %h %h",cycles,mem_req_addr,mem_req_write,mem_req_wdata,read_value);
""")
    if replay_samples:
        start = text.index("anvil_e2_top #(")
        end = text.index("localparam WORDS", start)
        text = text[:start]+text[end:]
        text = text.replace("wire ", "reg ")
        initialization = f'initial $readmemh("{path}",samples);\n'
        final = f'if(record_count!={replay_samples}) $fatal(1,"REPLAY_RECORD_COUNT");'
    else:
        initialization = ""
        final = "" if baseline else f'$writememh("{path}",samples,0,record_count-1);'
    text = text.replace(" end\nend\nalways @(posedge clk)", """
 end
 if(rst_n && cycles%10000==0) report_prefix();
end
always @(posedge clk)""")
    text = text.replace("endmodule", f"""
{initialization}
{"" if baseline else f'''initial begin
 if($bits({public})!=PUBLIC_BITS || $bits({inputs})!=INPUT_BITS)
  $fatal(1,"SAMPLE_WIDTH");
end'''}
task automatic report_prefix;
begin
 $display("PROGRESS cycles=%0d requests=%0d responses=%0d reads=%0d writes=%0d latest=%h",
          cycles,requests,responses,read_count,write_count,latest_address);
 if(cycles>={cycles}) begin
  {final}
  $display("SAMPLES %0d",sample_count);
  $display("CHANGES %0d",record_count);
  $display("DIAGNOSTIC_STOP_INCOMPLETE"); $fflush(); $finish;
 end
end
endtask
endmodule
""")
    return text


def current_host_cost(run, configuration, cycles):
    durations = {}

    def measured(name, operation):
        start = time.monotonic()
        try:
            return operation()
        finally:
            durations[name] = time.monotonic()-start
            run.receipt["durations_s"] = durations
            run.save()

    fixture = measured("fixture_generation", lambda: Fixture(CONFIGS[configuration], 17, 2))
    integer, expected = measured("integer_oracle", lambda: fixture.run(Integer()))
    floating, _ = measured("floating_oracle", lambda: fixture.run(Floating()))
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm_error = abs(sum((a/Q)**2 for a in integer)**0.5-1) if any(integer) else 0
    assert absolute <= 0.002 and norm_error <= 0.002
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(fixture.c), "seed": 17, "mode": 2,
        "diagnostic_only": True, "cycle_limit": cycles,
        "mathematical_max_abs_error": absolute, "l2_error": norm_error,
    }
    memory = run.directory/"input.mem"

    def stimulus():
        memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                                 for a, v in sorted(fixture.mem.items())))
        return bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)

    original = measured("stimulus_generation", stimulus)
    baseline_tb = run.directory/"baseline.sv"
    baseline_exe = run.directory/"baseline.vvp"
    baseline_tb.write_text(monitored_prefix(original, run.directory, cycles, baseline=True))
    measured("baseline_compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", baseline_exe,
         *rtl_files(), baseline_tb], "baseline-compile", timeout=20))
    baseline_out, _, _ = measured("baseline_simulation", lambda: run.command(
        ["vvp", "-v", baseline_exe], "baseline-simulate", timeout=45))
    tb, exe = run.directory/"progress.sv", run.directory/"progress.vvp"
    tb.write_text(monitored_prefix(original, run.directory, cycles))
    measured("compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", exe, *rtl_files(), tb],
        "compile", timeout=20))
    out, _, _ = measured("simulation", lambda: run.command(
        ["vvp", "-v", exe], "simulate", timeout=45))

    def scoreboard():
        assert out.count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
        requests, observed, samples, changes = [], {}, None, None
        for line in out.splitlines():
            fields = line.split()
            if fields and fields[0] == "T":
                assert len(fields) == 6
                requests.append((int(fields[1]), int(fields[2], 16), int(fields[3]),
                                 int(fields[4], 16), int(fields[5], 16)))
            elif fields and fields[0] == "W":
                observed.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
            elif fields and fields[0] == "SAMPLES":
                samples = int(fields[1])
            elif fields and fields[0] == "CHANGES":
                changes = int(fields[1])
        assert samples and changes and requests
        tags = ("T ", "W ", "PROGRESS ", "DIAGNOSTIC_STOP_")
        assert [x for x in out.splitlines() if x.startswith(tags)] == [
            x for x in baseline_out.splitlines() if x.startswith(tags)], "RECORDER_CHANGED_PREFIX"
        for address, values in observed.items():
            assert address in expected and values == expected[address][:len(values)], (
                f"integer write-prefix mismatch at {address:#x}")
        counts = {"requests": len(requests), "reads": sum(not r[2] for r in requests),
                  "writes": sum(r[2] for r in requests),
                  "compared_prefix_writes": sum(map(len, observed.values())),
                  "compared_addresses": len(observed), "public_samples": samples,
                  "change_records": changes}
        assert counts["writes"] == counts["compared_prefix_writes"]
        # Public scratch regions classify traffic, not private RTL states.
        regions = list(fixture.layout.items())
        traffic = {}
        for cycle, address, write, _, _ in requests:
            region = next((name for (name, start), (_, end) in zip(regions, regions[1:])
                           if start <= address < end), "provisioned")
            item = traffic.setdefault(region, {"reads": 0, "writes": 0,
                                              "first_cycle": cycle, "last_cycle": cycle})
            item["writes" if write else "reads"] += 1
            item["last_cycle"] = cycle
        run.receipt["prefix_counts"] = counts
        run.receipt["public_region_traffic"] = traffic
        run.receipt["assertions"].append({
            "exact_write_prefix": True, "full_fixture_complete": False,
            "protocol_monitors": "Unchanged bench: active X/Z, reset, request/output/"
                                 "completion stalls, ownership, response retirement, "
                                 "alignment, access validity and post-accept timing.",
        })
        return changes

    samples = measured("scoreboard", scoreboard)
    replay_tb, replay_exe = run.directory/"host-monitored.sv", run.directory/"host-monitored.vvp"
    replay_tb.write_text(monitored_prefix(original, run.directory, cycles, samples))
    measured("replay_compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", replay_exe, replay_tb],
        "host-monitored-compile", timeout=10))
    replay, _, _ = measured("host_responder_and_protocol_monitors", lambda: run.command(
        ["vvp", "-v", replay_exe], "host-monitored-simulate", timeout=10))

    def compare_replay():
        tags = ("T ", "W ", "PROGRESS ", "SAMPLES ", "CHANGES ", "DIAGNOSTIC_STOP_")
        assert [x for x in out.splitlines() if x.startswith(tags)] == [
            x for x in replay.splitlines() if x.startswith(tags)], "HOST_REPLAY_TRANSCRIPT"
        run.receipt["assertions"].append({
            "identical_cycle_request_write_prefix": True,
            "identical_host_inputs_at_every_sample": True,
            "monitored_host_replay_only": True,
            "limitation": "Replay includes all host stimulus, responder and protocol monitors, "
                          "plus recorded-sample loading/comparisons; DUT run includes sample "
                          "recording. Timing difference is not exact causal DUT CPU time.",
        })

    measured("replay_scoreboard", compare_replay)
    # The checked replay retains wide input snapshots. A second playback uses
    # only public-output changes, so snapshot parsing is not mistaken for host
    # responder/monitor cost. Its host code and all assertions remain identical.
    def public_changes():
        changes = []
        previous = None
        for line in (run.directory/"public-samples.mem").read_text().splitlines():
            if line.startswith("//"):
                continue
            word = int(line, 16)
            public = word & ((1 << 156)-1)
            sample = word >> (64+32+601+156)
            if public != previous:
                changes.append((sample << 156) | public)
                previous = public
        assert changes
        path = run.directory/"public-changes.mem"
        path.write_text("".join(f"{word:047x}\n" for word in changes))
        return path, len(changes)

    changes_path, change_count = measured("lean_replay_stimulus", public_changes)
    lean = monitored_prefix(original, run.directory, cycles, samples)
    start = lean.index("localparam PUBLIC_BITS=")
    end = lean.index("task automatic known;", start)
    lean_declarations = f"""
reg [187:0] changes[0:{change_count-1}];
reg [155:0] held_public;
integer change_index=0,sample_count=0,record_count=0,write_count=0,read_count=0;
reg [63:0] latest_address=0;
initial $readmemh("{changes_path}",changes);
task automatic capture;
begin
 if(change_index<{change_count} && changes[change_index][187:156]==sample_count) begin
  held_public=changes[change_index][155:0]; change_index=change_index+1;
 end
 {{job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata,
   mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy}}=held_public;
 sample_count=sample_count+1;
end
endtask
"""
    lean = lean[:start]+lean_declarations+lean[end:]
    capture_start = lean.index("task automatic capture;\nbegin")
    capture_end = lean.index("endtask", capture_start)+len("endtask")
    capture_body = lean[capture_start+len("task automatic capture;\n"):capture_end-len("endtask")]
    lean = lean[:capture_start]+lean[capture_end:]
    lean = lean.replace("capture();", capture_body)
    start = lean.index('initial $readmemh("'+str(run.directory/"public-samples.mem"))
    end = lean.index("task automatic report_prefix;", start)
    lean = lean[:start]+lean[end:]
    lean = lean.replace(f'if(record_count!={samples}) $fatal(1,"REPLAY_RECORD_COUNT");',
                        f'if(change_index!={change_count}) $fatal(1,"REPLAY_CHANGE_COUNT");')
    lean_tb, lean_exe = run.directory/"host-lean.sv", run.directory/"host-lean.vvp"
    lean_tb.write_text(lean)
    measured("lean_replay_compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", lean_exe, lean_tb],
        "host-lean-compile", timeout=10))
    lean_out, _, _ = measured("lean_host_responder_and_protocol_monitors", lambda: run.command(
        ["vvp", "-v", lean_exe], "host-lean-simulate", timeout=10))
    tags = ("T ", "W ", "PROGRESS ", "SAMPLES ", "DIAGNOSTIC_STOP_")
    assert [x for x in out.splitlines() if x.startswith(tags)] == [
        x for x in lean_out.splitlines() if x.startswith(tags)], "LEAN_HOST_REPLAY_TRANSCRIPT"
    run.receipt["assertions"].append({
        "lean_replay_identical_prefix": True, "public_change_records": change_count,
        "protocol_monitors_retained": True,
        "limitation": "Lean replay avoids wide recorded input comparisons; the separate "
                      "checked replay proves those inputs. Both compare every request/write "
                      "cycle and payload. Playback overhead remains included, not subtracted.",
    })
    optimized_tb, optimized_exe = run.directory/"host-inlined.sv", run.directory/"host-inlined.vvp"
    optimized_tb.write_text(inline_public_monitor(lean))
    measured("inlined_host_compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", optimized_exe, optimized_tb],
        "host-inlined-compile", timeout=10))
    optimized_out, _, _ = measured("inlined_host_responder_and_protocol_monitors", lambda: run.command(
        ["vvp", "-v", optimized_exe], "host-inlined-simulate", timeout=10))
    assert [x for x in out.splitlines() if x.startswith(tags)] == [
        x for x in optimized_out.splitlines() if x.startswith(tags)], "INLINED_HOST_TRANSCRIPT"
    optimized_dut_tb = run.directory/"dut-inlined.sv"
    optimized_dut_exe = run.directory/"dut-inlined.vvp"
    optimized_dut_tb.write_text(inline_public_monitor(
        monitored_prefix(original, run.directory, cycles, baseline=True)))
    measured("inlined_dut_compilation", lambda: run.command(
        ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", optimized_dut_exe,
         *rtl_files(), optimized_dut_tb], "dut-inlined-compile", timeout=20))
    optimized_dut_out, _, _ = measured("inlined_dut_simulation", lambda: run.command(
        ["vvp", "-v", optimized_dut_exe], "dut-inlined-simulate", timeout=45))
    baseline_tags = ("T ", "W ", "PROGRESS ", "DIAGNOSTIC_STOP_")
    assert [x for x in baseline_out.splitlines() if x.startswith(baseline_tags)] == [
        x for x in optimized_dut_out.splitlines() if x.startswith(baseline_tags)], (
            "INLINED_DUT_TRANSCRIPT")
    run.receipt["assertions"].append({
        "inlined_monitor_host_and_dut_prefix_identical": True,
        "optimization_scope": "Diagnostic copies only; identical monitor statements "
                              "and observation points, no assertions removed.",
    })
    run.receipt["cost_comparison"] = {
        "host_fraction_of_baseline": (
            durations["host_responder_and_protocol_monitors"]/durations["baseline_simulation"]),
        "recording_overhead_s": durations["simulation"]-durations["baseline_simulation"],
        "baseline_us_per_cycle": durations["baseline_simulation"]*1e6/cycles,
        "simulation_us_per_cycle": durations["simulation"]*1e6/cycles,
        "host_us_per_cycle": durations["host_responder_and_protocol_monitors"]*1e6/cycles,
        "lean_host_fraction_of_baseline": (
            durations["lean_host_responder_and_protocol_monitors"]/durations["baseline_simulation"]),
        "lean_host_us_per_cycle": (
            durations["lean_host_responder_and_protocol_monitors"]*1e6/cycles),
    }
    run.save()


def replay_host(run, fixture, memory, transcript):
    """Measure only the real responder's recorded lookups, not inference."""
    requests = [line.split()[1:] for line in transcript.splitlines()
                if line.startswith("T ")]
    assert requests
    trace = run.directory/"requests.trace"
    trace.write_text("".join(" ".join(row)+"\n" for row in requests))
    words = (fixture.layout["end"]-SCRATCH)//4
    text = f"""
module host_replay;
reg clk=0;
always #5 clk=~clk;
reg [63:0] addresses[0:{len(fixture.mem)-1}];
reg [31:0] values[0:{len(fixture.mem)-1}];
reg [31:0] scratch[0:{words-1}];
reg initialized[0:{words-1}];
integer fd,tf,rc,count=0,cycles=0,target,write_flag,entry,lo,hi,mid,i,requests=0;
reg [63:0] address;
reg [31:0] data,expected,actual;
initial begin
 for(i=0;i<{words};i=i+1) initialized[i]=0;
 fd=$fopen("{memory}","r");
 if(!fd) $fatal(1,"REPLAY_MEMORY");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\\n",addresses[count],values[count]);
  if(rc==2) count=count+1;
 end
 $fclose(fd);
 tf=$fopen("{trace}","r"); if(!tf) $fatal(1,"REPLAY_TRACE");
 for(i=0;i<{len(requests)};i=i+1) begin
  rc=$fscanf(tf,"%d %h %d %h %h\\n",target,address,write_flag,data,expected);
  if(rc!=5) $fatal(1,"REPLAY_FORMAT");
  while(cycles<target) begin @(posedge clk); cycles=cycles+1; end
  actual=0;
  if(write_flag) begin
   entry=(address-64'h{SCRATCH:x})/4;
   if(entry<0 || entry>={words}) $fatal(1,"REPLAY_WRITE_ADDRESS");
   scratch[entry]=data; initialized[entry]=1;
   $display("W %h %h",address,data);
  end else if(address>=64'h{SCRATCH:x} && address<64'h{fixture.layout["end"]:x}) begin
   entry=(address-64'h{SCRATCH:x})/4;
   if(!initialized[entry]) $fatal(1,"REPLAY_UNINITIALIZED");
   actual=scratch[entry];
  end else begin
   lo=0; hi=count-1; entry=-1;
   while(lo<=hi) begin
    mid=(lo+hi)/2;
    if(addresses[mid]==address) begin entry=mid; lo=hi+1; end
    else if(addresses[mid]<address) lo=mid+1;
    else hi=mid-1;
   end
   if(entry<0) $fatal(1,"REPLAY_READ_ADDRESS");
   actual=values[entry];
  end
  if(actual!==expected) $fatal(1,"REPLAY_READ_VALUE");
  requests=requests+1;
 end
 $fclose(tf);
 $display("HOST_REPLAY_COMPLETE cycles=%0d requests=%0d",cycles,requests);
 $finish;
end
endmodule
"""
    tb, exe = run.directory/"host.sv", run.directory/"host.vvp"
    tb.write_text(text)
    run.command(["iverilog", "-g2012", "-Wall", "-s", "host_replay",
                 "-o", exe, tb], "host-compile", timeout=10)
    out, _, _ = run.command(["vvp", "-v", exe], "host-simulate", timeout=10)
    assert f"requests={len(requests)}" in out and "HOST_REPLAY_COMPLETE" in out
    run.receipt["assertions"].append({
        "host_replay_only": True, "compared_requests": len(requests),
        "compared_read_responses": sum(row[2] == "0" for row in requests),
        "limitation": "Measures recorded responder lookups, scratch and clock events; "
                      "excludes DUT and public protocol monitors; not hardware acceptance.",
    })
    run.save()


def lookup_cost(run, reference):
    """Real-DUT A/B; only provisioned-address indexing differs between copies."""
    reference = (ROOT/reference).resolve()
    assert reference.is_relative_to(ROOT/"evidence/preparation")
    links = (reference/"receipt.json",
             ROOT/"evidence/preparation/q40-playback-exact-b17-003/receipt.json")
    run.receipt["references"] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in links}
    prior = json.loads(links[0].read_text())
    assert prior["prefix_counts"]["compared_prefix_writes"] == 696
    assert all(prior["source_sha256"][name] == digest
               for name, digest in run.receipt["source_sha256"].items()
               if name != "tests/progress.py"), "CHANGED_LOOKUP_PROBE_INPUTS"
    durations = {}

    def measured(name, operation):
        start = time.monotonic()
        try:
            return operation()
        finally:
            durations[name] = time.monotonic()-start
            run.receipt["durations_s"] = durations
            run.save()

    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm_error = abs(sum((a/Q)**2 for a in integer)**0.5-1)
    assert absolute <= 0.002 and norm_error <= 0.002
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(fixture.c), "seed": 17, "mode": 2,
        "cycle_limit": 100000, "mathematical_max_abs_error": absolute,
        "l2_error": norm_error, "full_fixture_complete": False,
    }
    memory = run.directory/"input.mem"
    memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                             for a, v in sorted(fixture.mem.items())))
    assert memory.read_bytes() == (reference/"input.mem").read_bytes()
    original = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
    old_lookup = """    lo=0; hi=count-1; entry=-1;
    while(lo<=hi) begin
     mid=(lo+hi)/2;
     if(addresses[mid]==mem_req_addr) begin entry=mid; lo=hi+1; end
     else if(addresses[mid]<mem_req_addr) lo=mid+1;
     else hi=mid-1;
    end"""
    assert original.count(old_lookup) == 1
    size = 1 << (4*len(fixture.mem)-1).bit_length()
    # Stored addresses remain the collision authority; no zero/default data
    # can turn a sparse, unprovisioned address into a successful lookup.
    declarations = f"""
localparam LOOKUP_SIZE={size};
integer address_index[0:LOOKUP_SIZE-1];
integer slot;
function automatic integer address_slot(input [63:0] address);
 reg [63:0] word_address;
 begin
  word_address=(address>>2)*64'h9e3779b97f4a7c15;
  address_slot=word_address>>(64-{size.bit_length()-1});
 end
endfunction
"""
    initialization = """
 for(i=0;i<LOOKUP_SIZE;i=i+1) address_index[i]=-1;
 for(i=0;i<count;i=i+1) begin
  slot=address_slot(addresses[i]);
  while(address_index[slot]>=0) slot=(slot+1)&(LOOKUP_SIZE-1);
  address_index[slot]=i;
 end
"""
    new_lookup = """    slot=address_slot(mem_req_addr);
    entry=address_index[slot];
    lookup_steps=lookup_steps+1;
    while(entry>=0 && addresses[entry]!=mem_req_addr) begin
     slot=(slot+1)&(LOOKUP_SIZE-1);
     entry=address_index[slot]; lookup_steps=lookup_steps+1;
    end"""
    counted = old_lookup.replace("    lo=0;", "    lookup_count=lookup_count+1;\n    lo=0;")
    counted = counted.replace("     mid=", "     lookup_steps=lookup_steps+1;\n     mid=")
    common = original.replace("integer fd,rc",
                              "integer lookup_count=0,lookup_steps=0;\ninteger fd,rc")
    baseline = common.replace(old_lookup, counted)
    candidate = common.replace(old_lookup, "    lookup_count=lookup_count+1;\n"+new_lookup)
    candidate = candidate.replace("task automatic known;", declarations+"\ntask automatic known;")
    candidate = candidate.replace(" $fclose(fd);", " $fclose(fd);\n"+initialization)
    restored = candidate.replace(declarations+"\n", "").replace(
        "\n"+initialization, "").replace(
            "    lookup_count=lookup_count+1;\n"+new_lookup, counted)
    assert restored == baseline, "NON_LOOKUP_DIAGNOSTIC_DELTA"
    run.receipt["lookup_implementation"] = {
        "baseline": "sorted provisioned addresses, binary search",
        "candidate": "exact-key open-addressed index; linear collision probing",
        "slots": size, "provisioned_words": len(fixture.mem),
        "production_changed": False,
        "unchanged": "DUT, stimulus, scratch validity, sparse-address rejection, error "
                     "injection, response scheduling, all X/Z/protocol assertions",
    }
    outputs = {}
    for name, source, recorded in (
            ("binary-recorded", baseline, True), ("indexed-recorded", candidate, True),
            ("binary-timing-1", baseline, False), ("indexed-timing-1", candidate, False),
            ("indexed-timing-2", candidate, False), ("binary-timing-2", baseline, False)):
        folder = run.directory/name
        folder.mkdir()
        text = monitored_prefix(source, folder, 100000, baseline=not recorded)
        text = text.replace('$display("DIAGNOSTIC_STOP_INCOMPLETE");',
                            '$display("LOOKUP %0d %0d",lookup_count,lookup_steps);\n'
                            '  $display("DIAGNOSTIC_STOP_INCOMPLETE");')
        tb, exe = folder/"tb.sv", folder/"tb.vvp"
        tb.write_text(text)
        run.receipt.setdefault("diagnostic_source_sha256", {})[
            str(tb.relative_to(ROOT))] = hashlib.sha256(tb.read_bytes()).hexdigest()
        measured(name+"-compile", lambda: run.command(
            ["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", exe, *rtl_files(), tb],
            name+"-compile", timeout=10))
        outputs[name] = measured(name+"-simulation", lambda: run.command(
            ["vvp", "-v", exe], name+"-simulate", timeout=15)[0])

    def compare():
        tags = ("T ", "W ", "PROGRESS ", "DIAGNOSTIC_STOP_")
        transcript = lambda text: [s for s in text.splitlines() if s.startswith(tags)]
        retained = transcript((reference/"simulate.stdout").read_text())
        counts = {}
        for name, out in outputs.items():
            assert out.count("DIAGNOSTIC_STOP_INCOMPLETE") == 1
            assert "TRANSCRIPT_COMPLETE" not in out
            assert transcript(out) == retained, "LOOKUP_PUBLIC_TRANSACTION_MISMATCH "+name
            records = [s.split() for s in out.splitlines() if s.startswith("LOOKUP ")]
            assert len(records) == 1
            counts[name] = dict(zip(("lookups", "lookup_steps"), map(int, records[0][1:])))
            observed = {}
            for line in out.splitlines():
                fields = line.split()
                if fields and fields[0] == "W":
                    observed.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
            assert sum(map(len, observed.values())) == 696
            assert all(a in expected and values == expected[a][:len(values)]
                       for a, values in observed.items()), "INTEGER_WRITE_PREFIX"
        def changes(path):
            return [int(s, 16) for s in path.read_text().splitlines()
                    if not s.startswith("//")]
        reference_changes = changes(reference/"public-samples.mem")
        for name in ("binary-recorded", "indexed-recorded"):
            actual = changes(run.directory/name/"public-samples.mem")
            assert actual == reference_changes, "EXACT_PUBLIC_AND_HOST_SAMPLES "+name
            assert "SAMPLES 300004" in outputs[name]
            assert "CHANGES 81305" in outputs[name]
        assert len(reference_changes) == 81305
        run.receipt["lookup_counts"] = counts
        run.receipt["assertions"].append({
            "all_sampled_public_and_host_values_exact": 300004,
            "wide_change_records_exact": 81305,
            "request_cycle_payload_response_values_exact": 12247,
            "independent_integer_prefix_writes": 696,
            "sparse_rejection_and_scratch_initialization_checks_retained": True,
            "only_lookup_diff_verified": True, "full_inference_complete": False,
        })
        binary = [durations[f"binary-timing-{i}-simulation"] for i in (1, 2)]
        indexed = [durations[f"indexed-timing-{i}-simulation"] for i in (1, 2)]
        run.receipt["cost_comparison"] = {
            "binary_s": binary, "indexed_s": indexed,
            "indexed_over_binary_mean": sum(indexed)/sum(binary),
            "interpretation": "Same real DUT and unchanged public workload; balanced "
                              "execution order. No playback timing subtraction or "
                              "claim of completed inference/aggregate compliance.",
        }
    measured("exact_comparison", compare)
    run.save()


def lookup_gap_analysis(run, retained_results):
    """Localize public transaction gaps, without inferring internal CPU cost."""
    artifacts = (ROOT/retained_results).resolve()
    assert artifacts.is_relative_to(ROOT/"evidence/preparation")
    receipt = json.loads((artifacts/"receipt.json").read_text())
    assert receipt["error"] is None
    assert receipt["assertions"][0]["all_sampled_public_and_host_values_exact"] == 300004
    paths = (artifacts/"receipt.json", artifacts/"binary-timing-1-simulate.stdout")
    run.receipt["retained_artifacts"] = {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    fixture = Fixture(CONFIGS["B"], 17, 2)
    regions = list(fixture.layout.items())
    def region(address):
        return next((name for (name, start), (_, end) in zip(regions, regions[1:])
                     if start <= address < end), "provisioned")
    requests = [line.split()[1:] for line in paths[1].read_text().splitlines()
                if line.startswith("T ")]
    assert len(requests) == 12247
    groups = {}
    for previous, current in zip(requests, requests[1:]):
        before, after = int(previous[0]), int(current[0])
        key = (("write:" if int(previous[2]) else "read:")+region(int(previous[1], 16))
               +" -> "+("write:" if int(current[2]) else "read:")
               +region(int(current[1], 16)))
        groups.setdefault(key, []).append((after-before, before, after))
    summary = {}
    for name, gaps in groups.items():
        largest = max(gaps)
        summary[name] = {
            "count": len(gaps), "total_request_gap_cycles": sum(g[0] for g in gaps),
            "mean_request_gap_cycles": sum(g[0] for g in gaps)/len(gaps),
            "maximum_request_gap_cycles": largest[0],
            "maximum_gap_from_cycle": largest[1], "maximum_gap_to_cycle": largest[2],
        }
    assert sum(x["count"] for x in summary.values()) == len(requests)-1
    assert sum(x["total_request_gap_cycles"] for x in summary.values()) == (
        int(requests[-1][0])-int(requests[0][0]))
    run.receipt["public_request_gap_groups"] = summary
    run.receipt["assertions"].append(
        "All 12246 adjacent request gaps accounted for exactly; gaps include bus "
        "response scheduling and DUT work, not causal simulator CPU attribution.")
    run.receipt["interpretation"] = (
        "Lookup equivalence succeeded but timing benefit is not consistent; production "
        "harness unchanged. Next bounded surface: repeated vision-attention K/V reads "
        "and score-to-value gaps, correlated with the published two-pass attention "
        "algorithm. RTL source inspection identifies score division and exp/series "
        "as candidates inside those gaps, not measured dominant CPU costs. A Designer "
        "optimization would require its own semantics-preserving evidence.")
    run.save()


def projection_attention_cost(run, reference):
    """One real-DUT run; address-derived intervals never identify private states."""
    reference = (ROOT/reference).resolve()
    assert reference.is_relative_to(ROOT/"evidence/preparation")
    old = json.loads((reference/"receipt.json").read_text())
    for name, digest in run.receipt["source_sha256"].items():
        if name != "tests/progress.py":
            assert old["source_sha256"][name] == digest, "CHANGED_REFERENCE_SOURCE "+name
    artifacts = ("receipt.json", "input.mem", "simulate.stdout", "public-samples.mem")
    run.receipt["reference_artifacts"] = {
        str((reference/name).relative_to(ROOT)): hashlib.sha256(
            (reference/name).read_bytes()).hexdigest() for name in artifacts}
    fixture = Fixture(CONFIGS["B"], 17, 2)
    integer, expected = fixture.run(Integer())
    floating, _ = fixture.run(Floating())
    absolute = max(abs(a/Q-b) for a, b in zip(integer, floating))
    norm_error = abs(sum((a/Q)**2 for a in integer)**0.5-1)
    assert absolute <= .002 and norm_error <= .002
    memory = run.directory/"input.mem"
    memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                             for a, v in sorted(fixture.mem.items())))
    assert memory.read_bytes() == (reference/"input.mem").read_bytes()
    retained = (reference/"simulate.stdout").read_text()
    requests = [tuple([int(f[1]), int(f[2], 16), int(f[3]),
                       int(f[4], 16), int(f[5], 16)])
                for f in (s.split() for s in retained.splitlines()) if f and f[0] == "T"]
    assert len(requests) == 12247
    c = fixture.c
    ranges = {name: (fixture.offsets[name], fixture.offsets[name]+4*size)
              for name, size in (("patch", c.VISION_HIDDEN*3*c.PATCH_SIZE**2),
                                 ("position", 2*c.POSITION_EMBEDDING_SIZE*c.VISION_HIDDEN),
                                 *((f"v0.{x}", c.VISION_HIDDEN**2) for x in ("q", "k", "v", "o")))}

    def weight_kind(request):
        _, address, write, _, _ = request
        return next((name for name, (lo, hi) in ranges.items()
                     if not write and lo <= address < hi), None)

    first_vision = next(r[0] for r in requests if not r[2] and
                        fixture.layout["v0"] <= r[1] < fixture.layout["v1"])
    first_attention = next(r[0] for r in requests if not r[2] and
                           fixture.layout["vq"] <= r[1] < fixture.layout["vk"])
    intervals = [{"kind": "patch_stage", "start": 0, "end": first_vision},
                 {"kind": "vision_qkv_build", "start": first_vision,
                  "end": first_attention},
                 {"kind": "attention_and_layer_tail", "start": first_attention,
                  "end": 100000}]
    # Dense windows begin at the first weight request and end at the next
    # differently classified transaction. They include bus/helper/output gaps.
    for index, request in enumerate(requests):
        kind = weight_kind(request)
        if kind not in ("v0.q", "v0.k", "v0.v"):
            continue
        if index and weight_kind(requests[index-1]) == kind:
            continue
        end = index+1
        while end < len(requests) and weight_kind(requests[end]) == kind:
            end += 1
        assert end-index == c.VISION_HIDDEN**2
        intervals.append({"kind": kind+"_dense", "start": request[0],
                          "end": requests[end][0], "weight_reads": end-index})
    attention_start = None
    for request in requests:
        _, address, write, _, _ = request
        if not write and fixture.layout["vq"] <= address < fixture.layout["vk"]:
            if attention_start is None:
                attention_start = request[0]
        elif attention_start is not None and weight_kind(request) == "v0.o":
            intervals.append({"kind": "vision_attention", "start": attention_start,
                              "end": request[0]})
            attention_start = None
    assert attention_start is None, "TRUNCATED_ATTENTION_WINDOW"
    assert sum(i["kind"] == "vision_attention" for i in intervals) == 8
    assert all(sum(i["kind"] == f"v0.{x}_dense" for i in intervals) == 20
               for x in ("q", "k", "v"))
    milestones = sorted({0, first_vision, first_attention, 100000,
                         *[i["end"] for i in intervals if i["kind"] == "vision_attention"]})
    text = monitored_prefix(bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4),
                            run.directory, 100000)
    # Only sparse, read-only observations are added. The responder, schedule,
    # sampled stream and every protocol assertion remain unchanged.
    marker = " if(rst_n) begin\n  if(stalled_request"
    assert text.count(marker) == 1
    condition = " || ".join(f"cycles=={cycle}" for cycle in milestones if cycle < 100000)
    text = text.replace(marker, f"""
 if(rst_n && ({condition})) begin
  $display("INTERVAL_MARK %0d",cycles); $fflush();
 end
""" + marker)
    text = text.replace('$display("DIAGNOSTIC_STOP_INCOMPLETE");',
                        '$display("INTERVAL_MARK 100000"); $fflush();\n'
                        '  $display("DIAGNOSTIC_STOP_INCOMPLETE");')
    tb, exe = run.directory/"intervals.sv", run.directory/"intervals.vvp"
    tb.write_text(text)
    run.receipt["fixture"] = {
        "configuration": dataclasses.asdict(c), "seed": 17, "mode": 2,
        "cycle_limit": 100000, "mathematical_max_abs_error": absolute,
        "l2_error": norm_error, "incomplete_prefix_only": True}
    run.receipt["interval_definition"] = (
        "Half-open accepted-edge cycle intervals derived from documented tensor/scratch "
        "addresses in the exact retained transcript. Dense includes first weight request "
        "through next different transaction; attention includes first Q read through first "
        "O weight request for a query. Broad stages and subwindows overlap; do not sum both.")
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", exe,
                 *rtl_files(), tb], "intervals-compile", timeout=20)
    stop = threading.Event()
    wall = []
    polling_errors = []
    stdout_path = run.directory/"intervals-simulate.stdout"
    wall_start = time.monotonic()

    def observe_wall():
        try:
            while not stdout_path.exists() and not stop.wait(.01):
                pass
            if not stdout_path.exists():
                return
            with stdout_path.open() as stream:
                while True:
                    line = stream.readline()
                    if line:
                        if line.startswith("INTERVAL_MARK "):
                            wall.append({"cycle": int(line.split()[1]),
                                         "observed_elapsed_s": time.monotonic()-wall_start})
                    elif stop.is_set():
                        break
                    else:
                        stop.wait(.01)
        except Exception as error:
            polling_errors.append(repr(error))

    observer = threading.Thread(target=observe_wall)
    observer.start()
    try:
        out, err, _ = run.command(["vvp", "-v", exe], "intervals-simulate", timeout=45)
    finally:
        stop.set()
        observer.join()
        run.receipt["wall_observations"] = wall
        run.receipt["wall_observation_method"] = (
            "Host monotonic receipt of 12 flushed sparse simulator markers via stdout-file "
            "polling at 10ms. Includes scheduling, buffering and observation overhead; "
            "not causal DUT CPU time. Final marker follows sample-file serialization.")
        run.receipt["simulation_wall_s"] = time.monotonic()-wall_start
        run.save()
    assert not polling_errors, polling_errors
    assert [w["cycle"] for w in wall] == milestones
    tags = ("T ", "W ", "PROGRESS ", "SAMPLES ", "CHANGES ", "DIAGNOSTIC_STOP_")
    transcript = lambda s: [line for line in s.splitlines() if line.startswith(tags)]
    assert transcript(out) == transcript(retained), "CHANGED_PUBLIC_TRANSCRIPT"
    assert out.count("DIAGNOSTIC_STOP_INCOMPLETE") == 1 and "TRANSCRIPT_COMPLETE" not in out
    samples = lambda path: [int(s, 16) for s in path.read_text().splitlines()
                            if not s.startswith("//")]
    changes = samples(run.directory/"public-samples.mem")
    assert changes == samples(reference/"public-samples.mem"), "CHANGED_PUBLIC_HOST_STREAM"
    observed = {}
    for line in out.splitlines():
        f = line.split()
        if f and f[0] == "W":
            observed.setdefault(int(f[1], 16), []).append(int(f[2], 16))
    assert sum(map(len, observed.values())) == 696
    assert all(a in expected and values == expected[a][:len(values)]
               for a, values in observed.items()), "INDEPENDENT_WRITE_PREFIX"

    # Reconstruct only Active-region rising-edge public observations. The
    # compressed stream is exact and already compared in full above.
    records, cursor, held, pending = [], 0, None, False
    for cycle in range(100000):
        sample_index = 4+3*cycle
        while cursor < len(changes) and changes[cursor] >> 853 <= sample_index:
            held = changes[cursor]
            cursor += 1
        public = held & ((1 << 156)-1)
        values, shift = {}, 156
        for name, width in PUBLIC_FIELDS:
            shift -= width
            values[name] = (public >> shift) & ((1 << width)-1)
        inputs = (held >> 156) & ((1 << 601)-1)
        ready, rsp_valid = (inputs >> 36) & 1, (inputs >> 35) & 1
        request = values["mem_req_valid"] and ready
        response = rsp_valid and values["mem_rsp_ready"]
        records.append({
            "requests": int(bool(request)), "responses": int(bool(response)),
            "request_stall": int(values["mem_req_valid"] and not ready),
            "response_not_present": int(pending and not rsp_valid),
            "response_backpressure": int(rsp_valid and not values["mem_rsp_ready"]),
            "no_external_transaction": int(not pending and not values["mem_req_valid"])})
        if response:
            assert pending
            pending = False
        if request:
            assert not pending
            pending = True
    assert sum(r["requests"] for r in records) == 12247
    for item in intervals:
        item["simulation_cycles"] = item["end"]-item["start"]
        item["pin_counts"] = {name: sum(r[name] for r in records[item["start"]:item["end"]])
                              for name in records[0]}
    totals = {}
    for item in intervals:
        group = totals.setdefault(item["kind"], {"windows": 0, "simulation_cycles": 0,
                                                 **dict.fromkeys(records[0], 0)})
        group["windows"] += 1
        group["simulation_cycles"] += item["simulation_cycles"]
        for name, value in item["pin_counts"].items():
            group[name] += value
    run.receipt["intervals"] = intervals
    run.receipt["interval_totals"] = totals
    statistics = out+"\n"+err
    run.receipt["simulator_event_statistics"] = {
        name: int(match.group(1)) for name in (
            "time steps", "thread schedule events", "assign events", "other events")
        if (match := re.search(r"(\d+)\s+"+name, statistics))}
    assert "thread schedule events" in run.receipt["simulator_event_statistics"]
    run.receipt["assertions"].append({
        "exact_sampled_public_host_observations": 300004,
        "exact_change_records": len(changes), "exact_request_records": 12247,
        "independent_prefix_writes": 696, "all_original_protocol_monitors_retained": True,
        "full_fixture_completed": False})
    run.receipt["limitations"] = (
        "Cycle categories are observable overlaps, not mutually exclusive CPU attribution. "
        "Dense windows exclude preceding activation loads and include row/output gaps. "
        "Attention windows include Q/K/V bus waits, score/exp/weighted reduction and head "
        "handoffs; no private helper timing is observed. Event statistics cover the entire "
        "instrumented run, not individual operators. No baseline rerun or overhead "
        "subtraction; later vision tokens and all downstream stages remain unobserved.")
    run.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--cycles", type=int, default=300000)
    parser.add_argument("--host-replay", action="store_true")
    parser.add_argument("--monitored-host-cost", action="store_true")
    parser.add_argument("--playback-control", action="store_true")
    parser.add_argument("--lookup-cost", action="store_true")
    parser.add_argument("--lookup-analysis")
    parser.add_argument("--projection-attention-cost", action="store_true")
    parser.add_argument("--reference",
                        default="evidence/preparation/q40-current-monitored-host-b17-007")
    parser.add_argument("--playback-results")
    parser.add_argument("--refresh-playback-controls", action="store_true")
    parser.add_argument("--configuration", choices=("B", "C"), default="B")
    parser.add_argument("--repair-of",
                        default="evidence/preparation/q40-divider-b-joint-002/receipt.json")
    args = parser.parse_args()
    directory = (ROOT / args.output).resolve()
    assert directory.is_relative_to(ROOT / "evidence/preparation")
    assert 0 < args.cycles <= 300000
    assert not args.host_replay or args.cycles <= 100000
    assert not args.monitored_host_cost or args.cycles <= 100000
    run = Run(directory, budget=100 if args.monitored_host_cost or args.playback_control or args.lookup_cost else 60,
              repair_of=args.repair_of)
    try:
        run.tools(("python3", "iverilog", "vvp"))
        if args.projection_attention_cost:
            assert args.configuration == "B" and args.cycles == 100000
            projection_attention_cost(run, args.reference)
            run.finish("diagnostic-incomplete")
            print(json.dumps({"status": run.receipt["status"],
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 0
        if args.lookup_analysis:
            lookup_gap_analysis(run, args.lookup_analysis)
            run.finish("diagnostic-analysis")
            print(json.dumps({"status": run.receipt["status"],
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 0
        if args.lookup_cost:
            assert args.configuration == "B" and args.cycles == 100000
            lookup_cost(run, args.reference)
            run.finish("diagnostic-incomplete")
            print(json.dumps({"status": run.receipt["status"],
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 0
        if args.playback_control:
            playback_cost(run, args.reference, args.playback_results,
                          args.refresh_playback_controls)
            run.finish("diagnostic-incomplete")
            print(json.dumps({"status": run.receipt["status"],
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 0
        if args.monitored_host_cost:
            current_host_cost(run, args.configuration, args.cycles)
            run.finish("diagnostic-incomplete")
            print(json.dumps({"status": run.receipt["status"],
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 0
        fixture = Fixture(CONFIGS[args.configuration], 17, 2)
        _, expected = fixture.run(Integer())
        run.receipt["fixture"] = {
            "configuration": dataclasses.asdict(fixture.c), "seed": 17,
            "mode": 2, "diagnostic_only": True,
            "expected_write_count": sum(map(len, expected.values())),
        }
        memory = directory / "input.mem"
        memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                                 for a, v in sorted(fixture.mem.items())))
        text = bench(fixture, memory, (fixture.layout["end"]-SCRATCH)//4)
        text = text.replace("integer fd,rc", "integer write_count=0;\n"
                            "reg [63:0] latest_address=0;\ninteger fd,rc")
        text = text.replace("pending=1; response_at=", "latest_address=mem_req_addr;\n"
                            "   pending=1; response_at=")
        text = text.replace('$display("W %h %h",mem_req_addr,mem_req_wdata);',
                            'write_count=write_count+1;\n'
                            '     $display("W %h %h",mem_req_addr,mem_req_wdata);')
        if args.host_replay:
            text = text.replace("mem_rsp_rdata=read_value;", """
   mem_rsp_rdata=read_value;
   $display("T %0d %h %0d %h %h",cycles,mem_req_addr,mem_req_write,mem_req_wdata,read_value);
""")
        text = text.replace("endmodule", f"""
always @(negedge clk) if(rst_n && cycles%10000==0) begin
 $display("PROGRESS time=%0t cycles=%0d requests=%0d responses=%0d writes=%0d latest=%h",
          $time,cycles,requests,responses,write_count,latest_address);
 $fflush();
 if(cycles>={args.cycles}) begin
  $display("DIAGNOSTIC_STOP_INCOMPLETE"); $fflush(); $finish;
 end
end
endmodule
""")
        tb, executable = directory/"progress.sv", directory/"progress.vvp"
        tb.write_text(text)
        run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o",
                     executable, *rtl_files(), tb], "compile", timeout=20)
        try:
            run.command(["vvp", "-v", executable], "simulate", timeout=45)
        finally:
            stdout = (directory/"simulate.stdout").read_text()
            observed = {}
            for line in stdout.splitlines():
                fields = line.split()
                if fields and fields[0] == "W":
                    observed.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
            mismatches = [hex(a) for a, values in observed.items()
                          if a not in expected or values != expected[a][:len(values)]]
            run.receipt["assertions"].append({
                "compared_prefix_writes": sum(map(len, observed.values())),
                "compared_addresses": len(observed), "mismatches": mismatches,
                "public_progress": [line for line in stdout.splitlines()
                                    if line.startswith("PROGRESS ")],
                "full_fixture_complete": "TRANSCRIPT_COMPLETE" in stdout,
                "diagnostic_stop": "DIAGNOSTIC_STOP_INCOMPLETE" in stdout,
            })
            run.save()
            assert not mismatches, f"integer write-prefix mismatch: {mismatches}"
        if args.host_replay:
            replay_host(run, fixture, memory, stdout)
        run.finish("diagnostic-incomplete")
    except Exception as error:
        run.receipt["traceback"] = traceback.format_exc()
        timed_out = any(record.get("timed_out") for record in run.receipt["executions"])
        run.finish("diagnostic-incomplete" if timed_out else "failed", str(error))
    print(json.dumps({"status": run.receipt["status"],
                      "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
    return int(run.receipt["status"] == "failed")


if __name__ == "__main__":
    sys.exit(main())
