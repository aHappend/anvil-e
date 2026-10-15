#!/usr/bin/env python3
"""Public-pin verification entry point. Missing coverage is a failure, not a skip."""
import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import dataclasses
import hashlib
import json
import os
import re
import resource
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
from model import (CONFIGS, Config, Fixture, Floating, Integer, Q, materialize, SCRATCH,
                   WEIGHTS, VISION, IMAGE, IDS, POSITIONS, MASKS)

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_STAGES = {
    "anvil_e2_vision_patch_embed", "anvil_e2_vision_encoder_layer",
    "anvil_e2_vision_pool_proj", "anvil_e2_multimodal_fusion",
    "anvil_e2_text_frontend_ple", "anvil_e2_hybrid_layer", "anvil_e2_pool_norm",
}


def sources():
    paths = []
    for pattern in ("rtl/*.sv", "design/*.md", "tests/*.py",
                    "anvil_e1_reference/rtl/*.sv"):
        found = sorted(ROOT.glob(pattern))
        assert found, f"missing source match: {pattern}"
        paths.extend(found)
    paths.extend(ROOT/"hf_embeddinggemma2_vision_spec"/p for p in (
        "config.json", "vision_model_tensors.json", "language_model_tensors.json",
        "modules.json", "1_Pooling/config.json", "sentence_bert_config.json"))
    assert all(p.is_file() for p in paths), "missing authoritative input"
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in paths}


class Run:
    def __init__(self, directory, budget=86400, repair_of=None, *, deadline=None):
        began = time.monotonic()
        assert 0 < budget <= 86400, "runner budget must be bounded by 86400 seconds"
        self.directory = Path(directory).resolve()
        self.directory.mkdir(parents=True, exist_ok=False)
        self.start = time.time()
        self.deadline = min(began+budget, deadline) if deadline is not None else began+budget
        self.receipt = {
            "cwd": str(ROOT), "started_at": self.start, "timeout_s": budget,
            "source_sha256": sources(), "repair_of": repair_of,
            "tools": {}, "executions": [], "assertions": [], "coverage": [],
            "status": "running",
            "entry_argv": [sys.executable, *sys.argv],
            "absolute_monotonic_deadline": self.deadline,
        }
        self.save()

    def save(self):
        # This directory is unique to one execution; completed receipts are
        # never reopened by another invocation.
        (self.directory/"receipt.json").write_text(json.dumps(self.receipt, indent=2))

    def command(self, argv, name, timeout=20, expected=0):
        assert timeout > 0, "child watchdog must be positive"
        stdout, stderr = self.directory/(name+".stdout"), self.directory/(name+".stderr")
        record = {"argv": [str(a) for a in argv], "cwd": str(ROOT),
                  "requested_timeout_s": timeout,
                  "stdout": str(stdout.relative_to(ROOT)),
                  "stderr": str(stderr.relative_to(ROOT))}
        self.receipt["executions"].append(record)
        self.save()
        process = None
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        begin = time.monotonic()
        try:
            with stdout.open("w") as out, stderr.open("w") as err:
                remaining = self.deadline-time.monotonic()
                effective = min(timeout, remaining)
                record.update(started_at=time.time(), remaining_common_s=remaining,
                              timeout_s=max(0, effective), effective_timeout_s=max(0, effective))
                assert effective > 0, "operation budget exhausted"
                launch = time.monotonic()
                process = subprocess.Popen(record["argv"], cwd=ROOT, stdout=out, stderr=err)
                record["pid"] = process.pid
                # Launch overhead consumes the same watchdog, not a fresh one.
                wait_limit = min(launch+effective, self.deadline)-time.monotonic()
                try:
                    process.wait(timeout=max(0, wait_limit))
                    record.update(exit_code=process.returncode, timed_out=False)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    record.update(exit_code=process.returncode, timed_out=True)
                    raise AssertionError(f"tool timeout: {name}")
        finally:
            if process is not None and process.returncode is None:
                process.kill()
                process.wait()
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            record.update(
                elapsed_s=time.monotonic()-begin,
                child_user_cpu_s=after.ru_utime-usage.ru_utime,
                child_system_cpu_s=after.ru_stime-usage.ru_stime,
                cpu_accounting="RUSAGE_CHILDREN delta; nonexclusive if commands overlap",
                cleanup={"launched": process is not None,
                         "direct_child_reaped": process is not None and process.returncode is not None},
                stdout_bytes=stdout.stat().st_size if stdout.exists() else 0,
                stderr_bytes=stderr.stat().st_size if stderr.exists() else 0)
            record["ended_at"] = time.time()
            self.save()
        if expected is not None:
            assert process.returncode == expected, (
                f"{name}: exit {process.returncode}, expected {expected}; see {stderr}")
        return stdout.read_text(), stderr.read_text(), process.returncode

    def timing(self, name, began):
        self.receipt.setdefault("python_phases", []).append({
            "phase": name, "elapsed_s": time.monotonic()-began[0],
            "python_cpu_s": time.process_time()-began[1]})
        self.save()
        assert time.monotonic() < self.deadline, "operation budget exhausted"

    def tools(self, names):
        for name in names:
            path = shutil.which(name)
            assert path, f"missing prerequisite: {name}"
            flag = "-V" if name in ("iverilog", "vvp", "yosys") else "--version"
            out, err, code = self.command([path, flag], "version-"+name, expected=None)
            assert code == 0, f"cannot query tool version: {name}"
            self.receipt["tools"][name] = {"path": path, "version": out+err}
        self.save()

    def finish(self, status, error=None):
        self.receipt.update(status=status, ended_at=time.time(), error=error)
        self.save()


def fixture_candidates(run, cases, workers=2):
    """Bounded scheduler candidate; each case owns its receipt and artifacts."""
    assert workers in (1, 2)
    assert len({name for name, _ in cases}) == len(cases), "duplicate case name"
    started = time.monotonic()
    results = {}
    pending = iter(enumerate(cases))
    failures = []

    def execute(index, name, fixture):
        child = Run(run.directory/name, deadline=run.deadline)
        child.receipt["tools"] = run.receipt["tools"]
        child.receipt["scheduler_case"] = {"index": index, "name": name}
        begin = time.monotonic()
        try:
            execute_fixture(child, name, fixture)
            assert len(child.receipt["coverage"]) == 1, "missing case comparison"
            assert time.monotonic() < run.deadline, "case exceeded common deadline"
        except Exception as error:
            child.finish("failed", str(error))
            return index, child, time.monotonic()-begin, str(error)
        child.finish("passed")
        return index, child, time.monotonic()-begin, None

    # Exiting the executor waits for all launched work, including failed tools'
    # subprocess.run timeout cleanup; no worker receives a renewed deadline.
    with ThreadPoolExecutor(max_workers=workers) as pool:
        active = {}

        def launch():
            if failures:
                return
            item = next(pending, None)
            if item is not None:
                index, (name, fixture) = item
                active[pool.submit(execute, index, name, fixture)] = index

        for _ in range(workers):
            launch()
        while active:
            complete, _ = wait(active, return_when=FIRST_COMPLETED)
            for future in sorted(complete, key=lambda f: active[f]):
                index = active.pop(future)
                try:
                    result = future.result()
                except Exception as error:
                    failures.append(f"{cases[index][0]}: {error}")
                else:
                    results[index] = result
                    if result[3] is not None:
                        failures.append(f"{cases[index][0]}: {result[3]}")
            for _ in range(workers-len(active)):
                launch()

    record = {"workers": workers, "common_deadline": run.deadline,
              "elapsed_s": time.monotonic()-started,
              "planned_cases": [name for name, _ in cases], "cases": []}
    for index in sorted(results):
        _, child, elapsed, error = results[index]
        record["cases"].append({
            "case": cases[index][0], "elapsed_s": elapsed, "error": error,
            "status": child.receipt["status"],
            "receipt": str((child.directory/"receipt.json").relative_to(ROOT)),
        })
        run.receipt["assertions"].extend(child.receipt["assertions"])
        run.receipt["coverage"].extend(child.receipt["coverage"])
    run.receipt.setdefault("scheduler_batches", []).append(record)
    run.save()
    assert not failures, "; ".join(failures)
    assert len(results) == len(cases), "unfinished scheduler cases"
    return record


def parameter_args(c, top="anvil_e2_top"):
    return [f"-P{top}.{k}={v}" for k, v in dataclasses.asdict(c).items()]


def rtl_files(directory=None):
    return sorted((directory or ROOT/"rtl").glob("*.sv"))


def check_authority(run):
    folder = ROOT/"hf_embeddinggemma2_vision_spec"
    config = json.loads((folder/"config.json").read_text())
    language = json.loads((folder/"language_model_tensors.json").read_text())
    vision = json.loads((folder/"vision_model_tensors.json").read_text())
    assert config["vision_config"]["num_hidden_layers"] == 16
    assert config["text_config"]["num_hidden_layers"] == 24
    assert [i for i, x in enumerate(config["text_config"]["layer_types"])
            if x == "full_attention"] == [5, 11, 17, 23]
    assert language["global_tensors"]["language_model.embedding_projection.weight"]["shape"] == [768, 512]
    assert vision, "empty vision manifest"
    pooling = json.loads((folder/"1_Pooling/config.json").read_text())
    assert pooling["pooling_mode"] == "mean" and pooling["include_prompt"]
    assert len(json.loads((folder/"modules.json").read_text())) == 3
    assert json.loads((folder/"sentence_bert_config.json").read_text())
    run.receipt["assertions"].append("authoritative configuration and manifest presence")


def bench(fixture, memory_path, scratch_words, max_cycles=3000000,
          expected_error=0, descriptor=None, inject=None, reset_phase=None,
          jobs=1):
    """Memory responder accesses only top-level pins and independent host memory."""
    c = fixture.c
    params = ", ".join(f".{k}({v})" for k, v in dataclasses.asdict(c).items())
    descriptor = descriptor or {}
    mode = descriptor.get("mode", fixture.mode)
    tokens = descriptor.get("tokens", len(fixture.ids))
    rows = descriptor.get("rows", fixture.rows)
    cols = descriptor.get("cols", fixture.cols)
    dim = descriptor.get("dimension", fixture.dimension)
    bases = {"weights_base": WEIGHTS, "vision_weights_base": VISION,
             "image_base": IMAGE, "tokens_base": IDS, "positions_base": POSITIONS,
             "mask_base": MASKS, "scratch_base": SCRATCH}
    bases.update(descriptor.get("bases", {}))
    base_declarations = "\n".join(f"reg [63:0] {k}=64'h{v:x};" for k, v in bases.items())
    ports = ["clk", "rst_n", "job_valid", "job_mode", "job_tokens", "job_patch_rows",
             "job_patch_cols", "job_output_dim", *bases, "mem_req_ready", "mem_rsp_valid",
             "mem_rsp_rdata", "mem_rsp_error", "emb_ready", "done_ready", "job_ready",
             "mem_req_valid", "mem_req_write", "mem_req_addr", "mem_req_wdata",
             "mem_rsp_ready", "emb_valid", "emb_data", "emb_index", "emb_last",
             "done_valid", "done_error", "busy"]
    public = "{job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata," \
             "mem_rsp_ready,emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy}"
    inject_expr = "0"
    if inject == "image":
        inject_expr = f"!mem_req_write && mem_req_addr>=64'h{IMAGE:x} && mem_req_addr<64'h{IDS:x}"
    elif inject == "text":
        inject_expr = f"!mem_req_write && mem_req_addr>=64'h{IDS:x} && mem_req_addr<64'h{SCRATCH:x}"
    elif inject == "write":
        inject_expr = "mem_req_write"
    elif inject in ("vision-v", "text-v"):
        region, following = ("vv", "soft") if inject == "vision-v" else ("v", "end")
        inject_expr = (f"!mem_req_write && mem_req_addr>=64'h{fixture.layout[region]:x}"
                       f" && mem_req_addr<64'h{fixture.layout[following]:x}")
    else:
        assert inject is None, f"unknown memory-error target: {inject}"
    reset_expr = {"request": "mem_req_valid && !mem_req_ready",
                  "response": "pending && !mem_rsp_valid",
                  "output": "emb_valid && !emb_ready"}.get(reset_phase, "0")
    return f"""
module tb;
reg clk=0;
reg rst_n=0;
always #5 clk=~clk;
reg job_valid=0;
reg [1:0] job_mode={mode};
reg [31:0] job_tokens={tokens},job_patch_rows={rows},job_patch_cols={cols};
reg [15:0] job_output_dim={dim};
{base_declarations}
reg mem_req_ready=0,mem_rsp_valid=0,mem_rsp_error=0,emb_ready=0,done_ready=0;
reg [31:0] mem_rsp_rdata=0;
wire job_ready,mem_req_valid,mem_req_write,mem_rsp_ready,emb_valid,emb_last,done_valid,busy;
wire [63:0] mem_req_addr;
wire [31:0] mem_req_wdata;
wire signed [31:0] emb_data;
wire [15:0] emb_index;
wire [3:0] done_error;
anvil_e2_top #({params}) dut ({",".join("."+p+"("+p+")" for p in ports)});
localparam WORDS={scratch_words};
reg [31:0] scratch [0:WORDS-1];
reg initialized [0:WORDS-1];
reg [63:0] addresses [0:{len(fixture.mem)-1}];
reg [31:0] values [0:{len(fixture.mem)-1}];
integer fd,rc,i,lo,hi,mid,entry,count=0,cycles=0;
integer requests=0,responses=0,beats=0,reqstalls=0,rspstalls=0,embstalls=0,donestalls=0;
integer accept_cycle=-1,final_cycle=-1,completion_cycle=-1,response_at=0,completed_jobs=0;
integer first_output=-1,first_done=-1;
reg pending=0,stalled_request=0,stalled_embedding=0,stalled_done=0;
reg [96:0] held_request;
reg [48:0] held_embedding;
reg [3:0] held_error;
reg active=0, reset_done=0, injected=0, error_retired=0;
reg [31:0] read_value;
task automatic known;
begin
 if ((^{public})===1'bx) $fatal(1,"UNKNOWN_PUBLIC cycle=%0d",cycles);
 if (!rst_n && {public} !== '0) $fatal(1,"RESET_OUTPUT cycle=%0d",cycles);
end
endtask
initial begin
 for(i=0;i<WORDS;i=i+1) initialized[i]=0;
 fd=$fopen("{memory_path}","r");
 if(fd==0) $fatal(1,"MEMORY_FILE");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\\n",addresses[count],values[count]);
  if(rc==2) count=count+1;
 end
 $fclose(fd);
 if(count!={len(fixture.mem)}) $fatal(1,"MEMORY_LENGTH");
 #0; known(); #1; known();
 #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1;
  if(cycles>{max_cycles}) $fatal(1,"INCOMPLETE_TRANSCRIPT");
  if(!active && !reset_done && cycles>3) job_valid=1;
  if(cycles<=3 && (job_ready!==1 || busy!==0 || mem_req_valid!==0 || done_valid!==0))
    $fatal(1,"AUTONOMOUS_JOB");
  if(active && job_ready) $fatal(1,"READY_WHILE_BUSY");
  mem_req_ready=(cycles%7!=0 && cycles%7!=1 && cycles%7!=2);
  if(emb_valid && first_output<0) first_output=cycles;
  if(done_valid && first_done<0) first_done=cycles;
  emb_ready=first_output>=0 && cycles>first_output+25 && cycles%41>=17;
  done_ready=first_done>=0 && cycles>first_done+25 && cycles%43>=19;
  mem_rsp_valid=pending && cycles>=response_at;
  if({reset_expr} && !reset_done) begin
   rst_n=0; job_valid=0; mem_rsp_valid=0; pending=0; reset_done=1;
   #1; known();
   $display("RESET_OBSERVED {reset_phase}"); #11;
   rst_n=1; #10;
   if(job_ready!==1 || busy!==0 || emb_valid!==0 || done_valid!==0 || mem_req_valid!==0)
     $fatal(1,"CANCELED_JOB_RESUMED");
   $display("RESET_COMPLETE"); $finish;
  end
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(stalled_request && (!mem_req_valid ||
     {{mem_req_write,mem_req_addr,mem_req_wdata}}!==held_request))
    $fatal(1,"REQUEST_STABILITY");
  if(stalled_embedding && (!emb_valid ||
     {{emb_data,emb_index,emb_last}}!==held_embedding))
    $fatal(1,"EMBEDDING_STABILITY");
  if(stalled_done && (!done_valid || done_error!==held_error))
    $fatal(1,"COMPLETION_STABILITY");
  stalled_request=mem_req_valid && !mem_req_ready;
  held_request={{mem_req_write,mem_req_addr,mem_req_wdata}};
  stalled_embedding=emb_valid && !emb_ready;
  held_embedding={{emb_data,emb_index,emb_last}};
  stalled_done=done_valid && !done_ready; held_error=done_error;
  if(stalled_request) reqstalls=reqstalls+1;
  if(stalled_embedding) embstalls=embstalls+1;
  if(stalled_done) donestalls=donestalls+1;
  if(mem_rsp_valid && !mem_rsp_ready) rspstalls=rspstalls+1;
  if(job_valid && job_ready) begin
   if(active) $fatal(1,"DUPLICATE_JOB");
   accept_cycle=cycles; active=1;
  end
  if(mem_req_valid && cycles<=accept_cycle+1) $fatal(1,"EARLY_REQUEST");
  if(mem_rsp_valid && mem_rsp_ready) begin
   if(!pending || cycles<response_at) $fatal(1,"RESPONSE_PROTOCOL");
   pending=0; responses=responses+1;
   if(mem_rsp_error) error_retired=1;
  end
  if(error_retired && mem_req_valid) $fatal(1,"REQUEST_AFTER_ERROR");
  if(mem_req_valid && mem_req_ready) begin
   if(pending) $fatal(1,"MULTIPLE_OUTSTANDING");
   if(mem_req_addr[1:0]!==0) $fatal(1,"UNALIGNED");
   pending=1; response_at=cycles+2+(requests%3); requests=requests+1;
   mem_rsp_error=0; read_value=0;
   if({inject_expr} && !injected) begin
    mem_rsp_error=1; injected=1;
    $display("I %h",mem_req_addr);
   end
   if(mem_req_write) begin
    if(mem_req_addr<64'h{SCRATCH:x} ||
       mem_req_addr>=64'h{SCRATCH+scratch_words*4:x}) $fatal(1,"UNEXPECTED_WRITE");
    entry=(mem_req_addr-64'h{SCRATCH:x})/4;
    if(!mem_rsp_error) begin
     scratch[entry]=mem_req_wdata; initialized[entry]=1;
     $display("W %h %h",mem_req_addr,mem_req_wdata);
    end
   end else if(mem_req_addr>=64'h{SCRATCH:x} &&
               mem_req_addr<64'h{SCRATCH+scratch_words*4:x}) begin
    entry=(mem_req_addr-64'h{SCRATCH:x})/4;
    if(!initialized[entry]) $fatal(1,"UNINITIALIZED_READ %h",mem_req_addr);
    read_value=scratch[entry];
   end else begin
    lo=0; hi=count-1; entry=-1;
    while(lo<=hi) begin
     mid=(lo+hi)/2;
     if(addresses[mid]==mem_req_addr) begin entry=mid; lo=hi+1; end
     else if(addresses[mid]<mem_req_addr) lo=mid+1;
     else hi=mid-1;
    end
    if(entry<0) $fatal(1,"UNEXPECTED_READ %h",mem_req_addr);
    read_value=values[entry];
   end
   mem_rsp_rdata=read_value;
  end
  if(emb_valid && emb_ready) begin
   if(!active || done_valid || pending) $fatal(1,"OUTPUT_PHASE");
   if(emb_index!==beats || emb_last!==(beats=={dim}-1)) $fatal(1,"OUTPUT_SHAPE");
   $display("E %0d %h %0d",emb_index,emb_data,emb_last);
   beats=beats+1;
   if(emb_last) final_cycle=cycles;
  end
  if(done_valid && done_ready) begin
   if(!active || pending || done_error!==4'd{expected_error}) $fatal(1,"DONE_ERROR %d",done_error);
   if({int(inject is not None)} && (!injected || !error_retired))
     $fatal(1,"MISSING_ERROR_INJECTION");
   if({expected_error}==0 && (beats!={dim} || cycles<=final_cycle)) $fatal(1,"COMPLETION_ORDER");
   if({expected_error}!=0 && beats!=0) $fatal(1,"ERROR_EMBEDDING");
   if(requests!=responses) $fatal(1,"UNRETIRED_TRANSACTION");
   $display("C %0d %0d %0d %0d %0d %0d %0d %0d",
     done_error,requests,responses,beats,reqstalls,rspstalls,embstalls,donestalls);
   completion_cycle=cycles;
   completed_jobs=completed_jobs+1;
   #1;
   if(job_ready!==1 || busy!==0 || done_valid!==0) $fatal(1,"DONE_IDLE");
   if(completed_jobs=={jobs}) begin
    $display("TRANSCRIPT_COMPLETE"); $finish;
   end
   active=0; beats=0; final_cycle=-1;
   first_output=-1; first_done=-1;
   stalled_done=0;
  end
  #1;
  if(active) job_valid=0;
  if(cycles==accept_cycle && (busy!==1 || job_ready!==0 || mem_req_valid!==0))
    $fatal(1,"POST_ACCEPT");
 end
end
endmodule
"""


def execute_fixture(run, name, fixture, directory=None, expected_error=0,
                    descriptor=None, inject=None, reset_phase=None, exact=True,
                    jobs=1, diagnose=False, startup_diagnostic=False):
    began = time.monotonic(), time.process_time()
    integer, writes = fixture.run(Integer())
    run.timing(name+"-integer-oracle", began)
    began = time.monotonic(), time.process_time()
    floating, _ = fixture.run(Floating())
    run.timing(name+"-floating-oracle", began)
    began = time.monotonic(), time.process_time()
    assert expected_error or len(integer) == fixture.dimension, "oracle output shape"
    absolute = max((abs(a/Q-b) for a, b in zip(integer, floating)), default=0)
    norm_error = abs(sum((a/Q)**2 for a in integer)**0.5-1) if any(integer) else 0
    if not diagnose:
        assert absolute <= 0.002, f"oracle mathematical tolerance: {absolute}"
        assert norm_error <= 0.002, f"oracle norm tolerance: {norm_error}"
    mem = run.directory/(name+".mem")
    mem.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                           for a, v in sorted(fixture.mem.items())))
    tb = run.directory/(name+".sv")
    words = (fixture.layout["end"]-SCRATCH)//4
    text = bench(fixture, mem, words, expected_error=expected_error,
                 descriptor=descriptor, inject=inject, reset_phase=reset_phase, jobs=jobs)
    if startup_diagnostic:
        text = text.replace("endmodule", """
initial begin #1; $display("PUBLIC_TIME %0t", $time); $fflush(); end
always @(posedge clk) if(cycles<2000 || cycles%10000==0) begin
 $display("PUBLIC_PROGRESS %0t cycles=%0d requests=%0d responses=%0d valid=%b ready=%b busy=%b",
          $time, cycles, requests, responses, job_valid, job_ready, busy);
 $fflush();
end
endmodule
""")
    tb.write_text(text)
    run.timing(name+"-stimulus", began)
    executable = run.directory/(name+".vvp")
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 *rtl_files(directory), tb], name+"-compile", timeout=120)
    out, _, _ = run.command(["vvp", *(["-v"] if startup_diagnostic else []), executable],
                            name+"-simulate", timeout=30 if startup_diagnostic else 45)
    began = time.monotonic(), time.process_time()
    if reset_phase:
        assert f"RESET_OBSERVED {reset_phase}" in out and "RESET_COMPLETE" in out
        run.receipt["coverage"].append({"case": name, "reset": reset_phase})
        return
    assert out.count("TRANSCRIPT_COMPLETE") == 1, "incomplete transcript"
    beats, observed_writes, completion, injected_addresses = [], {}, [], []
    for line in out.splitlines():
        fields = line.split()
        if fields and fields[0] == "E":
            assert len(fields) == 4
            index, value, last = int(fields[1]), int(fields[2], 16), int(fields[3])
            assert index == len(beats) % fixture.dimension and last == (index == fixture.dimension-1)
            beats.append(value-(1 << 32) if value & (1 << 31) else value)
        elif fields and fields[0] == "W":
            assert len(fields) == 3
            observed_writes.setdefault(int(fields[1], 16), []).append(int(fields[2], 16))
        elif fields and fields[0] == "C":
            assert len(fields) == 9
            completion.append([int(v) for v in fields[1:]])
        elif fields and fields[0] == "I":
            assert len(fields) == 2
            injected_addresses.append(int(fields[1], 16))
    assert len(completion) == jobs and all(c[0] == expected_error for c in completion)
    if expected_error:
        assert not beats, "error produced output"
        if inject is not None:
            assert len(injected_addresses) == 1, "missing/duplicate memory error"
            assert observed_writes.keys() <= writes.keys(), "error-prefix scratch address"
            for address, actual in observed_writes.items():
                assert actual == writes[address][:len(actual)], (
                    f"error-prefix scratch mismatch at {address:#x}")
            if inject in ("vision-v", "text-v"):
                region, following = ("vv", "soft") if inject == "vision-v" else ("v", "end")
                assert fixture.layout[region] <= injected_addresses[0] < fixture.layout[following], (
                    "memory error did not reach the targeted attention V region")
        if expected_error in (1, 5):
            assert completion[0][1] == 0, "invalid descriptor issued memory"
    else:
        if exact:
            assert observed_writes.keys() == writes.keys(), "scratch address coverage mismatch"
            for address, expected in writes.items():
                assert observed_writes[address] == expected * jobs, (
                    f"scratch mismatch at {address:#x}: "
                    f"{observed_writes[address][:8]} != {expected[:8]}")
        assert beats == integer * jobs, f"exact Q24 output mismatch: {beats[:8]} != {integer[:8]}"
        assert completion[0][1] == completion[0][2] > 0
        assert completion[0][4] > 0, "request backpressure not observed"
        assert completion[0][6] >= 25 and completion[0][7] >= 25, "long output/completion stalls missing"
    run.receipt["coverage"].append({
        "case": name, "config": dataclasses.asdict(fixture.c), "seed": fixture.seed,
        "mode": fixture.mode, "dimension": fixture.dimension, "expected_error": expected_error,
        "memory_error_target": inject,
        "injected_addresses": injected_addresses,
        "compared_components": len(beats), "compared_scratch_addresses": len(observed_writes),
        "mathematical_max_abs_error": absolute, "l2_error": norm_error,
        "completion": completion[0], "transcript": str((run.directory/(name+"-simulate.stdout")).relative_to(ROOT)),
    })
    run.save()
    assert absolute <= 0.002, f"mathematical tolerance: {absolute}"
    assert norm_error <= 0.002, f"norm tolerance: {norm_error}"
    run.timing(name+"-scoreboard", began)


def frontend_probe(run):
    """A single nonzero cached PLE operand at the public frontend boundary."""
    run.tools(("python3", "iverilog", "vvp"))
    f = Fixture(CONFIGS["A"], 17, 0)
    f.mem[IMAGE] = -Q//4
    f.mem[f.offsets["ple_model"]] = Q//2
    f.mem[f.offsets["ple_norm"]] = 0
    memory = run.directory/"frontend.mem"
    memory.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                              for a, v in sorted(f.mem.items())))
    text = bench(f, memory, (f.layout["end"]-SCRATCH)//4,
                 descriptor={"tokens": 1}, max_cycles=20000)
    original = text[text.index("anvil_e2_top #("):text.index("localparam WORDS")]
    replacement = """
assign busy=rst_n && !job_ready;
assign mem_req_write=rst_n && cmd_write;
wire cmd_write;
anvil_e2_text_frontend_ple #(
 .HIDDEN_SIZE(1),.PER_LAYER_INPUT_SIZE(1),.INTERMEDIATE_SIZE(1),
 .EMBEDDING_DIM(6),.NUM_LAYERS(1),.NUM_Q_HEADS(4),
 .LOCAL_KV_HEADS(2),.FULL_KV_HEADS(1),.LOCAL_HEAD_DIM(2),.FULL_HEAD_DIM(4),
 .SLIDING_WINDOW(1)
) frontend (
 .clk(clk),.rst_n(rst_n),.start_valid(job_valid),.start_ready(job_ready),
 .tokens(32'd1),.valid_tokens(32'd1),.output_dim(16'd6),
 .weights(weights_base),.token_ids(tokens_base),.positions(positions_base),
 .masks(mask_base),.scratch(scratch_base),.x0_base(64'h30000000),
 .x1_base(64'h70000040),.ple_base(64'h70000000),
 .q_base(64'h70000080),.k_base(64'h70000100),.v_base(64'h70000140),
 .layer_index(32'd0),.patch_cols(32'd1),.start_current_x(1'b0),
 .cmd_valid(mem_req_valid),.cmd_ready(mem_req_ready),
 .cmd_write(cmd_write),.cmd_addr(mem_req_addr),.cmd_wdata(mem_req_wdata),
 .result_valid(mem_rsp_valid),.result_ready(mem_rsp_ready),
 .result_data(mem_rsp_rdata),.result_error(mem_rsp_error),
 .emb_valid(emb_valid),.emb_ready(emb_ready),.emb_data(emb_data),
 .emb_index(emb_index),.emb_last(emb_last),
 .done_valid(done_valid),.done_ready(done_ready),.done_error(done_error)
);
"""
    text = text.replace(original, replacement)
    text = text.replace("if(0==0 && (beats!=6 || cycles<=final_cycle))",
                        "if(beats!=0)")
    text = text.replace("if(mem_req_valid && cycles<=accept_cycle+1)",
                        "if(mem_req_valid && cycles<=accept_cycle)")
    tb = run.directory/"frontend.sv"
    tb.write_text(text)
    executable = run.directory/"frontend.vvp"
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 *rtl_files(), tb], "frontend-compile", timeout=15)
    out, _, _ = run.command(["vvp", executable], "frontend-simulate", timeout=15)
    assert out.count("TRANSCRIPT_COMPLETE") == 1, "incomplete public frontend transcript"
    ops = Integer()
    expected = materialize(ops.norm(
        ops.mat([[ops.decode(Q//2)]], [ops.decode(-Q//4)]), [0])[0])
    lines = [line.split() for line in out.splitlines() if line.startswith("W ")]
    actual = [(int(p[1], 16), int(p[2], 16)) for p in lines]
    run.receipt["assertions"].append({
        "case": "public-singleton-nonzero-PLE", "input_q24": -Q//4,
        "projection_weight_q24": Q//2, "norm_weight_q24": 0,
        "expected_write": [SCRATCH, expected & 0xffffffff], "actual_writes": actual,
    })
    run.save()
    assert actual == [(SCRATCH, expected & 0xffffffff)], (
        f"public PLE mismatch: actual={actual}, expected={(SCRATCH, expected & 0xffffffff)}")


def directed(run):
    c = CONFIGS["A"]
    invalid = [
        ("mode3", {"mode": 3}, 1),
        ("zero-text", {"tokens": 0}, 1),
        ("unsupported-dimension", {"dimension": 3}, 1),
        ("zero-image-grid", {"mode": 2, "rows": 0}, 1),
        ("pool-count-mismatch", {"mode": 2, "cols": 2}, 1),
        ("vision-with-text", {"mode": 1}, 1),
        ("joint-without-text", {"mode": 2, "tokens": 0}, 1),
        ("unaligned-weight", {"bases": {"weights_base": WEIGHTS+1}}, 1),
        ("unaligned-image", {"mode": 2, "bases": {"image_base": IMAGE+1}}, 1),
        ("weight-overflow", {"bases": {"weights_base": 0xfffffffffffffffc}}, 5),
        ("scratch-overflow", {"bases": {"scratch_base": 0xfffffffffffffffc}}, 5),
        ("priority1-before5", {"mode": 3, "bases": {"scratch_base": 0xfffffffffffffffc}}, 1),
    ]
    for name, descriptor, error in invalid:
        execute_fixture(run, name, Fixture(c, 17, 0), expected_error=error,
                        descriptor=descriptor)
    for name, address, value in [("invalid-id", IDS, c.VOCAB_SIZE),
                                 ("invalid-position", POSITIONS, c.MAX_SEQ_LEN),
                                 ("invalid-mask", MASKS, 2)]:
        fixture = Fixture(c, 17, 0)
        fixture.mem[address] = value
        execute_fixture(run, name, fixture, expected_error=2)
    fixture = Fixture(c, 17, 0)
    fixture.masks = [0]*len(fixture.ids)
    fixture.mem.update({MASKS+4*i: 0 for i in range(len(fixture.ids))})
    execute_fixture(run, "all-masked", fixture, expected_error=4)
    for path, mode in (("image", 2), ("text", 0), ("write", 2),
                       ("vision-v", 2), ("text-v", 0)):
        execute_fixture(run, "memory-error-"+path, Fixture(c, 17, mode),
                        expected_error=3, inject=path)
    for phase in ("request", "response", "output"):
        execute_fixture(run, "reset-"+phase, Fixture(c, 17, 2), reset_phase=phase)
    execute_fixture(run, "zero-pooled-vector", Fixture(c, 17, 0, zero=True))
    execute_fixture(run, "back-to-back", Fixture(c, 17, 0), jobs=2)


def illegal_parameters(run):
    for parameter, value in [
        ("VISION_LAYERS", 0), ("TEXT_LAYERS", 0), ("VISION_HIDDEN", 0),
        ("VISION_HEAD_DIM", 2), ("VISION_HEADS", 2), ("PATCH_SIZE", 0),
        ("POOL_KERNEL", 0), ("VISION_SOFT_TOKENS", 0), ("TEXT_HIDDEN", 0),
        ("PLE_DIM", 0), ("TEXT_FFN", 0), ("VISION_FFN", 0), ("EMBED_DIM", 5),
        ("LOCAL_HEAD_DIM", 3), ("LOCAL_KV_HEADS", 3), ("FULL_KV_HEADS", 0),
        ("SLIDING_WINDOW", 0), ("MAX_SEQ_LEN", 0),
    ]:
        name = "illegal-"+parameter
        executable = run.directory/(name+".vvp")
        c = dataclasses.replace(CONFIGS["A"], **{parameter: value})
        run.command(["iverilog", "-g2012", "-Wall", "-s", "anvil_e2_top",
                     "-o", executable, *parameter_args(c), *rtl_files()],
                    name+"-compile", timeout=10)
        out, err, code = run.command(["vvp", executable], name+"-simulate",
                                     timeout=5, expected=None)
        assert code != 0 and "PARAMETER ERROR" in out+err, "missing explicit parameter diagnostic"
        run.receipt["coverage"].append({"case": name, "diagnostic": "PARAMETER ERROR",
                                        "exit_code": code})
        run.save()


def operator_coverage(run):
    targets = ("uniform", "vision_position", "vision_rope", "pool_sample",
               "bridge", "ple", "schedule", "unmasked", "pretruncate",
               "axial_swap", "vision_head_0", "vision_head_1",
               "text_head_0", "text_head_1", "text_head_2", "text_head_3")
    c = CONFIGS["B"]
    baselines = {}
    for alteration in targets:
        dimension = c.EMBED_DIM//3 if alteration == "pretruncate" else c.EMBED_DIM
        if dimension not in baselines:
            fixture = Fixture(c, 17, 2, dimension)
            original, writes = fixture.run(Integer())
            baselines[dimension] = fixture, original, writes
        fixture, original, writes = baselines[dimension]
        changed, other_writes = fixture.run(Integer(), alteration)
        assert original != changed, f"fixture insensitive to {alteration}"
        run.receipt["assertions"].append({
            "operator": alteration, "seed": 17, "configuration": "B", "mode": 2,
            "counterfactual_changed_components": sum(a!=b for a, b in zip(original, changed)),
            "counterfactual_changed_scratch": sum(writes[a]!=other_writes.get(a) for a in writes),
        })
    run.save()


def behavior(run):
    run.tools(("python3", "iverilog", "vvp"))
    check_authority(run)
    run.command(["iverilog", "-g2012", "-Wall", "-t", "null", "-s", "anvil_e2_top",
                 *rtl_files()], "default-elaboration", timeout=20)
    for label, c in CONFIGS.items():
        seeds = (17, 89) if label in ("B", "C") else (17,)
        dimensions = (768, 512, 256, 128) if label == "D" else (
            (1, 2, 4, 6) if label == "A" else (c.EMBED_DIM,))
        for seed in seeds:
            for mode in (0, 1, 2):
                for dim in dimensions:
                    execute_fixture(run, f"{label}-s{seed}-m{mode}-d{dim}",
                                    Fixture(c, seed, mode, dim))
    from stages import (focused, extremes, guard_boundaries, guarded_norm,
                        guarded_divider, guarded_nonlinear)
    guard_boundaries(run)
    guarded_divider(run)
    guarded_norm(run)
    guarded_nonlinear(run)
    from cursor_boundaries import boundaries
    boundaries(run)
    from attention_boundaries import boundaries as attention_boundaries
    attention_boundaries(run)
    focused(run)
    directed(run)
    illegal_parameters(run)
    operator_coverage(run)
    extremes(run)
    # Retain the case that exposed the floating oracle's unquantized epsilon.
    execute_fixture(run, "six-layer-numerical-regression",
                    Fixture(dataclasses.replace(CONFIGS["C"], VISION_LAYERS=1,
                                                TEXT_LAYERS=6), 17, 2))
    covered = {a["operator"] for a in run.receipt["assertions"] if "operator" in a}
    assert {"axial_swap", "vision_head_0", "vision_head_1",
            "text_head_0", "text_head_1", "text_head_2", "text_head_3"} <= covered
    assert any(a.get("integer_extremes") for a in run.receipt["assertions"])


def sensitivity(run, selected=None):
    run.tools(("python3", "iverilog", "vvp"))
    mutations = [
        ("vision-position", "anvil_e2_vision_patch_embed.sv",
         "value<=sat({{80{value[47]}},value}+\n"
         "                           {{80{result_data[31]}},result_data,16'd0});",
         "value<=value;", "A", 6),
        ("soft-token-fusion", "anvil_e2_multimodal_fusion.sv",
         "value<=image_slot ? $signed(result_data):scale(result_data);",
         "value<=image_slot ? 32'sd0:scale(result_data);", "A", 6),
        ("PLE-bypass", "anvil_e2_hybrid_layer.sv",
         "50: if (!VISION) `E2_VECTOR(2,0,2,0,HIDDEN_SIZE,51)",
         "50: if (!VISION) begin pc<=51; end", "A", 6),
        ("full-local-schedule", "anvil_e2_attention.sv",
         "else if (full_mode) begin component<=0; state<=KREQ; end",
         "else if (full_mode && VISION) begin component<=0; state<=KREQ; end", "C", 12),
        ("normalize-before-truncate", "anvil_e2_pool.sv",
         "if (channel==dimension-1) begin channel<=0; state<=NSTART; end",
         "if (channel==EMBEDDING_DIM-1) begin channel<=0; state<=NSTART; end", "A", 2),
    ]
    for name, filename, before, after, configuration, dim in mutations:
        if selected is not None and name not in selected:
            continue
        directory = run.directory/name
        directory.mkdir()
        for source in rtl_files():
            shutil.copyfile(source, directory/source.name)
        path = directory/filename
        original = path.read_text()
        assert before in original, f"mutation source match missing: {name}"
        path.write_text(original.replace(before, after))
        if name == "normalize-before-truncate":
            text = path.read_text()
            text = text.replace("{16'd0,dimension}:32'd0", "32'(EMBEDDING_DIM):32'd0")
            text = text.replace("if (channel==dimension-1) begin channel<=0; state<=NOUTPUT; end",
                                "if (channel==EMBEDDING_DIM-1) begin channel<=0; state<=NOUTPUT; end")
            text = text.replace("norm_out_last!=(channel==dimension-1)",
                                "norm_out_last!=(channel==EMBEDDING_DIM-1)")
            text = text.replace("if (channel==dimension-1) begin\n                            channel<=0;",
                                "if (channel==EMBEDDING_DIM-1) begin\n                            channel<=0;")
            path.write_text(text)
        record = {"mutation": name, "file": filename, "before": before, "after": after,
                  "copied_source_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                           for p in directory.glob("*.sv")}}
        run.receipt["assertions"].append(record)
        run.save()
        start = len(run.receipt["executions"])
        config = CONFIGS[configuration]
        seed, mode = 17, 2
        if name == "full-local-schedule":
            config = dataclasses.replace(config, VISION_LAYERS=1, TEXT_LAYERS=6)
            seed, mode = 89, 0
        fixture = Fixture(config, seed, mode, dim)
        record.update(fixture_config=dataclasses.asdict(config), seed=seed, mode=mode)
        run.save()
        try:
            execute_fixture(run, name, fixture,
                            directory=directory)
        except AssertionError as error:
            executions = run.receipt["executions"][start:]
            assert len(executions)==2 and executions[0]["exit_code"]==0, (
                f"mutation not compiled and executed: {name}: {error}")
            assert not any(e["timed_out"] for e in executions), "mutation timeout not sensitivity"
            message = str(error)
            assert ("scratch mismatch" in message or "exact Q24 output mismatch" in message or
                    ("exit" in message and any(token in
                     (run.directory/(name+"-simulate.stdout")).read_text()
                     for token in ("OUTPUT_SHAPE", "DONE_ERROR", "UNINITIALIZED_READ",
                                   "UNEXPECTED_READ", "OUTPUT_PHASE")))), (
                f"not a functional/protocol rejection: {name}: {message}")
            record.update(rejected=True, detecting_assertion=message)
            run.save()
        else:
            raise AssertionError(f"surviving mutation: {name}")


def synthesis(run, labels=("A", "C"), wrapper=True):
    run.tools(("python3", "yosys"))
    for label in labels:
        c = CONFIGS[label]
        script = run.directory/(label+".ys")
        netlist = run.directory/(label+".json")
        commands = [
            "read_verilog -sv -defer " + " ".join(str(p) for p in rtl_files()),
            "hierarchy -check -top anvil_e2_top " +
            " ".join(f"-chparam {k} {v}" for k, v in dataclasses.asdict(c).items()),
            "proc", "opt -fast -noff", "memory_collect",
            "check -assert", "stat", f"write_json {netlist}",
        ]
        root_module = "anvil_e2_top"
        if wrapper:
            root_module = "synthesis_fixture"
            source = (ROOT/"rtl/anvil_e2_top.sv").read_text()
            ports = source.split(") (", 1)[1].split(");", 1)[0]
            fixture = run.directory/(label+"-synthesis-fixture.sv")
            fixture.write_text("module synthesis_fixture (\n"+ports+");\n"
                               "anvil_e2_top #("+
                               ",".join(f".{k}({v})" for k, v in dataclasses.asdict(c).items())+
                               ") implementation (.*);\nendmodule\n")
            run.receipt.setdefault("generated_source_sha256", {})[
                str(fixture.relative_to(ROOT))] = hashlib.sha256(fixture.read_bytes()).hexdigest()
            commands[0] += " "+str(fixture)
            commands[1] = "hierarchy -check -top synthesis_fixture"
        script.write_text("\n".join(commands)+"\n")
        try:
            run.command(["yosys", "-Q", "-t", "-s", script],
                        label+"-yosys", timeout=60)
        finally:
            log = (run.directory/(label+"-yosys.stdout")).read_text()
            headers = [line for line in log.splitlines()
                       if re.match(r"\[[0-9.]+\]\s+\d+(?:\.\d+)*\.\s", line)]
            derivations = [line.split("Generating RTLIL representation for module ", 1)[1]
                           for line in log.splitlines()
                           if "Generating RTLIL representation for module " in line]
            run.receipt["assertions"].append({
                "synthesis_diagnostic": label, "timestamped_pass_headers": headers,
                "module_derivations": derivations,
                "duplicate_derivations": sorted({x for x in derivations
                                                  if derivations.count(x) > 1}),
                "last_log_lines": log.splitlines()[-12:],
            })
            run.save()
        data = json.loads(netlist.read_text())
        modules = data["modules"]
        assert root_module in modules
        visited, stages, sequential = set(), set(), 0

        def visit(name):
            nonlocal sequential
            if name in visited:
                return
            visited.add(name)
            module = modules[name]
            assert not int(module.get("attributes", {}).get("blackbox", "0"), 2), "black box"
            hdlname = module.get("attributes", {}).get("hdlname", name).split()[0].lstrip("\\")
            stages.add(hdlname)
            for cell_name, cell in module.get("cells", {}).items():
                kind = cell["type"]
                assert "latch" not in kind.lower(), f"latch {name}/{cell_name}: {kind}"
                assert cell.get("connections"), f"unconnected cell {name}/{cell_name}"
                if kind in modules:
                    child_name = modules[kind].get("attributes", {}).get(
                        "hdlname", kind).split()[0].lstrip("\\")
                    if child_name in REQUIRED_STAGES:
                        for pin in ("clk", "rst_n", "start_valid", "start_ready",
                                    "cmd_valid", "cmd_ready", "result_valid",
                                    "result_ready", "done_valid", "done_ready"):
                            bits = cell["connections"].get(pin, [])
                            assert bits and any(isinstance(b, int) for b in bits), (
                                f"disconnected stage control {name}/{cell_name}.{pin}")
                    visit(kind)
                elif kind.startswith("$"):
                    if "dff" in kind.lower():
                        sequential += 1
                else:
                    raise AssertionError(f"unresolved cell: {kind}")
        visit(root_module)
        assert "anvil_e2_top" in stages, "missing actual product top"
        def contains_state(name, active=frozenset()):
            assert name not in active, "recursive synthesis hierarchy"
            cells = modules[name].get("cells", {}).values()
            return any("dff" in cell["type"].lower() or
                       (cell["type"] in modules and
                        contains_state(cell["type"], active | {name}))
                       for cell in cells)

        for name in visited:
            hdlname = modules[name].get("attributes", {}).get(
                "hdlname", name).split()[0].lstrip("\\")
            if hdlname in REQUIRED_STAGES:
                assert contains_state(name), f"required stage without sequential state: {hdlname}"
        assert REQUIRED_STAGES <= stages, f"missing required stage hierarchy {REQUIRED_STAGES-stages}"
        assert sequential > 0 and modules[root_module]["cells"], "empty/no-state synthesis"
        run.receipt["coverage"].append({"config": label, "reachable_modules": len(visited),
                                        "sequential_cells": sequential, "latches": 0,
                                        "netlist": str(netlist.relative_to(ROOT))})
        run.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", choices=("behavior", "sensitivity", "synthesis"))
    parser.add_argument("--probe", choices=("A", "B", "C", "D", "frontend",
                                           "focused", "directed", "synthesis-A",
                                           "mutation-ple", "mutation-normalize",
                                           "reset-output", "operators", "last-position",
                                           "synthesis-wrapper-A", "synthesis-wrapper-C", "extremes",
                                           "mutation-vision", "mutation-fusion",
                                           "mutation-schedule", "b89-text", "guard-boundaries",
                                           "startup", "numerical-matrix", "guarded-norm",
                                           "guarded-division", "guarded-divider",
                                           "guarded-nonlinear", "six-layer-regression",
                                           "attention-errors"))
    parser.add_argument("--output")
    parser.add_argument("--repair-of")
    parser.add_argument("--probe-seed", type=int, default=17)
    parser.add_argument("--probe-mode", type=int, choices=(0, 1, 2), default=2)
    parser.add_argument("--probe-dimension", type=int)
    args = parser.parse_args()
    assert args.probe or (args.probe_seed == 17 and args.probe_mode == 2 and
                          args.probe_dimension is None), "fixture overrides are preparation-only"
    if args.probe:
        assert args.output, "preparation requires an explicit unique output path"
        directory = ROOT/args.output
        assert directory.is_relative_to(ROOT/"evidence/preparation"), "probe must be project-local"
        checks = [args.probe]
    else:
        checks = [args.check] if args.check else ["behavior", "sensitivity", "synthesis"]
    for check in checks:
        directory = (ROOT/args.output if args.probe else
                     ROOT/"evidence/verification"/check/(str(time.time_ns())+"-"+str(os.getpid())))
        run = Run(directory, 3600 if args.probe else 86400, args.repair_of)
        try:
            if check == "frontend":
                frontend_probe(run)
            elif check == "b89-text":
                run.tools(("python3", "iverilog", "vvp"))
                execute_fixture(run, "B-s89-m0-d12", Fixture(CONFIGS["B"], 89, 0),
                                diagnose=True)
            elif check == "startup":
                run.tools(("python3", "iverilog", "vvp"))
                execute_fixture(run, "startup", Fixture(CONFIGS["A"], 17, 2),
                                startup_diagnostic=True)
            elif check == "guard-boundaries":
                run.tools(("python3",))
                from stages import guard_boundaries
                guard_boundaries(run)
            elif check == "guarded-norm":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import guarded_norm
                guarded_norm(run, diagnostic=True)
            elif check == "guarded-division":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import guarded_division_diagnostic
                guarded_division_diagnostic(run)
            elif check == "guarded-divider":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import guarded_divider
                guarded_divider(run)
            elif check == "guarded-nonlinear":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import guarded_nonlinear
                guarded_nonlinear(run)
            elif check == "six-layer-regression":
                run.tools(("python3", "iverilog", "vvp"))
                execute_fixture(run, "six-layer-numerical-regression",
                                Fixture(dataclasses.replace(CONFIGS["C"], VISION_LAYERS=1,
                                                            TEXT_LAYERS=6), 17, 2))
            elif check == "attention-errors":
                run.tools(("python3", "iverilog", "vvp"))
                for target, mode in (("vision-v", 2), ("text-v", 0)):
                    execute_fixture(run, "memory-error-"+target,
                                    Fixture(CONFIGS["A"], 17, mode),
                                    expected_error=3, inject=target)
            elif check == "numerical-matrix":
                run.tools(("python3",))
                for label, config in CONFIGS.items():
                    seeds = (17, 89) if label in ("B", "C") else (17,)
                    dimensions = (768, 512, 256, 128) if label == "D" else (
                        (1, 2, 4, 6) if label == "A" else (config.EMBED_DIM,))
                    for seed in seeds:
                        for mode in (0, 1, 2):
                            for dim in dimensions:
                                f = Fixture(config, seed, mode, dim)
                                exact, _ = f.run(Integer())
                                mathematical, _ = f.run(Floating())
                                error = max(abs(a/Q-b) for a, b in zip(exact, mathematical))
                                norm_error = abs(sum((a/Q)**2 for a in exact)**0.5-1) if any(exact) else 0
                                run.receipt["assertions"].append({
                                    "oracle_only": True, "config": label, "seed": seed,
                                    "mode": mode, "dimension": dim,
                                    "max_component_error": error, "l2_error": norm_error,
                                    "threshold": 0.002,
                                })
                                run.save()
                                assert error <= 0.002 and norm_error <= 0.002, (
                                    f"{label}/seed{seed}/mode{mode}/dim{dim}: {error}, {norm_error}")
            elif check == "focused":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import focused
                focused(run)
            elif check == "last-position":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import patch
                patch(run, size=1, rows=1, cols=10240)
            elif check == "directed":
                run.tools(("python3", "iverilog", "vvp"))
                directed(run)
                illegal_parameters(run)
            elif check == "synthesis-A":
                synthesis(run, ("A",), wrapper=False)
            elif check == "synthesis-wrapper-A":
                synthesis(run, ("A",), wrapper=True)
            elif check == "synthesis-wrapper-C":
                synthesis(run, ("C",), wrapper=True)
            elif check.startswith("mutation-"):
                selected = {"mutation-ple": "PLE-bypass",
                            "mutation-normalize": "normalize-before-truncate",
                            "mutation-vision": "vision-position",
                            "mutation-fusion": "soft-token-fusion",
                            "mutation-schedule": "full-local-schedule"}
                sensitivity(run, (selected[check],))
            elif check == "extremes":
                run.tools(("python3", "iverilog", "vvp"))
                from stages import extremes
                extremes(run)
            elif check == "reset-output":
                run.tools(("python3", "iverilog", "vvp"))
                execute_fixture(run, "reset-output", Fixture(CONFIGS["A"], 17, 2),
                                reset_phase="output")
            elif check == "operators":
                run.tools(("python3",))
                operator_coverage(run)
            elif args.probe:
                run.tools(("python3", "iverilog", "vvp"))
                fixture = Fixture(CONFIGS[check], args.probe_seed, args.probe_mode,
                                  args.probe_dimension)
                execute_fixture(run, f"{check}-s{fixture.seed}-m{fixture.mode}"
                                f"-d{fixture.dimension}", fixture)
            else:
                globals()[check](run)
        except Exception as error:
            run.finish("failed", str(error))
            traceback.print_exc()
            print(json.dumps({"check": check, "status": "failed",
                              "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
            return 1
        run.finish("passed")
        print(json.dumps({"check": check, "status": "passed",
                          "receipt": str((directory/"receipt.json").relative_to(ROOT))}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
