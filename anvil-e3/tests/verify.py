#!/usr/bin/env python3
"""Independent public-interface verification for Anvil-E3.

Requirement mapping:
  elaboration: production defaults, legal minima/ragged geometries, illegal tuples
  behavior: exact elementary arithmetic, mathematical audio oracle, pin protocol
  synthesis: whole hierarchy, two legal geometries, structural no-latch checks

Checks not yet implemented are failures, never accepted coverage. Preparation
probes are advisory and use fresh, project-local directories with receipts.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import datetime
import hashlib
import json
import math
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
Q = 1 << 24
WIDE = 1 << 40
EPSILON = 17 / Q
SEED = 0xE30017
SOURCES = sorted((ROOT / "rtl").glob("*.sv"))
MINIMUM = dict(
    AUDIO_LAYERS=1, AUDIO_HIDDEN=1, AUDIO_FFN=1, AUDIO_HEADS=1,
    AUDIO_HEAD_DIM=1, AUDIO_OUT_DIM=1, AUDIO_CONV_KERNEL=1,
    AUDIO_SUBSAMPLE_C0=1, AUDIO_SUBSAMPLE_C1=1, AUDIO_FREQ_BINS=1,
    VISION_LAYERS=1, VISION_HIDDEN=4, VISION_FFN=3, VISION_HEADS=1,
    VISION_HEAD_DIM=4, PATCH_SIZE=1, POOL_KERNEL=1, VISION_SOFT_TOKENS=1,
    TEXT_LAYERS=1, TEXT_HIDDEN=1, PLE_DIM=1, TEXT_FFN=1, EMBED_DIM=6,
    VOCAB_SIZE=262144, POSITION_EMBEDDING_SIZE=8, TEXT_Q_HEADS=1,
    LOCAL_KV_HEADS=1, FULL_KV_HEADS=1, LOCAL_HEAD_DIM=2, FULL_HEAD_DIM=2,
    SLIDING_WINDOW=3, MAX_SEQ_LEN=128,
)
RAGGED = dict(
    MINIMUM, AUDIO_LAYERS=2, AUDIO_HIDDEN=3, AUDIO_FFN=5,
    AUDIO_HEADS=1, AUDIO_HEAD_DIM=3, AUDIO_OUT_DIM=5,
    AUDIO_SUBSAMPLE_C0=3, AUDIO_SUBSAMPLE_C1=2, AUDIO_FREQ_BINS=5,
    AUDIO_CONV_KERNEL=5, TEXT_HIDDEN=3, PLE_DIM=3, TEXT_FFN=5,
    TEXT_LAYERS=7, EMBED_DIM=12, VISION_FFN=5,
)
DEFAULT_LAYERS = dict(MINIMUM, AUDIO_LAYERS=12, VISION_LAYERS=16, TEXT_LAYERS=24)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def nearest(n, d):
    """Exact signed round-to-nearest, ties-to-even division."""
    require(d > 0, "oracle denominator must be positive")
    sign = -1 if n < 0 else 1
    quotient, remainder = divmod(abs(n), d)
    if 2 * remainder > d or (2 * remainder == d and quotient & 1):
        quotient += 1
    return sign * quotient


def saturate(n):
    return max(-(1 << 31), min((1 << 31) - 1, n))


def quantize(x):
    return saturate(round(x * Q))


def real(n):
    return n / Q


def stored(x):
    return real(quantize(x))


def signed(n):
    n &= 0xFFFFFFFF
    return n - (1 << 32) if n & (1 << 31) else n


def word(n):
    return f"32'h{n & 0xffffffff:08x}"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = list(SOURCES)
    for pattern in ("design/*.md", "tests/*.py",
                    "hf_embeddinggemma2_trimodal_spec/*.json",
                    "hf_embeddinggemma2_trimodal_spec/1_Pooling/config.json",
                    "hf_embeddinggemma2_trimodal_spec/official_weights/*",
                    "anvil_e2_reference/rtl/*.sv"):
        paths.extend(ROOT.glob(pattern))
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(paths)) if p.is_file()}


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class Execution:
    def __init__(self, directory, purpose):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=False)
        self.records = []
        self.receipt = dict(
            schema=1, purpose=purpose, acceptance_evidence=False,
            cwd=str(ROOT), argv=[sys.executable, *sys.argv], source_sha256=source_hashes(),
            start_time=stamp(), seeds=[SEED], commands=self.records,
        )
        self.save()

    def save(self):
        (self.directory / "receipt.json").write_text(json.dumps(self.receipt, indent=2) + "\n")

    def tool(self, name, version_args):
        executable = shutil.which(name)
        require(executable is not None, f"required executable unavailable: {name}")
        record = self.run(f"version-{name}", [executable, *version_args])
        output = (self.directory / record["stdout_path"]).read_text(errors="replace")
        errors = (self.directory / record["stderr_path"]).read_text(errors="replace")
        self.receipt.setdefault("tool_versions", {})[name] = dict(
            version=next(line for line in (output+"\n"+errors).splitlines() if line.strip()),
            argv=record["argv"], exit_code=record["exit_code"],
            stdout_path=record["stdout_path"], stderr_path=record["stderr_path"])
        self.save()
        return output

    def run(self, name, argv, timeout=3600, expected_exit=0):
        number = len(self.records)
        prefix = f"{number:03d}-{name}"
        stdout_path = self.directory / f"{prefix}.stdout"
        stderr_path = self.directory / f"{prefix}.stderr"
        record = dict(argv=[str(a) for a in argv], cwd=str(ROOT), start_time=stamp(),
                      timeout_s=timeout, timed_out=False,
                      stdout_path=stdout_path.name, stderr_path=stderr_path.name)
        self.records.append(record)
        self.save()
        start = time.monotonic()
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            try:
                result = subprocess.run(record["argv"], cwd=ROOT, stdout=stdout,
                                        stderr=stderr, timeout=timeout, check=False)
                record["exit_code"] = result.returncode
            except subprocess.TimeoutExpired:
                record["exit_code"] = None
                record["timed_out"] = True
        record["end_time"] = stamp()
        record["duration_s"] = time.monotonic() - start
        self.save()
        require(not record["timed_out"], f"{name}: timeout; retained {stdout_path}")
        if expected_exit is None:
            require(record["exit_code"] != 0, f"{name}: expected explicit rejection")
        else:
            require(record["exit_code"] == expected_exit,
                    f"{name}: exit={record['exit_code']}; "
                    f"stdout={stdout_path.relative_to(ROOT)}, "
                    f"stderr={stderr_path.relative_to(ROOT)}")
        return record

    def finish(self, outcome, detail):
        self.receipt.update(end_time=stamp(), outcome=outcome, detail=detail,
                            exit_code=0 if outcome == "passed" else 1)
        self.save()


def param_text(parameters):
    return ", ".join(f".{name}({value})" for name, value in parameters.items())


def compile_tb(execution, name, text, sources=None):
    if (execution.directory / f"{name}.sv").exists():
        name += f"-{len(execution.records):03d}"
    path = execution.directory / f"{name}.sv"
    path.write_text(text)
    execution.receipt.setdefault("cases", []).append(dict(
        name=name, testbench=str(path.relative_to(ROOT)), sha256=sha(path),
        parameters={key: int(value) for key, value in
                    re.findall(r"\.(\w+)\((-?\d+)\)", text)}, seed=SEED))
    execution.save()
    output = execution.directory / f"{name}.vvp"
    execution.run(f"{name}-compile", [
        "iverilog", "-g2012", "-Wall", "-s", "tb", "-o", output,
        *(sources or getattr(execution, "sources", SOURCES)), path,
    ])
    record = execution.run(f"{name}-simulate", ["vvp", output])
    return (execution.directory / record["stdout_path"]).read_text()


def compare(actual, expected, name, exact=False, normalized=False):
    require(len(actual) == len(expected),
            f"{name}: count actual={len(actual)} expected={len(expected)}")
    require(len(actual) > 0, f"{name}: no comparisons")
    require(all(isinstance(x, int) for x in actual), f"{name}: missing or noninteger observed data")
    if exact:
        require(actual == expected, f"{name}: exact mismatch actual={actual}, expected={expected}")
        return dict(comparisons=len(actual), max_abs_error=0, exact=True)
    a, e = [real(x) for x in actual], [real(x) for x in expected]
    error = max(abs(x - y) for x, y in zip(a, e))
    require(error <= 0.002, f"{name}: max_abs_error={error} > 0.002; actual={a}, expected={e}")
    norm_a, norm_e = sum(x*x for x in a), sum(x*x for x in e)
    cosine = None
    if norm_e:
        require(norm_a > 0, f"{name}: nonzero oracle produced zero RTL vector")
        cosine = sum(x*y for x, y in zip(a, e)) / math.sqrt(norm_a * norm_e)
        require(cosine >= 0.999, f"{name}: cosine={cosine} < 0.999")
    if normalized and norm_e:
        require(abs(norm_a - 1) <= 0.002, f"{name}: squared norm={norm_a}")
    return dict(comparisons=len(a), max_abs_error=error, cosine=cosine,
                squared_norm=norm_a, exact=False)


def rms(values, weights):
    denominator = math.sqrt(sum(x*x for x in values) / len(values) + EPSILON)
    return [stored(x * gamma / denominator) for x, gamma in zip(values, weights)]


def silu(x):
    return x / (1 + math.exp(-x))


def matrix(values, weights, bounds=None, bias=None):
    inputs = values
    if bounds is not None:
        lower, upper, out_lower, out_upper = bounds
        require(lower <= upper and out_lower <= out_upper, "invalid oracle clipping bounds")
        inputs = [max(lower, min(upper, x)) for x in values]
    result = []
    for index, row in enumerate(weights):
        value = math.fsum(x*y for x, y in zip(row, inputs))
        if bias is not None:
            value += bias[index]
        if bounds is not None:
            value = max(out_lower, min(out_upper, value))
        result.append(stored(value))
    return result


def conv2d(values, weights):
    """Time/frequency/channel features, [cout,cin,ky,kx] weights."""
    frames, bins, channels = len(values), len(values[0]), len(values[0][0])
    output = []
    for t in range((frames + 1) // 2):
        frequencies = []
        for f in range((bins + 1) // 2):
            vector = []
            for kernel in weights:
                terms = []
                for c in range(channels):
                    for ky in range(3):
                        for kx in range(3):
                            ti, fi = 2*t + ky - 1, 2*f + kx - 1
                            if 0 <= ti < frames and 0 <= fi < bins:
                                terms.append(values[ti][fi][c] * kernel[c][ky][kx])
                vector.append(stored(math.fsum(terms)))
            frequencies.append(vector)
        output.append(frequencies)
    return output


def depthwise(values, weights):
    kernel = len(weights[0])
    result = []
    for t in range(len(values)):
        result.append([
            stored(math.fsum(values[j][c] * weights[c][k]
                             for k in range(kernel)
                             if 0 <= (j := t + k - kernel//2) < len(values)))
            for c in range(len(weights))
        ])
    return result


def attention(q, k, v, relative, scale, heads, chunk, left, right):
    hidden = len(q[0])
    dim = hidden // heads
    result = []
    for t in range(len(q)):
        first = max(0, (t // chunk)*chunk - left)
        last = min(len(q), (t // chunk)*chunk + chunk + right)
        output = []
        for head in range(heads):
            query = [q[t][head*dim+d] * math.log1p(math.exp(scale[d])) /
                     (math.log(2) * math.sqrt(dim)) for d in range(dim)]
            scores = []
            for j in range(first, last):
                position = [
                    (math.sin if c % 2 == 0 else math.cos)(
                        (t-j) / 10000 ** (2*(c//2)/hidden))
                    for c in range(hidden)
                ]
                rel = [math.fsum(x*y for x, y in zip(row, position)) for row in relative]
                score = math.fsum(query[d] * (k[j][head*dim+d] + rel[head*dim+d])
                                  for d in range(dim))
                scores.append(50 * math.tanh(score / 50))
            maximum = max(scores)
            probabilities = [math.exp(s-maximum) for s in scores]
            denominator = math.fsum(probabilities)
            output.extend(stored(math.fsum(probabilities[j-first]*v[j][head*dim+d]
                                          for j in range(first, last)) / denominator)
                          for d in range(dim))
        result.append(output)
    return result


def flatten(values):
    if isinstance(values, (list, tuple)):
        return [x for item in values for x in flatten(item)]
    return [values]


def audio_shapes(p, layers=None):
    """Inventory-derived public packing; never imports RTL address functions."""
    inventory = json.loads((ROOT / "hf_embeddinggemma2_trimodal_spec/audio_model_tensors.json")
                           .read_text())["tensors"]
    h, f, d, o = (p[k] for k in ("AUDIO_HIDDEN", "AUDIO_FFN", "AUDIO_HEAD_DIM", "AUDIO_OUT_DIM"))
    c0, c1, bins = (p[k] for k in ("AUDIO_SUBSAMPLE_C0", "AUDIO_SUBSAMPLE_C1", "AUDIO_FREQ_BINS"))
    prefix = "audio_tower.subsample_conv_projection."
    shapes = {
        prefix+"layer0.conv.weight": [c0, 1, 3, 3],
        prefix+"layer0.norm.weight": [c0],
        prefix+"layer1.conv.weight": [c1, c0, 3, 3],
        prefix+"layer1.norm.weight": [c1],
        prefix+"input_proj_linear.weight": [h, c1*((bins+3)//4)],
    }
    relative_names = sorted(name.removeprefix("audio_tower.layers.0.")
                            for name in inventory if name.startswith("audio_tower.layers.0."))
    require(len(relative_names) == 62, "audio inventory must have 62 tensors per layer")
    for layer in range(p["AUDIO_LAYERS"] if layers is None else layers):
        for name in relative_names:
            shape = []
            if name.endswith("weight"):
                if "ffw_layer_1" in name:
                    shape = [f, h]
                elif "ffw_layer_2" in name:
                    shape = [h, f]
                elif "depthwise" in name:
                    shape = [h, 1, p["AUDIO_CONV_KERNEL"]]
                elif "linear_start" in name:
                    shape = [2*h, h]
                elif "linear_end" in name or "self_attn." in name:
                    shape = [h, h]
                else:
                    shape = [h]
            elif name.endswith("per_dim_scale"):
                shape = [d]
            shapes[f"audio_tower.layers.{layer}.{name}"] = shape
    shapes["audio_tower.output_proj.weight"] = [o, h]
    shapes["audio_tower.output_proj.bias"] = [o]
    shapes["embed_audio.embedding_projection.weight"] = [p["TEXT_HIDDEN"], o]
    return shapes


def inventory_check():
    config = json.loads((ROOT / "hf_embeddinggemma2_trimodal_spec/config.json").read_text())
    inventory = json.loads((ROOT / "hf_embeddinggemma2_trimodal_spec/audio_model_tensors.json")
                           .read_text())
    p = dict(MINIMUM, AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096,
             AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
             AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
             TEXT_HIDDEN=512)
    shapes = audio_shapes(p)
    require(len(shapes) == inventory["total_audio_tensors"] == 752,
            "audio inventory tensor-count mismatch")
    require(set(shapes) == set(inventory["tensors"]), "audio tensor names mismatch")
    for name, shape in shapes.items():
        require(shape == inventory["tensors"][name]["shape"],
                f"inventory shape mismatch: {name}: {shape}")
    require(config["audio_config"]["num_hidden_layers"] == 12, "audio config layer count")
    defaults = dict(
        AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096, AUDIO_HEADS=8,
        AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
        AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
        AUDIO_CHUNK_SIZE=12, AUDIO_CONTEXT_LEFT=13, AUDIO_CONTEXT_RIGHT=0,
        VISION_LAYERS=16, VISION_HIDDEN=768, VISION_FFN=3072, VISION_HEADS=12,
        VISION_HEAD_DIM=64, PATCH_SIZE=16, POOL_KERNEL=3, VISION_SOFT_TOKENS=280,
        TEXT_LAYERS=24, TEXT_HIDDEN=512, PLE_DIM=512, TEXT_FFN=2048,
        EMBED_DIM=768, VOCAB_SIZE=262144, POSITION_EMBEDDING_SIZE=10240,
        TEXT_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1, LOCAL_HEAD_DIM=256,
        FULL_HEAD_DIM=512, SLIDING_WINDOW=512, MAX_SEQ_LEN=262144)
    header = (ROOT / "rtl/anvil_e3_top.sv").read_text().split(") (", 1)[0]
    for name, value in defaults.items():
        match = re.search(r"\b"+name+r"\s*=\s*(\d+)\b", header)
        require(match is not None and int(match.group(1)) == value,
                f"production default mismatch: {name} must be {value}")
    pooling = json.loads((ROOT / "hf_embeddinggemma2_trimodal_spec/1_Pooling/config.json").read_text())
    require(pooling == dict(embedding_dimension=768, pooling_mode="mean", include_prompt=True),
            "authoritative pooling settings changed")
    modules = json.loads((ROOT / "hf_embeddinggemma2_trimodal_spec/modules.json").read_text())
    require(any(entry["path"] == "2_Normalize" and entry["type"].endswith(".Normalize")
                for entry in modules), "authoritative L2 Normalize module missing")
    return dict(tensors=len(shapes), names_and_shapes_compared=len(shapes), defaults=defaults,
                pooling=pooling)


def memory_tb(instance, inputs, outputs, init, finish, checks="", cycles=100000000,
              first_command_edge=None):
    """Self-checking one-outstanding public command/result memory environment.

    Memory is bounded and explicitly initialized by the caller. Every read must
    be initialized. Output writes are observable data, never hierarchical peeks.
    Payload checks sample pre-edge; #1 checks see settled nonblocking updates.
    """
    return f"""
`timescale 1ns/1ps
module tb;
reg clk=0;
always #5 clk=~clk;
reg rst_n=0, start_valid=0, cmd_ready=0, result_valid=0, result_error=0, done_ready=0;
reg [31:0] result_data=0;
wire start_ready, cmd_valid, cmd_write, result_ready, done_valid;
wire [63:0] cmd_addr;
wire [31:0] cmd_wdata;
wire [3:0] done_error;
{inputs}
{outputs}
{instance}
reg [31:0] memory[0:262143];
reg initialized[0:262143];
integer i, cycle=0, reads=0, writes=0, replies=0, pending=0, delay_count=0;
integer start_cycle=-1,first_command_seen=0;
reg stalled=0;
reg [96:0] held;
task put(input integer address, input [31:0] value);
begin memory[address/4]=value; initialized[address/4]=1; end
endtask
initial begin
  for(i=0;i<262144;i=i+1) begin memory[i]=32'hxxxxxxxx; initialized[i]=0; end
  {init}
  #1;
  if ({{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}}
      !== 105'd0) $fatal(1,"RESET zero leakage t=1");
  #20; rst_n=1;
  @(negedge clk);
  if (start_ready !== 1) $fatal(1,"START not ready after reset");
  start_valid=1;
  @(posedge clk); #1;
  start_cycle=cycle;
  if(start_ready !== 0 || done_valid !== 0 || cmd_valid !== 0)
    $fatal(1,"START staging violation");
  @(negedge clk); start_valid=0;
end
always @(posedge clk) begin
  if (!rst_n) begin
    if ({{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}}
        !== 105'd0) $fatal(1,"RESET active-edge zero leakage");
  end else begin
    cycle=cycle+1;
    if(cycle>{cycles}) $fatal(1,"LIVENESS bounded cycle limit");
    if (stalled && {{cmd_valid,cmd_write,cmd_addr,cmd_wdata}} !== {{1'b1,held}})
      $fatal(1,"PROTOCOL command changed while stalled");
    stalled=cmd_valid && !cmd_ready;
    held={{cmd_write,cmd_addr,cmd_wdata}};
    if (cmd_valid && cmd_ready) begin
      if(pending || result_valid) $fatal(1,"PROTOCOL more than one outstanding");
      if(^cmd_addr === 1'bx || cmd_addr[1:0] !== 0 || cmd_addr>=1048576)
        $fatal(1,"ADDRESS invalid command %h",cmd_addr);
      if(cmd_write === 1) begin
        if(^cmd_wdata === 1'bx) $fatal(1,"DATA unknown write");
        put(cmd_addr,cmd_wdata); writes=writes+1;
        $display("WRITE %h %h",cmd_addr,cmd_wdata);
        result_data <= 32'hdeadbeef;
      end else if(cmd_write === 0) begin
        if(initialized[cmd_addr/4] !== 1)
          $fatal(1,"MEMORY uninitialized read addr=%h",cmd_addr);
        result_data <= memory[cmd_addr/4]; reads=reads+1;
      end else $fatal(1,"PROTOCOL unknown write direction");
      pending=1; delay_count=cycle%3;
    end
    if(result_valid && result_ready) begin
      if(!pending) $fatal(1,"PROTOCOL orphan response");
      pending=0; result_valid<=0; replies=replies+1;
    end
    if(done_valid) begin
      if(done_error !== 0) $fatal(1,"COMPLETION error=%d",done_error);
      if(pending || result_valid) $fatal(1,"COMPLETION outstanding response");
      if(reads==0 || writes==0 || replies!=reads+writes)
        $fatal(1,"COVERAGE missing read/write/response comparisons");
      if({first_command_edge if first_command_edge is not None else -1}>=0 && first_command_seen==0)
        $fatal(1,"COVERAGE first command staging was not compared");
      {finish}
      $display("COUNTS %0d %0d %0d %0d",reads,writes,replies,cycle);
      $finish;
    end
    {checks}
  end
end
always @(posedge clk) begin
 #2;
 if(rst_n && start_cycle>=0 && first_command_seen==0 &&
    {first_command_edge if first_command_edge is not None else -1}>=0) begin
   if(cycle-start_cycle<{first_command_edge if first_command_edge is not None else -1} &&
      cmd_valid !== 0) $fatal(1,"STAGING first command early");
   if(cycle-start_cycle=={first_command_edge if first_command_edge is not None else -1}) begin
     if(cmd_valid !== 1) $fatal(1,"STAGING first command late");
     first_command_seen=1;
   end
 end
end
always @(negedge clk) begin
  if(!rst_n) begin
    if ({{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}}
        !== 105'd0) $fatal(1,"RESET falling-edge zero leakage");
  end else begin
    cmd_ready=(cycle%5!=0 && cycle%7!=0);
    if(pending && !result_valid) begin
      if(delay_count==0) result_valid=1;
      else delay_count=delay_count-1;
    end
  end
end
initial begin #3600000000000; $fatal(1,"SIMULATION 3600s simulated-time watchdog"); end
endmodule
"""


COMMON = """
.clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),
.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.result_valid(result_valid),
.result_ready(result_ready),.result_data(result_data),.result_error(result_error),
.done_valid(done_valid),.done_ready(done_ready),.done_error(done_error)
"""


def put_values(base, values):
    return "\n".join(f"put({base + 4*i},{word(quantize(x))});"
                     for i, x in enumerate(flatten(values)))


def read_writes(text):
    return [(int(line.split()[1], 16), signed(int(line.split()[2], 16)))
            for line in text.splitlines() if line.startswith("WRITE ")]


def observed(text, base, count):
    writes = read_writes(text)
    expected_addresses = [base+4*i for i in range(count)]
    actual = [(a, d) for a, d in writes if base <= a < base+4*count]
    require([a for a, _ in actual] == expected_addresses,
            f"output order/count mismatch at {base}: {actual}")
    return [d for _, d in actual]


def vector_case(execution, name, op, values, rows, cols=1, weights=None,
                aux=None, clipped=False, half=False, bias=False, expected=None, exact=False):
    inputs = [list(map(stored, vector)) for vector in values]
    tokens = len(inputs)
    wb, ib, ab, ob = 0x1000, 0x4000, 0x8000, 0xC000
    init = put_values(ib, inputs)
    if weights is not None:
        init += put_values(wb, weights)
    if aux is not None:
        init += put_values(ab, aux)
    instance = f"""
anvil_e3_audio_vector #(.MAX_WIDTH({max(rows, cols, 1)})) dut(
{COMMON},
.start_op(3'd{op}),.start_tokens(64'd{tokens}),.start_rows(32'd{rows}),
.start_cols(32'd{cols}),.start_weights(64'd{wb}),.start_input(64'd{ib}),
.start_aux(64'd{ab}),.start_output(64'd{ob}),
.start_clipped(1'b{int(clipped)}),.start_half(1'b{int(half)}),.start_bias(1'b{int(bias)})
);
"""
    text = compile_tb(execution, name, memory_tb(instance, "", "", init, "",
                                               first_command_edge=2 if op == 1 else 1))
    output_count = tokens * (rows*cols if op == 5 else rows)
    actual = observed(text, ob, output_count)
    require(expected is not None, f"missing expected values for {name}")
    return compare(actual, [quantize(x) for x in flatten(expected)], name, exact=exact)


def primitive_vectors(execution):
    ledger = {}
    vectors = [[0.25, -0.5, 0.75], [-0.375, 0.625, 0.125]]
    weights = [[0.125, -0.25, 0.5], [-0.75, 0.375, 0.0625]]
    expected = [matrix(x, weights) for x in vectors]
    ledger["matrix"] = vector_case(execution, "vector-matrix", 0, vectors, 2, 3,
                                   weights, expected=expected, exact=True)
    bounds = [-0.25, 0.5, -0.125, 0.25]
    packed = [bounds[1], bounds[0], *flatten(weights), bounds[3], bounds[2]]
    ledger["clipped"] = vector_case(
        execution, "vector-clipped", 0, vectors, 2, 3, packed, clipped=True,
        expected=[matrix(x, weights, bounds) for x in vectors], exact=True)
    # Dot would saturate before cancellation if bias were applied too late.
    ledger["bias-cancellation"] = vector_case(
        execution, "vector-bias", 0, [[127.0, 127.0]], 1, 2, [[1, 1]],
        aux=[-127], bias=True, expected=[[127]], exact=True)
    gamma = [0.75, -1.25, 0.5]
    ledger["direct-gamma"] = vector_case(
        execution, "vector-norm", 1, vectors, 3, weights=gamma,
        expected=[rms(x, gamma) for x in vectors])
    tiny = [[real(1), real(-2), real(3)], [0.0, 0.0, 0.0]]
    ledger["epsilon-zero"] = vector_case(
        execution, "vector-epsilon-zero", 1, tiny, 3, weights=gamma,
        expected=[rms(x, gamma) for x in tiny])
    ledger["silu"] = vector_case(
        execution, "vector-silu", 2, vectors, 3,
        expected=[[stored(silu(x)) for x in v] for v in vectors])
    aux = [[0.5, -0.25, 1.25], [-0.75, 0.375, -0.125]]
    ledger["half-residual"] = vector_case(
        execution, "vector-half", 3, vectors, 3, aux=aux, half=True,
        expected=[[stored(x+0.5*y) for x, y in zip(v, a)] for v, a in zip(vectors, aux)],
        exact=True)
    extrema = [[real((1 << 31)-1), -128.0, real(3), real(-3)]]
    extra = [[1.0, -1.0, real(1), real(-1)]]
    ledger["saturation-rounding"] = vector_case(
        execution, "vector-saturation", 3, extrema, 4, aux=extra, half=True,
        expected=[[real((1 << 31)-1), -128.0, real(4), real(-4)]], exact=True)
    half_values = [[real(x) for x in (0, 1, 2, 3, -1, -2, -3, -4)]]
    half_aux = [[real(x) for x in (1, 1, 1, 1, -1, -1, -1, -1)]]
    ledger["half-even-ties"] = vector_case(
        execution, "vector-half-even", 3, half_values, 8, aux=half_aux, half=True,
        expected=[[real(nearest(2*quantize(x)+quantize(y), 2))
                   for x, y in zip(half_values[0], half_aux[0])]], exact=True)
    glu_values = [v+a for v, a in zip(vectors, aux)]
    ledger["glu"] = vector_case(
        execution, "vector-glu", 4, glu_values, 3,
        expected=[[stored(x/(1+math.exp(-gate))) for x, gate in zip(v, a)]
                  for v, a in zip(vectors, aux)])
    ledger["reorder"] = vector_case(
        execution, "vector-reorder", 5, [[1, 2, 3, 4, 5, 6]], 2, 3,
        expected=[[1, 3, 5, 2, 4, 6]], exact=True)
    return ledger


def convolution_cases(execution):
    rng = random.Random(SEED)
    ledger = {}
    for frames, bins, cin, cout in ((1, 1, 1, 1), (2, 3, 2, 3), (3, 5, 3, 2),
                                    (4, 3, 1, 2), (5, 5, 2, 3)):
        values = [[[stored(rng.uniform(-0.8, 0.8)) for _ in range(cin)]
                   for _ in range(bins)] for _ in range(frames)]
        weights = [[[[stored(rng.uniform(-0.5, 0.5)) for _ in range(3)]
                     for _ in range(3)] for _ in range(cin)] for _ in range(cout)]
        name = f"conv-{frames}-{bins}-{cin}-{cout}"
        instance = f"""
anvil_e3_audio_conv #(.INPUT_CHANNELS({cin}),.OUTPUT_CHANNELS({cout}),
 .FREQ_BINS({bins})) dut({COMMON},.start_frames(32'd{frames}),
 .start_weights(64'h1000),.start_input(64'h4000),.start_output(64'hc000));
"""
        text = compile_tb(execution, name, memory_tb(
            instance, "", "", put_values(0x1000, weights)+put_values(0x4000, values), "",
            first_command_edge=10))
        expected = [quantize(x) for x in flatten(conv2d(values, weights))]
        ledger[name] = compare(observed(text, 0xC000, len(expected)), expected, name, exact=True)
    for frames, channels, kernel in ((1, 1, 1), (2, 3, 5), (3, 2, 5), (5, 3, 3)):
        values = [[stored(rng.uniform(-0.8, 0.8)) for _ in range(channels)]
                  for _ in range(frames)]
        weights = [[stored(rng.uniform(-0.5, 0.5)) for _ in range(kernel)]
                   for _ in range(channels)]
        name = f"depthwise-{frames}-{channels}-{kernel}"
        instance = f"""
anvil_e3_audio_conv #(.INPUT_CHANNELS({channels}),.OUTPUT_CHANNELS({channels}),
 .FREQ_BINS(1),.KERNEL({kernel}),.STRIDE(1),.DEPTHWISE(1)) dut({COMMON},
 .start_frames(32'd{frames}),.start_weights(64'h1000),.start_input(64'h4000),
 .start_output(64'hc000));
"""
        text = compile_tb(execution, name, memory_tb(
            instance, "", "", put_values(0x1000, weights)+put_values(0x4000, values), "",
            first_command_edge=2+2*(kernel//2)))
        expected = [quantize(x) for x in flatten(depthwise(values, weights))]
        ledger[name] = compare(observed(text, 0xC000, len(expected)), expected, name, exact=True)
    return ledger


def attention_cases(execution):
    rng = random.Random(SEED+1)
    ledger = {}
    for tokens, hidden, heads, chunk, left, right in (
            (1, 1, 1, 12, 13, 0), (3, 3, 1, 2, 1, 0),
            (5, 4, 2, 2, 1, 1), (2, 2, 1, 12, 13, 0),
            (11, 1, 1, 12, 13, 0),
            (12, 1, 1, 12, 13, 0), (13, 1, 1, 12, 13, 0),
            (27, 1, 1, 12, 13, 0)):
        q, k, v = ([[stored(rng.uniform(-0.9, 0.9)) for _ in range(hidden)]
                    for _ in range(tokens)] for _ in range(3))
        relative = [[stored(rng.uniform(-0.6, 0.6)) for _ in range(hidden)]
                    for _ in range(hidden)]
        scale = [stored(rng.uniform(-0.8, 0.8)) for _ in range(hidden // heads)]
        if tokens == 2 and hidden == 2:
            q, k, v = [[10, 0], [-10, 0]], [[10, 0], [stored(9.9), 0]], [[-1, 0.5], [1, -0.75]]
            relative, scale = [[0.0, 0.0], [0.0, 0.0]], [0.0, 0.0]
        name = f"attention-{tokens}-{hidden}-{heads}-{chunk}-{left}-{right}"
        instance = f"""
anvil_e3_audio_attention #(.AUDIO_HIDDEN({hidden}),.AUDIO_HEADS({heads}),
 .AUDIO_HEAD_DIM({hidden//heads}),.AUDIO_CHUNK_SIZE({chunk}),
 .AUDIO_CONTEXT_LEFT({left}),.AUDIO_CONTEXT_RIGHT({right})) dut(
 {COMMON},.tokens(32'd{tokens}),.q_base(64'h1000),.k_base(64'h2000),
 .v_base(64'h3000),.relative_weights(64'h4000),.scale_weights(64'h5000),
 .output_base(64'hc000));
"""
        init = (put_values(0x1000, q)+put_values(0x2000, k)+put_values(0x3000, v)+
                put_values(0x4000, relative)+put_values(0x5000, scale))
        text = compile_tb(execution, name, memory_tb(instance, "", "", init, "", first_command_edge=1))
        expected = [quantize(x) for x in flatten(
            attention(q, k, v, relative, scale, heads, chunk, left, right))]
        ledger[name] = compare(observed(text, 0xC000, len(expected)), expected, name)
    return ledger


def reshape(values, shape):
    if not shape:
        require(len(values) == 1, "scalar oracle shape")
        return values[0]
    if len(shape) == 1:
        require(len(values) == shape[0], "vector oracle shape")
        return list(values)
    stride = math.prod(shape[1:])
    require(len(values) == shape[0]*stride, "matrix oracle shape")
    return [reshape(values[i*stride:(i+1)*stride], shape[1:]) for i in range(shape[0])]


def synthetic_audio(p, seed):
    rng = random.Random(seed)
    tensors = {}
    addresses = {}
    offset = 0
    for name, shape in audio_shapes(p).items():
        size = math.prod(shape)
        if name.endswith("_max"):
            values = [0.65 if "input_max" in name else 0.55]
        elif name.endswith("_min"):
            values = [-0.6 if "input_min" in name else -0.5]
        elif len(shape) == 1 and "norm" in name:
            values = [rng.uniform(0.6, 1.2) for _ in range(size)]
        else:
            values = [rng.uniform(-0.45, 0.45) for _ in range(size)]
        tensors[name] = reshape(list(map(stored, values)), shape)
        addresses[name] = offset
        offset += size
    return tensors, addresses


def audio_memory(tensors, offsets, base):
    return "".join(put_values(base+4*offsets[name], flatten(value))
                   for name, value in tensors.items())


def oracle_subsample(values, tensors):
    prefix = "audio_tower.subsample_conv_projection."
    activations = values
    for layer in (0, 1):
        activations = conv2d(activations, tensors[prefix+f"layer{layer}.conv.weight"])
        gamma = tensors[prefix+f"layer{layer}.norm.weight"]
        activations = [[[stored(silu(x)) for x in rms(vector, gamma)] for vector in row]
                       for row in activations]
    inputs = [[row[f][c] for c in range(len(row[0])) for f in range(len(row))]
              for row in activations]
    return [matrix(x, tensors[prefix+"input_proj_linear.weight"]) for x in inputs]


def oracle_conformer(values, tensors, p, layer):
    prefix = f"audio_tower.layers.{layer}."

    def norm(xs, name):
        return [rms(x, tensors[prefix+name+".weight"]) for x in xs]

    def linear(xs, name):
        bound = [tensors[prefix+name+"."+key]
                 for key in ("input_min", "input_max", "output_min", "output_max")]
        return [matrix(x, tensors[prefix+name+".linear.weight"], bound) for x in xs]

    def feed_forward(xs, name):
        result = norm(xs, name+".pre_layer_norm")
        result = linear(result, name+".ffw_layer_1")
        result = [[stored(silu(x)) for x in vector] for vector in result]
        result = linear(result, name+".ffw_layer_2")
        return norm(result, name+".post_layer_norm")

    def residual(xs, ys, factor=1):
        return [[stored(x+factor*y) for x, y in zip(a, b)] for a, b in zip(xs, ys)]

    values = residual(values, feed_forward(values, "feed_forward1"), 0.5)
    normalized = norm(values, "norm_pre_attn")
    q, k, v = [linear(normalized, "self_attn."+name) for name in ("q_proj", "k_proj", "v_proj")]
    attended = attention(
        q, k, v, tensors[prefix+"self_attn.relative_k_proj.weight"],
        tensors[prefix+"self_attn.per_dim_scale"], p["AUDIO_HEADS"],
        p.get("AUDIO_CHUNK_SIZE", 12), p.get("AUDIO_CONTEXT_LEFT", 13),
        p.get("AUDIO_CONTEXT_RIGHT", 0))
    values = residual(values, norm(linear(attended, "self_attn.post"), "norm_post_attn"))
    convolved = linear(norm(values, "lconv1d.pre_layer_norm"), "lconv1d.linear_start")
    h = p["AUDIO_HIDDEN"]
    convolved = [[stored(x/(1+math.exp(-gate))) for x, gate in zip(xs[:h], xs[h:])]
                 for xs in convolved]
    kernels = [channel[0] for channel in tensors[prefix+"lconv1d.depthwise_conv1d.weight"]]
    convolved = norm(depthwise(convolved, kernels), "lconv1d.conv_norm")
    convolved = [[stored(silu(x)) for x in vector] for vector in convolved]
    values = residual(values, linear(convolved, "lconv1d.linear_end"))
    values = residual(values, feed_forward(values, "feed_forward2"), 0.5)
    return norm(values, "norm_out")


def subsystem_cases(execution):
    ledger = {}
    rng = random.Random(SEED+3)
    for name, p, frames in (("minimum", MINIMUM, 1), ("ragged", RAGGED, 5),
                             ("ragged-one", RAGGED, 1), ("ragged-two", RAGGED, 2),
                             ("ragged-three", RAGGED, 3), ("ragged-four", RAGGED, 4)):
        tensors, offsets = synthetic_audio(p, SEED+4)
        values = [[[stored(rng.uniform(-0.7, 0.7))]
                   for _ in range(p["AUDIO_FREQ_BINS"])] for _ in range(frames)]
        parameters = {key: p[key] for key in ("AUDIO_HIDDEN", "AUDIO_SUBSAMPLE_C0",
                                              "AUDIO_SUBSAMPLE_C1", "AUDIO_FREQ_BINS")}
        instance = f"""
anvil_e3_audio_subsample #({param_text(parameters)}) dut(
 {COMMON},.frames(32'd{frames}),.weights(64'h1000),.input_base(64'h10000),
 .work_base(64'h20000),.output_base(64'h40000));
"""
        init = audio_memory(tensors, offsets, 0x1000)+put_values(0x10000, values)
        text = compile_tb(execution, "subsample-"+name, memory_tb(
            instance, "", "", init, "", first_command_edge=12))
        expected = [quantize(x) for x in flatten(oracle_subsample(values, tensors))]
        ledger["subsample-"+name] = compare(
            observed(text, 0x40000, len(expected)), expected, "subsample-"+name)
    for name, p, tokens in (("minimum", MINIMUM, 1), ("ragged", RAGGED, 3),
                            ("default-layer-counts", DEFAULT_LAYERS, 1)):
        tensors, offsets = synthetic_audio(p, SEED+5)
        parameters = {k: v for k, v in p.items() if k.startswith("AUDIO_") or k == "TEXT_HIDDEN"}
        for layer in range(p["AUDIO_LAYERS"]):
            values = [[stored(rng.uniform(-0.8, 0.8)) for _ in range(p["AUDIO_HIDDEN"])]
                      for _ in range(tokens)]
            instance = f"""
anvil_e3_audio_conformer_layer #({param_text(parameters)}) dut(
 {COMMON},.tokens(32'd{tokens}),.layer_index(32'd{layer}),.weights(64'h1000),
 .x0_base(64'h10000),.x1_base(64'h14000),.work0_base(64'h20000),.work1_base(64'h24000),
 .q_base(64'h30000),.k_base(64'h34000),.v_base(64'h38000),
 .attention_base(64'h3c000),.start_current_x(1'b0));
"""
            init = audio_memory(tensors, offsets, 0x1000)+put_values(0x10000, values)
            case = f"conformer-{name}-{layer}"
            text = compile_tb(execution, case, memory_tb(instance, "", "", init, "", first_command_edge=4))
            expected = [quantize(x) for x in flatten(
                oracle_conformer(values, tensors, p, layer))]
            final = {}
            for address, data in read_writes(text):
                final[address] = data
            actual = [final.get(0x14000+4*i) for i in range(len(expected))]
            require(None not in actual, f"{case}: missing final writes")
            ledger[case] = compare(actual, expected, case)
    return ledger


def text_shapes(p):
    h, f, ple = (p[k] for k in ("TEXT_HIDDEN", "TEXT_FFN", "PLE_DIM"))
    shapes = {
        "embed_tokens.weight": [p["VOCAB_SIZE"], h],
        "embedding_projection.weight": [p["EMBED_DIM"], h],
        "norm.weight": [h],
        "ple.per_layer_model_projection.weight": [p["TEXT_LAYERS"]*ple, h],
        "ple.per_layer_projection_norm.weight": [ple],
    }
    for layer in range(p["TEXT_LAYERS"]):
        full = layer % 6 == 5
        dim = p["FULL_HEAD_DIM" if full else "LOCAL_HEAD_DIM"]
        kv = p["FULL_KV_HEADS" if full else "LOCAL_KV_HEADS"]
        q = p["TEXT_Q_HEADS"]
        tensors = {
            "input_layernorm.weight": [h], "layer_scalar": [1],
            "mlp.down_proj.weight": [h, f], "mlp.gate_proj.weight": [f, h],
            "mlp.up_proj.weight": [f, h],
            "ple_block.per_layer_input_gate.weight": [ple, h],
            "ple_block.per_layer_projection.weight": [h, ple],
            "ple_block.post_per_layer_input_norm.weight": [h],
            "post_attention_layernorm.weight": [h],
            "post_feedforward_layernorm.weight": [h],
            "pre_feedforward_layernorm.weight": [h],
            "self_attn.k_norm.weight": [dim], "self_attn.k_proj.weight": [kv*dim, h],
            "self_attn.o_proj.weight": [h, q*dim],
            "self_attn.q_norm.weight": [dim], "self_attn.q_proj.weight": [q*dim, h],
            "self_attn.v_proj.weight": [kv*dim, h],
        }
        shapes.update({f"layers.{layer}.{name}": shape for name, shape in tensors.items()})
    return shapes


def vision_shapes(p):
    h, f, d = (p[k] for k in ("VISION_HIDDEN", "VISION_FFN", "VISION_HEAD_DIM"))
    shapes = {
        "patch": [h, 3*p["PATCH_SIZE"]**2],
        "row": [p["POSITION_EMBEDDING_SIZE"], h],
        "col": [p["POSITION_EMBEDDING_SIZE"], h],
    }
    for layer in range(p["VISION_LAYERS"]):
        tensors = {
            "input_layernorm.weight": [h],
            "self_attn.q_proj.weight": [h, h], "self_attn.k_proj.weight": [h, h],
            "self_attn.v_proj.weight": [h, h], "self_attn.o_proj.weight": [h, h],
            "self_attn.q_norm.weight": [d], "self_attn.k_norm.weight": [d],
            "post_attention_layernorm.weight": [h], "pre_feedforward_layernorm.weight": [h],
            "mlp.gate_proj.weight": [f, h], "mlp.up_proj.weight": [f, h],
            "mlp.down_proj.weight": [h, f], "post_feedforward_layernorm.weight": [h],
        }
        shapes.update({f"layers.{layer}.{name}": shape for name, shape in tensors.items()})
    shapes["bridge"] = [p["TEXT_HIDDEN"], h]
    return shapes


def random_tensors(shapes, seed):
    rng = random.Random(seed)
    tensors, offsets = {}, {}
    offset = 0
    for name, shape in shapes.items():
        offsets[name] = offset
        offset += math.prod(shape)
        if name == "embed_tokens.weight":
            tensors[name] = {
                token: [stored(rng.uniform(-0.7, 0.7)) for _ in range(shape[1])]
                for token in (7, 11, 13, 255999, 256000, 258880, 258881, 258882, 258883)
            }
            continue
        if "norm" in name:
            values = [stored(rng.uniform(-0.2, 0.2)) for _ in range(math.prod(shape))]
        elif name.endswith("layer_scalar"):
            values = [stored(rng.uniform(0.8, 1.1))]
        else:
            values = [stored(rng.uniform(-0.4, 0.4)) for _ in range(math.prod(shape))]
        tensors[name] = reshape(values, shape)
    return tensors, offsets


def float_matrix(values, weights):
    return [max(-128, min(real((1 << 31)-1), math.fsum(x*y for x, y in zip(row, values))))
            for row in weights]


def retained_norm(values, weights):
    denominator = math.sqrt(math.fsum(x*x for x in values)/len(values) + EPSILON)
    return [max(-128, min(real((1 << 31)-1), x*(1+gamma)/denominator))
            for x, gamma in zip(values, weights)]


def gelu(x):
    return 0.5*x*(1+math.tanh(math.sqrt(2/math.pi)*(x+0.044715*x**3)))


def rotary(values, position, theta):
    dim = len(values)
    output = list(values)
    for pair in range(dim//2):
        angle = position / theta ** (2*pair/dim)
        lo, hi = values[pair], values[pair+dim//2]
        output[pair] = lo*math.cos(angle)-hi*math.sin(angle)
        output[pair+dim//2] = lo*math.sin(angle)+hi*math.cos(angle)
    return output


def retained_layer(values, ple_values, positions, masks, tensors, p, layer, vision=False, cols=1):
    prefix = f"layers.{layer}."
    h = p["VISION_HIDDEN" if vision else "TEXT_HIDDEN"]
    heads = p["VISION_HEADS" if vision else "TEXT_Q_HEADS"]
    full = vision or layer % 6 == 5
    dim = p["VISION_HEAD_DIM"] if vision else p["FULL_HEAD_DIM" if full else "LOCAL_HEAD_DIM"]
    kv = heads if vision else p["FULL_KV_HEADS" if full else "LOCAL_KV_HEADS"]
    q_values, k_values, v_values = [], [], []
    for token, vector in enumerate(values):
        normalized = retained_norm(vector, tensors[prefix+"input_layernorm.weight"])
        q = float_matrix(normalized, tensors[prefix+"self_attn.q_proj.weight"])
        k = float_matrix(normalized, tensors[prefix+"self_attn.k_proj.weight"])
        v = float_matrix(normalized, tensors[prefix+"self_attn.v_proj.weight"])
        projected = []
        for projection, count, name in ((q, heads, "q"), (k, kv, "k")):
            rotated = []
            for head in range(count):
                head_values = retained_norm(
                    projection[head*dim:(head+1)*dim],
                    tensors[prefix+f"self_attn.{name}_norm.weight"])
                if vision:
                    head_values = (
                        rotary(head_values[:dim//2], token//cols, 100)+
                        rotary(head_values[dim//2:], token%cols, 100))
                else:
                    head_values = rotary(head_values, positions[token], 1000000 if full else 10000)
                rotated.extend(map(stored, head_values))
            projected.append(rotated)
        q_values.append(projected[0]); k_values.append(projected[1])
        v_values.append(list(map(stored, v)))
    output = []
    for token, vector in enumerate(values):
        attended = []
        keys = [j for j in range(len(values))
                if vision or (masks[j] and (full or
                    abs(positions[token]-positions[j]) < p["SLIDING_WINDOW"]))]
        for head in range(heads):
            grouped = head // (heads // kv)
            if not keys:
                attended.extend([0.0]*dim)
                continue
            scores = [
                math.fsum(q_values[token][head*dim+d] * k_values[j][grouped*dim+d]
                          for d in range(dim)) / math.sqrt(dim) for j in keys]
            maximum = max(scores)
            probs = [math.exp(score-maximum) if score-maximum >= -16 else 0 for score in scores]
            total = math.fsum(probs)
            attended.extend(
                math.fsum(prob*v_values[j][grouped*dim+d] for prob, j in zip(probs, keys))/total
                for d in range(dim))
        attention_output = float_matrix(attended, tensors[prefix+"self_attn.o_proj.weight"])
        attention_output = retained_norm(attention_output, tensors[prefix+"post_attention_layernorm.weight"])
        residual = [x+y for x, y in zip(vector, attention_output)]
        normalized = retained_norm(residual, tensors[prefix+"pre_feedforward_layernorm.weight"])
        gate = [gelu(x) for x in float_matrix(normalized, tensors[prefix+"mlp.gate_proj.weight"])]
        up = float_matrix(normalized, tensors[prefix+"mlp.up_proj.weight"])
        down = float_matrix([x*y for x, y in zip(gate, up)], tensors[prefix+"mlp.down_proj.weight"])
        down = retained_norm(down, tensors[prefix+"post_feedforward_layernorm.weight"])
        residual = [x+y for x, y in zip(residual, down)]
        if not vision:
            gate = [gelu(x) for x in float_matrix(
                residual, tensors[prefix+"ple_block.per_layer_input_gate.weight"])]
            injection = float_matrix([x*y for x, y in zip(gate, ple_values[token][layer])],
                                     tensors[prefix+"ple_block.per_layer_projection.weight"])
            injection = retained_norm(injection, tensors[prefix+"ple_block.post_per_layer_input_norm.weight"])
            scalar = tensors[prefix+"layer_scalar"][0]
            residual = [(x+y)*scalar for x, y in zip(residual, injection)]
        require(len(residual) == h, "retained oracle hidden width")
        output.append(list(map(stored, residual)))
    return output


def oracle_vision(image, tensors, p, rows=1, cols=1):
    patch = p["PATCH_SIZE"]
    values = []
    for row in range(rows):
        for col in range(cols):
            pixels = [image[c][row*patch+dy][col*patch+dx]
                      for c in range(3) for dy in range(patch) for dx in range(patch)]
            embedded = float_matrix(pixels, tensors["patch"])
            values.append([stored(x+r+c) for x, r, c in
                           zip(embedded, tensors["row"][row], tensors["col"][col])])
    for layer in range(p["VISION_LAYERS"]):
        values = retained_layer(values, None, None, None, tensors, p, layer, True, cols)
    output = []
    kernel = p["POOL_KERNEL"]
    for row in range(0, rows, kernel):
        for col in range(0, cols, kernel):
            members = [values[r*cols+c] for r in range(row, min(rows, row+kernel))
                       for c in range(col, min(cols, col+kernel))]
            mean = [math.fsum(v[d] for v in members)/len(members) for d in range(p["VISION_HIDDEN"])]
            output.append(list(map(stored, float_matrix(mean, tensors["bridge"]))))
    return output


def oracle_backbone(vectors, positions, masks, tensors, p, output_dim):
    ple = []
    width = p["PLE_DIM"]
    for vector in vectors:
        projected = float_matrix(vector, tensors["ple.per_layer_model_projection.weight"])
        projected = [x/math.sqrt(p["TEXT_HIDDEN"]) for x in projected]
        ple.append([list(map(stored, retained_norm(
            projected[layer*width:(layer+1)*width],
            tensors["ple.per_layer_projection_norm.weight"])))
                    for layer in range(p["TEXT_LAYERS"])])
    values = vectors
    for layer in range(p["TEXT_LAYERS"]):
        values = retained_layer(values, ple, positions, masks, tensors, p, layer)
    projected = [
        float_matrix(retained_norm(vector, tensors["norm.weight"]),
                     tensors["embedding_projection.weight"]) for vector in values]
    count = sum(masks)
    require(count > 0, "all-masked backbone oracle")
    pooled = [math.fsum(vector[d]*mask for vector, mask in zip(projected, masks))/count
              for d in range(output_dim)]
    norm = math.sqrt(math.fsum(x*x for x in pooled))
    return [quantize(x/norm) if norm else 0 for x in pooled]


BASES = dict(weights_base=0x1000000, vision_weights_base=0x2000000,
             audio_weights_base=0x3000000, image_base=0x4000000, audio_base=0x5000000,
             tokens_base=0x6000000, positions_base=0x6001000, mask_base=0x6002000,
             scratch_base=0x8000000)


def tensor_image(tensors, offsets, base, hidden=None):
    result = {}
    for name, tensor in tensors.items():
        address = base+offsets[name]*4
        if isinstance(tensor, dict):
            require(hidden is not None, "sparse embeddings need hidden width")
            for token, vector in tensor.items():
                for i, value in enumerate(vector):
                    result[address+4*(token*hidden+i)] = quantize(value)
        else:
            result.update({address+4*i: quantize(value)
                           for i, value in enumerate(flatten(tensor))})
    return result


def integrated_fixture(p, mode, frames=5, output_dim=None, seed=SEED+11, zero=False,
                       rows=1, cols=1):
    rng = random.Random(seed)
    output_dim = output_dim or p["EMBED_DIM"]
    text, text_offsets = random_tensors(text_shapes(p), seed+1)
    if zero:
        text["embedding_projection.weight"] = [
            [0.0]*p["TEXT_HIDDEN"] for _ in range(p["EMBED_DIM"])]
    vision, vision_offsets = random_tensors(vision_shapes(p), seed+2)
    audio, audio_offsets = synthetic_audio(p, seed+3)
    image = [[[stored(rng.uniform(-0.7, 0.7)) for _ in range(cols*p["PATCH_SIZE"])]
              for _ in range(rows*p["PATCH_SIZE"])] for _ in range(3)]
    features = [[[stored(rng.uniform(-0.7, 0.7))]
                 for _ in range(p["AUDIO_FREQ_BINS"])] for _ in range(frames)]
    has_audio, has_vision, has_text = mode in (3, 4, 5, 6), mode in (1, 2, 5, 6), mode in (0, 2, 4, 6)
    ids, positions, masks, vectors = [], [], [], []

    def append_token(token, vector=None):
        ids.append(token); positions.append(len(positions)); masks.append(1)
        vectors.append(vector if vector is not None else
                       [stored(x*math.sqrt(p["TEXT_HIDDEN"])) for x in text["embed_tokens.weight"][token]])

    if has_audio:
        outputs = oracle_subsample(features, audio)
        for layer in range(p["AUDIO_LAYERS"]):
            outputs = oracle_conformer(outputs, audio, p, layer)
        outputs = [matrix(vector, audio["audio_tower.output_proj.weight"],
                          bias=audio["audio_tower.output_proj.bias"]) for vector in outputs]
        outputs = [matrix(vector, audio["embed_audio.embedding_projection.weight"]) for vector in outputs]
        append_token(256000)
        for vector in outputs:
            append_token(258881, vector)
        append_token(258883)
    if has_vision:
        append_token(255999)
        for vector in oracle_vision(image, vision, p, rows, cols):
            append_token(258880, vector)
        append_token(258882)
    frame_count = len(ids)
    text_ids, text_positions, text_masks = [7, 11, 13], [0, 5, 7], [1, 0, 1]
    if has_text:
        for token, position, mask in zip(text_ids, text_positions, text_masks):
            append_token(token)
            positions[-1] = position+frame_count
            masks[-1] = mask
    expected = oracle_backbone(vectors, positions, masks, text, p, output_dim)
    memory = tensor_image(text, text_offsets, BASES["weights_base"], p["TEXT_HIDDEN"])
    if has_audio:
        memory.update(tensor_image(audio, audio_offsets, BASES["audio_weights_base"]))
        memory.update({BASES["audio_base"]+4*i: quantize(value)
                       for i, value in enumerate(flatten(features))})
    if has_vision:
        memory.update(tensor_image(vision, vision_offsets, BASES["vision_weights_base"]))
        memory.update({BASES["image_base"]+4*i: quantize(value)
                       for i, value in enumerate(flatten(image))})
    if has_text:
        for key, values in (("tokens_base", text_ids), ("positions_base", text_positions),
                            ("mask_base", text_masks)):
            memory.update({BASES[key]+4*i: value for i, value in enumerate(values)})
    return dict(memory=memory, expected=expected, ids=ids, positions=positions, masks=masks,
                vectors=vectors, tokens=3 if has_text else 0, frames=frames,
                mode=mode, output_dim=output_dim, frame_count=frame_count, parameters=p,
                rows=rows, cols=cols)


def integrated_tb(fixture):
    p = fixture["parameters"]
    pins = "\n".join(f"reg [63:0] {name}=64'd{base};" for name, base in BASES.items())
    connections = ",".join(f".{name}({name})" for name in BASES)
    image_cases = "\n".join(f"64'h{address:x}: memory_read={word(value)};"
                             for address, value in sorted(fixture["memory"].items()))
    expected = fixture["expected"]
    expected_init = "\n".join(f"expected[{i}]={word(value)};" for i, value in enumerate(expected))
    dim = len(expected)
    error = fixture.get("error", 0)
    reset_kind = fixture.get("reset", "")
    overrides = fixture.get("descriptor", {})
    descriptor_init = "\n".join(f"{name}={value};" for name, value in overrides.items())
    inject = fixture.get("inject", "1'b0")
    early = int(fixture.get("early", False))
    backtoback = int(fixture.get("backtoback", False))
    capture_reset = "reset_abort;" if reset_kind == "capture" else ""
    reset_condition = {
        "read": "pending && !last_write",
        "write": "pending && last_write",
        "embedding": "emb_valid && !emb_ready",
        "completion": "done_valid && !done_ready",
    }.get(reset_kind, "1'b0")
    if error:
        output_check = '$fatal(1,"ERROR embedding emitted after unsuccessful job");'
        complete_check = f"""
     if(done_error !== 4'd{error}) $fatal(1,"COMPLETION expected error {error} got=%0d",done_error);
     if(beats!=0 || pending || mem_rsp_valid) $fatal(1,"ERROR completion leaked work");
     if({error}==1 || {error}==5)
       if(reads!=0 || writes!=0) $fatal(1,"ERROR descriptor accessed memory");
     done_stalls=done_stalls+1;
     if(done_ready) begin
       if(done_stalls<3) $fatal(1,"COVERAGE completion stall missing");
       $display("ERROR_OBSERVED {error} %0d %0d %0d",reads,writes,replies);
       $finish;
     end
"""
    else:
        output_check = f"""
     if(beats>={dim} || emb_index !== beats || emb_last !== (beats=={dim-1}))
       $fatal(1,"EMBEDDING beat count/index/last");
     if(^emb_data === 1'bx) $fatal(1,"EMBEDDING unknown data");
     $display("EMBED %0d %h %h",beats,emb_data,expected[beats]);
     if($itor($signed(emb_data))-$itor(expected[beats])>33554.432 ||
        $itor(expected[beats])-$itor($signed(emb_data))>33554.432)
       $fatal(1,"NUMERICAL component mismatch index=%0d got=%h expected=%h",
              beats,emb_data,expected[beats]);
     beats=beats+1;
"""
        complete_check = f"""
     if(done_error !== 0) $fatal(1,"COMPLETION expected success got=%0d",done_error);
     if(beats!={dim} || pending || mem_rsp_valid) $fatal(1,"COMPLETION premature");
     done_stalls=done_stalls+1;
     if(done_ready) begin
       if(reads==0 || writes==0 || replies!=reads+writes || req_stalls==0 ||
          emb_stalls==0 || done_stalls<3) $fatal(1,"COVERAGE missing required transfer/stall");
       $display("COUNTS %0d %0d %0d %0d %0d %0d %0d",
                reads,writes,replies,beats,req_stalls,emb_stalls,done_stalls);
       #1;
       if(job_ready !== 1 || busy !== 0 || done_valid !== 0)
         $fatal(1,"PROTOCOL completion retirement");
       if({backtoback}) begin
         @(posedge clk);#1;
         if(job_ready !== 0 || busy !== 1 || done_valid !== 0 || mem_req_valid !== 0)
           $fatal(1,"PROTOCOL next job did not capture exactly at D+1");
         @(posedge clk);#1;
         if(done_valid !== 1 || done_error !== 1 || mem_req_valid !== 0)
           $fatal(1,"PROTOCOL next descriptor validation at D+2");
         $display("BACK_TO_BACK_OBSERVED");
       end
       if({early} && early_count==0) $fatal(1,"COVERAGE early response absent");
       $finish;
     end
"""
    return f"""
`timescale 1ns/1ps
module tb;
reg clk=0;
always #5 clk=~clk;
reg rst_n=0,job_valid=0,mem_req_ready=0,mem_rsp_valid=0,mem_rsp_error=0,emb_ready=0,done_ready=0;
reg [31:0] mem_rsp_rdata=0;
reg [2:0] job_mode=3'd{fixture["mode"]};
reg [31:0] job_tokens=32'd{fixture["tokens"]}, job_patch_rows={fixture.get("rows", 1)},
 job_patch_cols={fixture.get("cols", 1)};
reg [31:0] job_audio_frames=32'd{fixture["frames"]};
reg [15:0] job_output_dim=16'd{dim};
{pins}
wire job_ready,mem_req_valid,mem_req_write,mem_rsp_ready,emb_valid,emb_last,done_valid,busy;
wire [63:0] mem_req_addr;
wire [31:0] mem_req_wdata;
wire signed [31:0] emb_data;
wire [15:0] emb_index;
wire [3:0] done_error;
anvil_e3_top #({param_text(p)}) dut(
 .clk(clk),.rst_n(rst_n),.job_valid(job_valid),.job_mode(job_mode),
 .job_tokens(job_tokens),.job_patch_rows(job_patch_rows),.job_patch_cols(job_patch_cols),
 .job_audio_frames(job_audio_frames),.job_output_dim(job_output_dim),{connections},
 .mem_req_ready(mem_req_ready),.mem_rsp_valid(mem_rsp_valid),.mem_rsp_rdata(mem_rsp_rdata),
 .mem_rsp_error(mem_rsp_error),.emb_ready(emb_ready),.done_ready(done_ready),
 .job_ready(job_ready),.mem_req_valid(mem_req_valid),.mem_req_write(mem_req_write),
 .mem_req_addr(mem_req_addr),.mem_req_wdata(mem_req_wdata),.mem_rsp_ready(mem_rsp_ready),
 .emb_valid(emb_valid),.emb_data(emb_data),.emb_index(emb_index),.emb_last(emb_last),
 .done_valid(done_valid),.done_error(done_error),.busy(busy));
reg [31:0] scratch_memory[0:262143];
reg scratch_initialized[0:262143];
reg signed [31:0] expected[0:{dim-1}];
integer i,cycle=0,reads=0,writes=0,replies=0,pending=0,delay_count=0,beats=0,done_stalls=0;
integer req_stalls=0,emb_stalls=0;
reg last_write=0,error_seen=0,early_response=0;
integer early_count=0;
reg request_stalled=0, embedding_stalled=0, completion_stalled=0;
reg [96:0] request_hold;
reg [48:0] embedding_hold;
reg [3:0] completion_hold;
function automatic [31:0] memory_read(input [63:0] address);
begin
 if(address>=64'h8000000 && address<64'h8100000) begin
   if(scratch_initialized[(address-64'h8000000)/4] !== 1)
     $fatal(1,"MEMORY uninitialized scratch %h",address);
   memory_read=scratch_memory[(address-64'h8000000)/4];
 end else case(address)
 {image_cases}
 default: begin memory_read=32'hxxxxxxxx; $fatal(1,"MEMORY unmapped read %h",address); end
 endcase
end
endfunction
task reset_outputs;
begin
 if({{job_ready,mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata,mem_rsp_ready,
      emb_valid,emb_data,emb_index,emb_last,done_valid,done_error,busy}} !== 156'd0)
   $fatal(1,"RESET nonzero/unknown public output");
end
endtask
task reset_abort;
integer old_count;
begin
 old_count=reads+writes;
 rst_n=0;mem_rsp_valid=0;pending=0;mem_rsp_error=0;job_valid=0;
 #1;reset_outputs;
 repeat(2) @(negedge clk);
 rst_n=1;
 @(negedge clk);
 if(job_ready !== 1 || busy !== 0 || done_valid !== 0 || emb_valid !== 0)
   $fatal(1,"RESET abort did not return idle");
 job_mode=7;job_valid=1;
 @(posedge clk);#1;
 if(job_ready !== 0 || busy !== 1 || done_valid !== 0 || mem_req_valid !== 0)
   $fatal(1,"RESET epoch descriptor capture");
 @(negedge clk);job_valid=0;
 @(posedge clk);#1;
 if(done_valid !== 1 || done_error !== 1 || emb_valid !== 0 ||
    mem_req_valid !== 0 || reads+writes!=old_count)
   $fatal(1,"RESET stale work or wrong next-epoch completion");
 $display("RESET_OBSERVED {reset_kind} %0d",old_count);
 $finish;
end
endtask
initial begin
 for(i=0;i<262144;i=i+1) begin scratch_memory[i]=32'hxxxxxxxx; scratch_initialized[i]=0; end
 {expected_init}
 {descriptor_init}
 #1; reset_outputs;
 #20; rst_n=1;
 @(negedge clk);
 if(job_ready !== 1 || busy !== 0) $fatal(1,"PROTOCOL release to idle");
 job_valid=1;
 @(posedge clk); #1;
 if(job_ready !== 0 || busy !== 1 || mem_req_valid !== 0 ||
    done_valid !== 0 || emb_valid !== 0) $fatal(1,"PROTOCOL descriptor capture edge");
 {capture_reset}
 @(negedge clk); job_valid=0;
 job_mode=7;job_tokens=32'hffffffff;job_audio_frames=0;job_output_dim=0;
 weights_base=64'hffffffffffffffff;vision_weights_base=3;audio_weights_base=3;
 image_base=3;audio_base=3;tokens_base=3;positions_base=3;mask_base=3;scratch_base=3;
 if({backtoback}) job_valid=1;
 @(posedge clk);#1;
 if({error}==1 || {error}==5) begin
   if(done_valid !== 1 || done_error !== 4'd{error} || mem_req_valid !== 0)
     $fatal(1,"PROTOCOL E+1 descriptor/extent validation");
 end else if(done_valid !== 0 || mem_req_valid !== 0 || emb_valid !== 0)
   $fatal(1,"PROTOCOL E+1 legal validation staging");
end
always @(posedge clk) begin
 if(!rst_n) reset_outputs;
 else begin
   cycle=cycle+1;
   if(cycle>100000000) $fatal(1,"LIVENESS cycle bound");
   if(^{{job_ready,mem_req_valid,mem_rsp_ready,emb_valid,done_valid,busy}} === 1'bx)
     $fatal(1,"PROTOCOL unknown handshake");
   if({error}!=0 && emb_valid !== 0) $fatal(1,"ERROR embedding presented on unsuccessful job");
   if(request_stalled && {{mem_req_valid,mem_req_write,mem_req_addr,mem_req_wdata}}
        !== {{1'b1,request_hold}}) $fatal(1,"PROTOCOL stalled request changed");
   request_stalled=mem_req_valid && !mem_req_ready;
   request_hold={{mem_req_write,mem_req_addr,mem_req_wdata}};
   if(request_stalled) req_stalls=req_stalls+1;
   if(embedding_stalled && {{emb_valid,emb_data,emb_index,emb_last}}
        !== {{1'b1,embedding_hold}}) $fatal(1,"PROTOCOL stalled embedding changed");
   embedding_stalled=emb_valid && !emb_ready;
   embedding_hold={{emb_data,emb_index,emb_last}};
   if(embedding_stalled) emb_stalls=emb_stalls+1;
   if(completion_stalled && {{done_valid,done_error}} !== {{1'b1,completion_hold}})
     $fatal(1,"PROTOCOL stalled completion changed");
   completion_stalled=done_valid && !done_ready;
   completion_hold=done_error;
   if(mem_req_valid && mem_req_ready) begin
     if(error_seen) $fatal(1,"ERROR new request after memory error observed");
     if(pending || (mem_rsp_valid && !early_response))
       $fatal(1,"PROTOCOL multiple outstanding requests");
     if(mem_rsp_valid && early_response) begin
       if(mem_rsp_ready !== 0) $fatal(1,"PROTOCOL combinational response bypass");
       early_count=early_count+1;
     end
     if(^mem_req_addr === 1'bx || mem_req_addr[1:0] !== 0)
       $fatal(1,"ADDRESS unknown/unaligned");
     if(mem_req_write === 1) begin
       if(mem_req_addr<64'h8000000 || mem_req_addr>=64'h8100000)
         $fatal(1,"ADDRESS write outside scratch %h",mem_req_addr);
       if(^mem_req_wdata === 1'bx) $fatal(1,"DATA unknown scratch write");
       scratch_memory[(mem_req_addr-64'h8000000)/4]=mem_req_wdata;
       scratch_initialized[(mem_req_addr-64'h8000000)/4]=1;
       writes=writes+1; mem_rsp_rdata<=32'hdeadbeef;
       $display("WRITE %h %h",mem_req_addr,mem_req_wdata);
     end else if(mem_req_write === 0) begin
       mem_rsp_rdata<=memory_read(mem_req_addr); reads=reads+1;
     end else $fatal(1,"PROTOCOL unknown direction");
     pending=1;delay_count=cycle%4;
     last_write=mem_req_write;
     if({inject}) begin mem_rsp_error<=1;mem_rsp_rdata<=32'hffffffff; end
     else mem_rsp_error<=0;
   end
   if(mem_rsp_valid && mem_rsp_ready) begin
     if(!pending) $fatal(1,"PROTOCOL orphan response");
     pending=0;mem_rsp_valid<=0;replies=replies+1;
     if(mem_rsp_error) error_seen=1;
     early_response=0;
   end
   if(emb_valid && emb_ready) begin
     {output_check}
   end
   if(done_valid) begin
     if(job_ready !== 0) $fatal(1,"PROTOCOL accepted job before completion drained");
     {complete_check}
   end
 end
end
always @(negedge clk) begin
 if(!rst_n) reset_outputs;
 else begin
   mem_req_ready=cycle%5!=0 && cycle%7!=0;
   emb_ready=emb_stalls>=3 && cycle%5==0;
   done_ready=done_stalls>=3;
   if({reset_condition}) reset_abort;
   if(pending && !mem_rsp_valid) begin
     if(delay_count==0) mem_rsp_valid=1;
     else delay_count=delay_count-1;
   end
   if({early} && !pending && mem_req_valid && mem_req_ready && !mem_rsp_valid) begin
     mem_rsp_valid=1;early_response=1;
     mem_rsp_rdata=mem_req_write ? 32'hdeadbeef:memory_read(mem_req_addr);
   end
 end
end
initial begin #3600000000000; $fatal(1,"SIMULATION watchdog"); end
endmodule
"""


def check_integrated(text, fixture, name):
    actual = [signed(int(line.split()[2], 16))
              for line in text.splitlines() if line.startswith("EMBED ")]
    result = compare(actual, fixture["expected"], name, normalized=True)
    p = fixture["parameters"]
    image_mode = fixture["mode"] in (1, 2, 5, 6)
    patches = fixture.get("rows", 1)*fixture.get("cols", 1)
    offset = 5*patches*p["VISION_HIDDEN"]+p["VISION_SOFT_TOKENS"]*p["TEXT_HIDDEN"] if image_mode else 0
    n = len(fixture["ids"])
    first_writes = {}
    for address, value in read_writes(text):
        first_writes.setdefault(address, value)
    base = BASES["scratch_base"] + offset*4
    for field in ("ids", "positions", "masks"):
        actual = [first_writes.get(base+4*i) for i in range(n)]
        compare(actual, fixture[field], name+"-"+field, exact=True)
        base += 4*n
    expected_vectors = [quantize(x) for x in flatten(fixture["vectors"])]
    actual = [first_writes.get(base+4*i) for i in range(len(expected_vectors))]
    require(None not in actual, f"{name}: missing fusion vector")
    result["fusion_vectors"] = compare(actual, expected_vectors, name+"-fusion")
    return result


def integrated_cases(execution):
    ledger = {}
    for name, parameters in (("minimum", MINIMUM), ("ragged", RAGGED)):
        for mode in range(7):
            fixture = integrated_fixture(parameters, mode)
            case = f"integrated-{name}-mode{mode}"
            text = compile_tb(execution, case, integrated_tb(fixture))
            ledger[case] = check_integrated(text, fixture, case)
            (execution.directory / "integrated-comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
    return ledger


def extended_cases(execution, section=None):
    require(section in (None, "prefix", "audio", "protocol", "spatial"), "unknown extended section")
    ledger = {}
    cases = [(f"prefix-{dimension}", dict(RAGGED, TEXT_LAYERS=1, EMBED_DIM=768), 0, dimension)
             for dimension in (768, 512, 256, 128)]
    cases += [("full-default-layer-counts", DEFAULT_LAYERS, 6, 6)]
    cases += [(f"text-layers-{layers}", dict(RAGGED, TEXT_LAYERS=layers,
                                           TEXT_Q_HEADS=2, FULL_HEAD_DIM=4), 2, 12)
              for layers in (5, 6)]
    cases += [(f"minimum-prefix-{dimension}", MINIMUM, 6, dimension) for dimension in (6, 4, 2, 1)]
    for name, p, mode, dim in cases if section in (None, "prefix") else []:
        fixture = integrated_fixture(p, mode, output_dim=dim)
        text = compile_tb(execution, name, integrated_tb(fixture))
        ledger[name] = check_integrated(text, fixture, name)
    for dim in (6, 4, 2, 1) if section in (None, "prefix") else ():
        fixture = integrated_fixture(MINIMUM, 0, output_dim=dim, zero=True)
        name = f"zero-prefix-{dim}"
        text = compile_tb(execution, name, integrated_tb(fixture))
        ledger[name] = check_integrated(text, fixture, name)
        require(ledger[name]["squared_norm"] == 0, f"{name}: nonzero zero prefix")
    if section == "prefix":
        return ledger
    for frames in (1, 2, 3, 4, 5, 41, 45, 49, 105) if section in (None, "audio") else ():
        fixture = integrated_fixture(MINIMUM, 3, frames=frames)
        name = f"audio-length-{frames}"
        text = compile_tb(execution, name, integrated_tb(fixture))
        ledger[name] = check_integrated(text, fixture, name)
        require(sum(token == 258881 for token in fixture["ids"]) == (frames+3)//4,
                f"{name}: oracle framing boundary")
    if section == "audio":
        return ledger
    protocol_cases = (("early-response", dict(early=True)), ("back-to-back", dict(backtoback=True)),
                      ("early-and-back-to-back", dict(early=True, backtoback=True)))
    for name, flags in protocol_cases if section in (None, "protocol") else ():
        fixture = integrated_fixture(MINIMUM, 6)
        fixture.update(flags)
        text = compile_tb(execution, name, integrated_tb(fixture))
        ledger[name] = check_integrated(text, fixture, name)
        if flags.get("backtoback"):
            require("BACK_TO_BACK_OBSERVED" in text, f"{name}: no second capture comparison")
    if section in (None, "protocol"):
        fixture = integrated_fixture(dict(RAGGED, VOCAB_SIZE=32), 0)
        name = "reduced-text-vocabulary"
        text = compile_tb(execution, name, integrated_tb(fixture))
        ledger[name] = check_integrated(text, fixture, name)
        fixture = integrated_fixture(MINIMUM, 0)
        fixture["descriptor"] = dict(audio_weights_base=3, audio_base=3, vision_weights_base=3,
                                     image_base=3, job_audio_frames=0,
                                     job_patch_rows="32'hffffffff", job_patch_cols="32'hffffffff")
        text = compile_tb(execution, "absent-modalities", integrated_tb(fixture))
        ledger["absent-modalities"] = check_integrated(text, fixture, "absent-modalities")
    if section == "protocol":
        return ledger
    parameters = dict(RAGGED, VISION_HIDDEN=8, VISION_HEADS=2, PATCH_SIZE=2, POOL_KERNEL=3,
                      VISION_LAYERS=2, TEXT_LAYERS=6, TEXT_Q_HEADS=2, FULL_HEAD_DIM=4)
    fixture = integrated_fixture(parameters, 6, rows=2, cols=3)
    fixture.update(rows=2, cols=3)
    text = compile_tb(execution, "multipatch-axial-gqa", integrated_tb(fixture))
    ledger["multipatch-axial-gqa"] = check_integrated(text, fixture, "multipatch-axial-gqa")
    return ledger


def error_cases(execution):
    ledger = {}
    base = integrated_fixture(MINIMUM, 0)
    descriptors = [
        ("mode7", dict(job_mode=7), 1),
        ("text-zero-count", dict(job_tokens=0), 1),
        ("nontext-count", dict(job_mode=3, job_tokens=1), 1),
        ("audio-zero-frames", dict(job_mode=3, job_tokens=0, job_audio_frames=0), 1),
        ("vision-zero-rows", dict(job_mode=1, job_tokens=0, job_patch_rows=0), 1),
        ("vision-zero-cols", dict(job_mode=1, job_tokens=0, job_patch_cols=0), 1),
        ("zero-output-dimension", dict(job_output_dim=0), 1),
        ("output-dimension", dict(job_output_dim=3), 1),
        ("unaligned-weights", dict(weights_base=3), 1),
        ("unaligned-scratch", dict(scratch_base=3), 1),
        ("unaligned-tokens", dict(tokens_base=3), 1),
        ("unaligned-positions", dict(positions_base=3), 1),
        ("unaligned-masks", dict(mask_base=3), 1),
        ("unaligned-audio", dict(job_mode=3, job_tokens=0, audio_base=3), 1),
        ("unaligned-audio-weights", dict(job_mode=3, job_tokens=0, audio_weights_base=3), 1),
        ("unaligned-image", dict(job_mode=1, job_tokens=0, image_base=3), 1),
        ("unaligned-vision-weights", dict(job_mode=1, job_tokens=0, vision_weights_base=3), 1),
        ("vision-pool-count", dict(job_mode=1, job_tokens=0, job_patch_rows=2), 1),
        ("weight-extent", dict(weights_base="64'hfffffffffffffffc"), 5),
        ("scratch-extent", dict(scratch_base="64'hfffffffffffffffc"), 5),
        ("token-extent", dict(tokens_base="64'hfffffffffffffffc"), 5),
        ("position-extent", dict(positions_base="64'hfffffffffffffffc"), 5),
        ("mask-extent", dict(mask_base="64'hfffffffffffffffc"), 5),
        ("audio-extent", dict(job_mode=3, job_tokens=0, audio_base="64'hfffffffffffffffc"), 5),
        ("audio-weight-extent", dict(job_mode=3, job_tokens=0,
                                     audio_weights_base="64'hfffffffffffffffc"), 5),
        ("image-extent", dict(job_mode=1, job_tokens=0, image_base="64'hfffffffffffffffc"), 5),
        ("vision-weight-extent", dict(job_mode=1, job_tokens=0,
                                      vision_weights_base="64'hfffffffffffffffc"), 5),
        ("descriptor-priority", dict(job_mode=7, weights_base="64'hfffffffffffffffc"), 1),
    ]
    for name, descriptor, error in descriptors:
        fixture = dict(base, descriptor=descriptor, error=error)
        text = compile_tb(execution, "error-"+name, integrated_tb(fixture))
        require(f"ERROR_OBSERVED {error} " in text, f"{name}: error event absent")
        ledger[name] = dict(error=error, observed=True, descriptor=descriptor)
    for mode, vocab in ((3, 258883), (1, 258882)):
        fixture = integrated_fixture(dict(MINIMUM, VOCAB_SIZE=vocab), mode)
        fixture["error"] = 1
        text = compile_tb(execution, f"error-vocabulary-{mode}", integrated_tb(fixture))
        require("ERROR_OBSERVED 1 " in text, "special-token vocabulary was not rejected")
        ledger[f"vocabulary-mode{mode}"] = dict(error=1, observed=True)
    for name, address, value, error in (
            ("token-range", BASES["tokens_base"], MINIMUM["VOCAB_SIZE"], 2),
            ("mask-range", BASES["mask_base"], 2, 2),
            ("position-range", BASES["positions_base"], MINIMUM["MAX_SEQ_LEN"], 2)):
        memory = dict(base["memory"]); memory[address] = value
        fixture = dict(base, memory=memory, error=error)
        text = compile_tb(execution, "error-"+name, integrated_tb(fixture))
        require(f"ERROR_OBSERVED {error} " in text, f"{name}: error event absent")
        ledger[name] = dict(error=error, observed=True)
    memory = dict(base["memory"])
    for i in range(base["tokens"]):
        memory[BASES["mask_base"]+4*i] = 0
    fixture = dict(base, memory=memory, error=4)
    text = compile_tb(execution, "error-all-masked", integrated_tb(fixture))
    require("ERROR_OBSERVED 4 " in text, "all masked completion missing")
    ledger["all-masked"] = dict(error=4, observed=True)
    for suffix in ("input_min", "output_min"):
        fixture = integrated_fixture(MINIMUM, 3)
        _, offsets = synthetic_audio(MINIMUM, SEED)
        name = "audio_tower.layers.0.feed_forward1.ffw_layer_1."+suffix
        fixture["memory"][BASES["audio_weights_base"]+4*offsets[name]] = quantize(1)
        fixture["error"] = 2
        text = compile_tb(execution, "error-clipping-"+suffix, integrated_tb(fixture))
        require("ERROR_OBSERVED 2 " in text, "inverted clipping bounds not rejected")
        ledger["clipping-"+suffix] = dict(error=2, observed=True)
    fixture = integrated_fixture(MINIMUM, 4)
    fixture["memory"][BASES["positions_base"]] = 0xFFFFFFFE
    fixture["error"] = 2
    text = compile_tb(execution, "error-shifted-position", integrated_tb(fixture))
    require("ERROR_OBSERVED 2 " in text, "shifted position overflow not rejected")
    ledger["shifted-position"] = dict(error=2, observed=True)
    for mode in range(7):
        for target in ("read", "write"):
            fixture = integrated_fixture(MINIMUM, mode)
            inject = "reads==1 && !mem_req_write" if target == "read" else "writes==1 && mem_req_write"
            fixture.update(error=3, inject=inject)
            name = f"error-mode{mode}-{target}"
            text = compile_tb(execution, name, integrated_tb(fixture))
            require("ERROR_OBSERVED 3 " in text, f"{name}: memory error missing")
            ledger[name] = dict(error=3, observed=True)
    for kind in ("capture", "read", "write", "embedding", "completion"):
        fixture = integrated_fixture(MINIMUM, 6)
        fixture["reset"] = kind
        text = compile_tb(execution, "reset-"+kind, integrated_tb(fixture))
        require(f"RESET_OBSERVED {kind} " in text, f"reset {kind} not observed")
        ledger["reset-"+kind] = dict(observed=True, epoch_abort=True)
    return ledger


def bridge_case(execution):
    p = RAGGED
    tensors, offsets = synthetic_audio(p, SEED+20)
    values = [[stored(x) for x in (0.3, -0.7, 0.15)],
              [stored(x) for x in (-0.25, 0.6, 0.4)]]
    parameters = {k: v for k, v in p.items()
                  if (k.startswith("AUDIO_") and k not in
                      ("AUDIO_HEADS", "AUDIO_CHUNK_SIZE", "AUDIO_CONTEXT_LEFT", "AUDIO_CONTEXT_RIGHT"))
                  or k == "TEXT_HIDDEN"}
    instance = f"""
anvil_e3_audio_bridge #({param_text(parameters)}) dut(
 {COMMON},.tokens(32'd2),.weights(64'h1000),.input_base(64'h10000),
 .work_base(64'h20000),.output_base(64'h40000));
"""
    init = audio_memory(tensors, offsets, 0x1000)+put_values(0x10000, values)
    text = compile_tb(execution, "bridge", memory_tb(instance, "", "", init, "", first_command_edge=2))
    projected = [matrix(value, tensors["audio_tower.output_proj.weight"],
                        bias=tensors["audio_tower.output_proj.bias"]) for value in values]
    expected = [matrix(value, tensors["embed_audio.embedding_projection.weight"]) for value in projected]
    return compare(observed(text, 0x40000, 2*p["TEXT_HIDDEN"]),
                   [quantize(x) for x in flatten(expected)], "audio-output-bias-bridge")


def official_slices():
    directory = ROOT / "hf_embeddinggemma2_trimodal_spec/official_weights"
    manifest = json.loads((directory / "official_weights_manifest.json").read_text())
    binary = directory / manifest["extracted_safetensors_file"]
    require(sha(binary) == manifest["extracted_safetensors_sha256"],
            "official extracted safetensors SHA mismatch")
    payload = binary.read_bytes()
    length = struct.unpack("<Q", payload[:8])[0]
    header = json.loads(payload[8:8+length])
    slices = json.loads((directory / "official_hardware_slices_fp32_q824.json").read_text())
    comparisons = 0
    for name, tensor in slices.items():
        source = header[name]
        require(source["dtype"] == "BF16", f"official dtype {name}")
        values = tensor["fp32"]
        integer = flatten(tensor["q8_24"])
        require([quantize(x) for x in flatten(values)] == integer,
                f"official JSON quantization {name}")
        for index, value in enumerate(flatten(values)):
            if len(tensor["shape"]) == 2:
                row, col = divmod(index, tensor["shape"][1])
                source_index = row*source["shape"][-1]+col
            else:
                source_index = index
            offset = 8+length+source["data_offsets"][0]+2*source_index
            bf16 = struct.unpack("<H", payload[offset:offset+2])[0]
            decoded = struct.unpack("<f", struct.pack("<I", bf16 << 16))[0]
            require(decoded == value, f"official BF16/source slice disagreement {name}[{index}]")
            comparisons += 1
    return slices, dict(tensors=len(slices), bf16_values_compared=comparisons, binary_sha256=sha(binary))


def official_cases(execution):
    slices, ledger = official_slices()
    matrices = [(name, tensor) for name, tensor in slices.items()
                if len(tensor["shape"]) == 2 and "embed_tokens" not in name
                and "position_embedding" not in name]
    vectors = [(name, tensor) for name, tensor in slices.items() if "norm" in name]
    input_values = [quantize(x) for x in slices["language_model.embed_tokens.weight"]["fp32"][7]]
    tasks = []
    for index, (name, tensor) in enumerate(matrices):
        rows, cols = tensor["shape"]
        weights = tensor["q8_24"]
        expected = [max(-(1 << 47), min((1 << 47)-(1 << 16),
                        nearest(sum(x*y for x, y in zip(row, input_values[:cols])), 1 << 8)))
                    for row in weights]
        initializers = "\n".join(f"weights[{r*cols+c}]={word(weights[r][c])};"
                                 for r in range(rows) for c in range(cols))
        initializers += "\n"+"\n".join(f"expected[{i}]=48'h{x & ((1 << 48)-1):012x};"
                                      for i, x in enumerate(expected))
        tasks.append(f"""
rows={rows};cols={cols};{initializers}
@(negedge clk);start_valid=1;
@(posedge clk);#1;
@(negedge clk);start_valid=0;feed_index=0;received=0;
while(feed_index<cols) begin
 in_valid=1;in_data=inputs[feed_index];
 @(posedge clk);
 if(in_ready) feed_index=feed_index+1;
 @(negedge clk);
end
in_valid=0;
wait(done_valid);#1;
if(done_error !== 0 || received!=rows) $fatal(1,"OFFICIAL matrix completion {index}");
$display("OFFICIAL_MATRIX {index} %0d",received);
@(negedge clk);done_ready=1;
@(posedge clk);#1;
@(negedge clk);done_ready=0;
""")
    init_inputs = "\n".join(f"inputs[{i}]=48'h{(x << 16) & ((1 << 48)-1):012x};"
                           for i, x in enumerate(input_values))
    text = f"""
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,start_valid=0,in_valid=0,result_valid=0,done_ready=0;
reg [31:0] rows=0,cols=0;
reg signed [47:0] in_data=0;
wire start_ready,in_ready,cmd_valid,result_ready,out_valid,out_last,done_valid;
wire [63:0] cmd_addr;
wire signed [47:0] out_data,mac_a,mac_b,rounded;
wire [31:0] out_index;
wire [3:0] done_error;
wire mac_clear,mac_accumulate;
reg signed [31:0] result_data=0,weights[0:1023];
reg signed [47:0] expected[0:31],inputs[0:15];
integer cycle=0,feed_index=0,received=0;
wire ready=cycle%5!=0;
anvil_e2_matvec #(.MAX_INPUT(16)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_rows(rows),.start_cols(cols),.start_weights(64'h1000),
 .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.cmd_valid(cmd_valid),
 .cmd_ready(ready),.cmd_addr(cmd_addr),.result_valid(result_valid),
 .result_ready(result_ready),.result_data(result_data),.result_error(1'b0),
 .mac_clear(mac_clear),.mac_accumulate(mac_accumulate),.mac_a(mac_a),.mac_b(mac_b),
 .mac_rounded(rounded),.out_valid(out_valid),.out_ready(ready),.out_data(out_data),
 .out_index(out_index),.out_last(out_last),.done_valid(done_valid),.done_ready(done_ready),
 .done_error(done_error));
anvil_e2_mac reduction(.clk(clk),.rst_n(rst_n),.clear(mac_clear),.accumulate(mac_accumulate),
 .a(mac_a),.b(mac_b),.rounded(rounded),.sum(),.product());
always @(posedge clk) if(rst_n) begin
 cycle=cycle+1;
 if(cmd_valid && ready) begin
   if(result_valid) $fatal(1,"OFFICIAL outstanding command");
   result_data<=weights[(cmd_addr-64'h1000)/4];result_valid<=1;
 end
 if(result_valid && result_ready) result_valid<=0;
 if(out_valid && ready) begin
   if(out_index !== received || out_last !== (received==rows-1) ||
      out_data !== expected[received])
     $fatal(1,"OFFICIAL matrix exact reduction index=%0d got=%h expected=%h",
            received,out_data,expected[received]);
   received=received+1;
 end
end
initial begin
 {init_inputs}
 #21;rst_n=1;
 {''.join(tasks)}
 $display("OFFICIAL_MATRICES_DONE {len(matrices)}");
 $finish;
end
initial begin #3600000000000;$fatal(1,"OFFICIAL watchdog");end
endmodule
"""
    output = compile_tb(execution, "official-matrices", text)
    require(f"OFFICIAL_MATRICES_DONE {len(matrices)}" in output, "missing official matrix comparisons")
    ledger["matrix_operations"] = [dict(name=name, shape=tensor["shape"], exact=True)
                                   for name, tensor in matrices]
    tasks = []
    for index, (name, tensor) in enumerate(vectors):
        count = len(tensor["q8_24"])
        values = [real(input_values[i % len(input_values)]) for i in range(count)]
        expected = retained_norm(values, tensor["fp32"])
        init = "\n".join(
            f"values[{i}]=48'h{(quantize(value) << 16) & ((1 << 48)-1):012x};"
            f"weights[{i}]={word(tensor['q8_24'][i])};"
            f"expected[{i}]={value_expected:.17g};"
            for i, (value, value_expected) in enumerate(zip(values, expected)))
        tasks.append(f"""
count={count};received=0;{init}
@(negedge clk);start_valid=1;
@(posedge clk);#1;
@(negedge clk);start_valid=0;feed_index=0;
while(feed_index<count) begin
 in_valid=1;in_data=values[feed_index];in_weight=weights[feed_index];
 @(posedge clk);if(in_ready) feed_index=feed_index+1;
 @(negedge clk);
end
in_valid=0;
wait(received==count);
$display("OFFICIAL_NORM {index} %0d",received);
""")
    text = f"""
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,start_valid=0,in_valid=0;
wire start_ready,in_ready,out_valid,out_last,out_error;
reg [31:0] count=0;
reg signed [47:0] in_data=0,values[0:31];
reg signed [31:0] in_weight=0,weights[0:31];
wire signed [47:0] out_data;
wire [31:0] out_index;
real expected[0:31],difference;
integer feed_index=0,received=0,cycle=0;
wire ready=cycle%5!=0;
anvil_e2_norm #(.MAX_WIDTH(32)) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_count(count),.start_l2(1'b0),.in_valid(in_valid),.in_ready(in_ready),
 .in_data(in_data),.in_weight(in_weight),.out_valid(out_valid),.out_ready(ready),
 .out_data(out_data),.out_index(out_index),.out_last(out_last),.out_error(out_error));
always @(posedge clk) if(rst_n) begin
 cycle=cycle+1;
 if(out_valid && ready) begin
   if(out_error !== 0 || out_index !== received || out_last !== (received==count-1) ||
      ^out_data === 1'bx) $fatal(1,"OFFICIAL norm protocol");
   difference=$itor($signed(out_data[47:16]))/16777216.0-expected[received];
   if(difference>0.002 || difference< -0.002)
     $fatal(1,"OFFICIAL norm mismatch index=%0d error=%f",received,difference);
   received=received+1;
 end
end
initial begin
 #21;rst_n=1;
 {''.join(tasks)}
 $display("OFFICIAL_NORMS_DONE {len(vectors)}");
 $finish;
end
initial begin #3600000000000;$fatal(1,"OFFICIAL watchdog");end
endmodule
"""
    output = compile_tb(execution, "official-norms", text)
    require(f"OFFICIAL_NORMS_DONE {len(vectors)}" in output, "missing official norm comparisons")
    ledger["norm_operations"] = [dict(name=name, shape=tensor["shape"])
                                 for name, tensor in vectors]
    ledger["limitations"] = "Extracted retained hardware slices only; all audio weights are synthetic"
    return ledger


def legacy_cases(execution):
    ledger = {}
    for mode in range(3):
        fixture = integrated_fixture(RAGGED, mode)
        current = compile_tb(execution, f"legacy-current-mode{mode}", integrated_tb(fixture))
        check_integrated(current, fixture, f"legacy-current-mode{mode}")
        p = {k: v for k, v in RAGGED.items() if not k.startswith("AUDIO_")}
        text = integrated_tb(fixture)
        text = text.replace("anvil_e3_top #("+param_text(RAGGED)+")",
                            "anvil_e2_top #("+param_text(p)+")")
        text = text.replace(".job_audio_frames(job_audio_frames),", "")
        text = text.replace(".audio_weights_base(audio_weights_base),", "")
        text = text.replace(".audio_base(audio_base),", "")
        text = text.replace(".job_mode(job_mode)", ".job_mode(job_mode[1:0])")
        sources = sorted((ROOT / "anvil_e2_reference/rtl").glob("*.sv"))
        output = compile_tb(execution, f"legacy-mode{mode}", text, sources)
        ledger[f"legacy-mode{mode}"] = check_integrated(output, fixture, f"legacy-mode{mode}")
        original = [signed(int(line.split()[2], 16))
                    for line in output.splitlines() if line.startswith("EMBED ")]
        revised = [signed(int(line.split()[2], 16))
                   for line in current.splitlines() if line.startswith("EMBED ")]
        ledger[f"legacy-mode{mode}"]["side_by_side"] = compare(
            revised, original, f"legacy-vs-E3-mode{mode}", exact=True)
    return ledger


def single_framing_case(execution):
    fixture = integrated_fixture(RAGGED, 6)
    text = compile_tb(execution, "mutant-framing", integrated_tb(fixture))
    return check_integrated(text, fixture, "framing")


def single_hybrid_case(execution):
    fixture = integrated_fixture(RAGGED, 0)
    text = compile_tb(execution, "mutant-hybrid", integrated_tb(fixture))
    return check_integrated(text, fixture, "hybrid")


def single_prefix_case(execution):
    fixture = integrated_fixture(RAGGED, 0, output_dim=4)
    text = compile_tb(execution, "mutant-prefix", integrated_tb(fixture))
    return check_integrated(text, fixture, "prefix")


def memory_bridge_case(execution):
    text = """
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,cmd_valid=0,cmd_write=0,result_ready=0,mem_req_ready=0;
reg mem_rsp_valid=0,mem_rsp_error=0;
reg [63:0] cmd_addr=0;
reg [31:0] cmd_wdata=0,mem_rsp_rdata=0;
wire cmd_ready,result_valid,result_error,mem_req_valid,mem_req_write,mem_rsp_ready;
wire [31:0] result_data,mem_req_wdata;
wire [63:0] mem_req_addr;
integer transactions=0;
anvil_e2_memory dut(.*);
task zero_outputs;
begin
 if({cmd_ready,result_valid,result_data,result_error,mem_req_valid,mem_req_write,
     mem_req_addr,mem_req_wdata,mem_rsp_ready} !== 134'd0)
   $fatal(1,"BRIDGE reset outputs");
end
endtask
always @(posedge clk) if(!rst_n) zero_outputs;
always @(negedge clk) if(!rst_n) zero_outputs;
task transaction(input write_bit,input [63:0] address,input [31:0] data,response,
                 input response_error);
begin
 @(negedge clk);
 if(cmd_ready !== 1) $fatal(1,"BRIDGE idle command ready");
 cmd_valid=1;cmd_write=write_bit;cmd_addr=address;cmd_wdata=data;
 @(posedge clk);
 if(mem_req_valid !== 0 || result_valid !== 0) $fatal(1,"BRIDGE command bypass pre-C");
 #1;
 if(mem_req_valid !== 1 || mem_req_addr !== address || mem_req_write !== write_bit ||
    mem_req_wdata !== data || cmd_ready !== 0 || mem_rsp_ready !== 0)
   $fatal(1,"BRIDGE command capture post-C");
 @(negedge clk);cmd_valid=0;cmd_addr=64'hffffffffffffffff;cmd_wdata=32'hbad0bad0;
 mem_rsp_valid=1;mem_rsp_rdata=response;mem_rsp_error=response_error;
 repeat(3) begin
   @(posedge clk);
   if(mem_req_valid !== 1 || mem_req_addr !== address || mem_req_write !== write_bit ||
      mem_req_wdata !== data || mem_rsp_ready !== 0 || result_valid !== 0)
     $fatal(1,"BRIDGE request stall/early response");
   #1;
 end
 @(negedge clk);mem_req_ready=1;
 @(posedge clk);#1;
 if(mem_req_valid !== 0 || mem_rsp_ready !== 1 || result_valid !== 0)
   $fatal(1,"BRIDGE request-to-response staging post-R");
 @(negedge clk);mem_req_ready=0;
 @(posedge clk);#1;
 if(mem_rsp_ready !== 0 || result_valid !== 1 || result_data !== response ||
    result_error !== response_error || cmd_ready !== 0)
   $fatal(1,"BRIDGE response-to-result staging post-S");
 @(negedge clk);mem_rsp_valid=0;mem_rsp_rdata=32'hbad0bad0;mem_rsp_error=!response_error;
 repeat(3) begin
   @(posedge clk);
   if(result_valid !== 1 || result_data !== response || result_error !== response_error ||
      cmd_ready !== 0 || mem_req_valid !== 0)
     $fatal(1,"BRIDGE internal result stall");
   #1;
 end
 @(negedge clk);result_ready=1;
 @(posedge clk);#1;
 if(result_valid !== 0 || cmd_ready !== 1 || mem_req_valid !== 0)
   $fatal(1,"BRIDGE result retirement post-U");
 @(negedge clk);result_ready=0;
 transactions=transactions+1;
end
endtask
initial begin
 #1;zero_outputs;#20;rst_n=1;
 transaction(0,64'h123456789abc0000,32'hbad00bad,32'h81234567,0);
 transaction(1,64'h223456789abc0004,32'h76543210,32'hffffffff,1);
 if(transactions!=2) $fatal(1,"BRIDGE missing observations");
 $display("BRIDGE_OBSERVED 2");$finish;
end
initial begin #3600000000000;$fatal(1,"BRIDGE watchdog");end
endmodule
"""
    output = compile_tb(execution, "memory-bridge", text)
    require("BRIDGE_OBSERVED 2" in output, "bridge transfer comparisons missing")
    return dict(transactions=2, request_stalls=6, result_stalls=6,
                early_response_coincidences=2, rising_edge_stage_comparisons=8)


def mutation_cases(execution, shard=None):
    mutations = [
        ("half-residual", "anvil_e3_audio_vector.sv", "if (half_weight) begin",
         "if (1'b0 && half_weight) begin", primitive_vectors),
        ("clipped-input", "anvil_e3_audio_vector.sv", "if (clipped && $signed(result_data)",
         "if (1'b0 && clipped && $signed(result_data)", primitive_vectors),
        ("relative-context", "anvil_e3_audio_attention.sv",
         "chunk_start-AUDIO_CONTEXT_LEFT:64'd0;", "64'd0:64'd0;", attention_cases),
        ("relative-projection", "anvil_e3_audio_attention.sv",
         "relative_value<=work[63:0];", "relative_value<=0;", attention_cases),
        ("per-dimension-scale", "anvil_e3_audio_attention.sv",
         "scaled_query[component]<=work[63:0];",
         "scaled_query[component]<=query_value;", attention_cases),
        ("logit-cap", "anvil_e3_audio_activation.sv",
         "3: result<=saturate(argument<0 ? -50*ratio:50*ratio);",
         "3: result<=saturate(argument);", attention_cases),
        ("depthwise-index", "anvil_e3_audio_conv.sv", "64'(out_c)*KERNEL+ky:",
         "64'(out_c)*KERNEL+(KERNEL-1-ky):", convolution_cases),
        ("output-bias-bridge", "anvil_e3_audio_bridge.sv", ".start_bias(!second_projection)",
         ".start_bias(1'b0)", bridge_case),
        ("framing-order", "anvil_e3_trimodal_fusion.sv", "id_hold<=256000;", "id_hold<=255999;",
         single_framing_case),
        ("hybrid-full-selection", "anvil_e2_hybrid_layer.sv", "VISION || layer%6==5",
         "VISION || 1'b0", single_hybrid_case),
        ("ple-injection", "anvil_e2_hybrid_layer.sv",
         "`E2_VECTOR(3,3,4,4,PER_LAYER_INPUT_SIZE,48)",
         "`E2_VECTOR(3,3,3,4,PER_LAYER_INPUT_SIZE,48)", single_hybrid_case),
        ("selected-prefix-normalization", "anvil_e2_pool.sv", "assign norm_start_l2=rst_n;",
         "assign norm_start_l2=1'b0;", single_prefix_case),
        ("memory-cycle-staging", "anvil_e2_memory.sv",
         "REQUEST: if (mem_req_ready) state <= RESPONSE;",
         "REQUEST: if (mem_req_ready) state <= RESULT;", memory_bridge_case),
    ]
    ledger = {}
    if shard is not None:
        mutations = [value for i, value in enumerate(mutations) if i % shard[1] == shard[0]]
    original_hashes = {str(p): sha(p) for p in SOURCES}
    # These named golden cases run before their corresponding isolated mutants.
    for name, filename, before, after, checker in mutations:
        directory = execution.directory / ("mutant-"+name)
        directory.mkdir()
        sources = []
        for source in SOURCES:
            target = directory / source.name
            contents = source.read_text()
            if source.name == filename:
                require(before in contents, f"{name}: mutation anchor not found")
                contents = contents.replace(before, after)
            target.write_text(contents)
            sources.append(target)
        mutation = dict(name=name, file=filename, before=before, after=after,
                        original_sha256=sha(ROOT / "rtl" / filename),
                        mutant_sha256=sha(directory / filename))
        (directory / "mutation.json").write_text(json.dumps(mutation, indent=2)+"\n")
        start = len(execution.records)
        execution.sources = sources
        rejection = None
        try:
            checker(execution)
        except AssertionError as exc:
            rejection = str(exc)
        finally:
            execution.sources = SOURCES
        commands = execution.records[start:]
        require(commands, f"{name}: mutant did not execute")
        compile_records = [r for r in commands if "-compile" in r["stdout_path"]]
        require(compile_records and all(r["exit_code"] == 0 for r in compile_records),
                f"{name}: parse/elaboration failure does not establish sensitivity")
        sim_records = [r for r in commands if "-simulate" in r["stdout_path"]]
        require(sim_records and all(not r["timed_out"] for r in sim_records),
                f"{name}: timeout does not establish sensitivity")
        diagnostics = "\n".join((execution.directory / r["stdout_path"]).read_text()
                                for r in sim_records)
        require(rejection is not None, f"{name}: escaped numerical/protocol detection")
        if any(r["exit_code"] != 0 for r in sim_records):
            require(any(marker in diagnostics for marker in
                        ("NUMERICAL component mismatch", "EMBEDDING beat count/index/last",
                         "COMPLETION expected success", "BRIDGE request-to-response staging")),
                    f"{name}: mutant failed outside intended numerical/protocol assertions")
        else:
            require(any(marker in rejection for marker in
                        ("exact mismatch", "max_abs_error", "cosine", "fusion")),
                    f"{name}: checker failed for an unrelated reason: {rejection}")
        ledger[name] = dict(mutation=mutation, rejected=True, assertion=rejection,
                            commands=[r["argv"] for r in commands],
                            logs=[r["stdout_path"] for r in sim_records])
        (execution.directory / "mutation-results.json").write_text(json.dumps(ledger, indent=2)+"\n")
    require(original_hashes == {str(p): sha(p) for p in SOURCES},
            "accepted RTL changed during isolated mutation campaign")
    return ledger


def elaborate(execution):
    execution.tool("iverilog", ["-V"])
    execution.tool("vvp", ["-V"])
    inventory_check()
    for name, parameters in (("defaults", {}), ("minimum", MINIMUM),
                              ("ragged", RAGGED), ("default-layer-counts", DEFAULT_LAYERS),
                              ("production-output", dict(MINIMUM, EMBED_DIM=768))):
        argv = ["iverilog", "-g2012", "-Wall", "-t", "null", "-s", "anvil_e3_top"]
        argv += [f"-Panvil_e3_top.{k}={v}" for k, v in parameters.items()]
        execution.run(f"elaborate-{name}", [*argv, *SOURCES])
    illegal = [
        dict(AUDIO_HIDDEN=0), dict(AUDIO_HEADS=2), dict(AUDIO_CONV_KERNEL=2),
        dict(AUDIO_CHUNK_SIZE=0), dict(AUDIO_CONTEXT_LEFT=-1), dict(EMBED_DIM=5),
        dict(VISION_HEAD_DIM=3), dict(LOCAL_HEAD_DIM=1), dict(TEXT_LAYERS=0),
        dict(AUDIO_FFN=65536), dict(AUDIO_CONTEXT_RIGHT=-1), dict(FULL_HEAD_DIM=3),
        dict(TEXT_Q_HEADS=3, LOCAL_KV_HEADS=2),
    ]
    positive = [key for key in MINIMUM if key not in
                ("AUDIO_HIDDEN", "TEXT_LAYERS", "EMBED_DIM")]
    illegal += [{key: 0} for key in positive]
    for i, overrides in enumerate(illegal):
        parameters = dict(MINIMUM, **overrides)
        path = execution.directory / f"illegal-{i}.vvp"
        argv = ["iverilog", "-g2012", "-Wall", "-s", "anvil_e3_top", "-o", path]
        argv += [f"-Panvil_e3_top.{k}={v}" for k, v in parameters.items()]
        execution.run(f"illegal-{i}-compile", [*argv, *SOURCES])
        record = execution.run(f"illegal-{i}-reject", ["vvp", path], expected_exit=None)
        text = (execution.directory / record["stdout_path"]).read_text()
        require("PARAMETER ERROR" in text, f"illegal-{i}: rejection was not a parameter diagnostic")


def synthesis(execution):
    execution.tool("yosys", ["-V"])
    statistics = []
    for name, parameters in (("minimum", MINIMUM), ("ragged", RAGGED)):
        script = execution.directory / f"{name}.ys"
        lowered = execution.directory / f"{name}-lowered.json"
        netlist = execution.directory / f"{name}-synthesized.json"
        script.write_text(
            "read_verilog -sv " + " ".join(str(p) for p in SOURCES) + "\n" +
            "chparam " + " ".join(f"-set {k} {v}" for k, v in parameters.items()) +
            " anvil_e3_top\nhierarchy -check -top anvil_e3_top\n" +
            "rename -top anvil_e3_top\n" +
            "proc\nopt\ncheck -assert\n" +
            "select -assert-none t:$dlatch t:$adlatch t:$dlatchsr\n" +
            f"write_json {lowered}\n" +
            "synth -top anvil_e3_top\ncheck -assert\n" +
            "select -assert-none t:$dlatch t:$adlatch t:$dlatchsr t:$_DLATCH_*\n" +
            f"stat\nwrite_json {netlist}\n")
        execution.run(f"synthesis-{name}", ["yosys", "-Q", "-T", "-s", script],
                      timeout=21600)
        for stage, path in (("lowered", lowered), ("synthesized", netlist)):
            document = json.loads(path.read_text())
            modules = document["modules"]
            require("anvil_e3_top" in modules, f"{name}/{stage}: missing top")
            if stage == "lowered":
                instances = {cell_name.split(".")[-1]
                             for cell_name in modules["anvil_e3_top"]["cells"]}
                required = {"audio_subsample", "audio_conformer", "audio_bridge", "vision_patch_embed",
                            "vision_encoder", "vision_pool", "trimodal_fusion", "text_frontend",
                            "hybrid_layer", "pool_norm", "memory_bridge"}
                require(required <= instances, f"{name}: missing functional blocks {required-instances}")
            count = 0
            for module_name, module in modules.items():
                attrs = module.get("attributes", {})
                for attr in ("blackbox", "whitebox"):
                    require(int(str(attrs.get(attr, "0")), 2) == 0,
                            f"{name}/{stage}: {attr} {module_name}")
                for cell in module.get("cells", {}).values():
                    kind = cell["type"]
                    require("latch" not in kind.lower(), f"{name}/{stage}: inferred {kind}")
                    require(kind.startswith("$") or kind in modules,
                            f"{name}/{stage}: unresolved module {kind}")
                    count += 1
            require(count > 0, f"{name}/{stage}: empty design")
            statistics.append(dict(configuration=name, parameters=parameters,
                                   stage=stage, cells=count, json=path.name, sha256=sha(path)))
    (execution.directory / "structural-results.json").write_text(json.dumps(statistics, indent=2)+"\n")


def run_groups(execution, groups):
    results, failures = {}, {}

    def run_one(name, function):
        child = Execution(execution.directory / name, f"Independent behavior group {name}")
        child.receipt["tool_versions"] = execution.receipt["tool_versions"]
        child.save()
        try:
            result = function(child)
        except (AssertionError, OSError, ValueError, KeyError, TypeError) as exc:
            child.finish("failed", str(exc))
            raise
        (child.directory / "comparisons.json").write_text(json.dumps(result, indent=2)+"\n")
        child.finish("passed", "All group comparisons completed")
        return result

    with ThreadPoolExecutor(max_workers=4) as workers:
        futures = {workers.submit(run_one, name, function): name for name, function in groups.items()}
        for future in as_completed(futures):
            name = futures[future]
            try:
                results[name] = future.result()
            except (AssertionError, OSError, ValueError, KeyError, TypeError) as exc:
                failures[name] = str(exc)
            path = execution.directory / name / "receipt.json"
            execution.receipt.setdefault("group_receipts", {})[name] = dict(
                path=str(path.relative_to(ROOT)), sha256=sha(path))
            execution.save()
    require(not failures, f"behavior groups failed: {json.dumps(failures, sort_keys=True)}")
    require(set(results) == set(groups), "behavior group result missing")
    return results


def behavior(execution, probe=None):
    execution.tool("iverilog", ["-V"])
    execution.tool("vvp", ["-V"])
    ledger = dict(inventory=inventory_check())
    functions = {"vectors": primitive_vectors, "convolution": convolution_cases,
                 "attention": attention_cases, "subsystems": subsystem_cases,
                 "integrated": integrated_cases, "extended": extended_cases,
                 "errors": error_cases, "bridge": bridge_case, "official": official_cases,
                 "legacy": legacy_cases, "memory": memory_bridge_case}
    if probe == "infrastructure":
        execution.tool("yosys", ["-V"])
        ledger["parallel"] = run_groups(execution, {"memory": memory_bridge_case,
                                                   "vectors": primitive_vectors})
        (execution.directory / "comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
        return
    if probe is None:
        groups = {name: function for name, function in functions.items() if name != "extended"}
        for section in ("prefix", "audio", "protocol", "spatial"):
            groups["extended-"+section] = lambda child, selected=section: extended_cases(child, selected)
        ledger["baseline"] = run_groups(execution, groups)
        execution.receipt["baseline_passed_before_mutation"] = True
        execution.save()
        groups = {f"mutations-{i}": (lambda child, index=i: mutation_cases(child, (index, 4)))
                  for i in range(4)}
        ledger["mutations"] = run_groups(execution, groups)
        require(sum(len(result) for result in ledger["mutations"].values()) == 13,
                "mandatory mutation results missing")
        (execution.directory / "comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
        return
    for name, function in functions.items():
        if probe is None or probe == name:
            ledger[name] = function(execution)
            (execution.directory / "comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
    if probe == "mutations":
        for name, function in (
                ("vectors", primitive_vectors), ("convolution", convolution_cases),
                ("attention", attention_cases), ("bridge", bridge_case),
                ("framing", single_framing_case), ("hybrid", single_hybrid_case),
                ("prefix", single_prefix_case), ("memory", memory_bridge_case)):
            ledger[name] = function(execution)
            (execution.directory / "comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
    if probe == "mutations":
        ledger["mutations"] = mutation_cases(execution)
        (execution.directory / "comparisons.json").write_text(json.dumps(ledger, indent=2)+"\n")
    require(probe in functions or probe == "mutations", f"unimplemented probe: {probe}")


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", choices=("elaborate", "behavior", "synthesis"))
    group.add_argument("--probe", choices=("vectors", "convolution", "attention", "subsystems",
                                           "integrated", "extended", "errors", "bridge", "official",
                                           "legacy", "memory", "mutations", "infrastructure"))
    parser.add_argument("--repair-of", action="append", default=[])
    args = parser.parse_args()
    name = args.check or args.probe
    identifier = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    identifier += "-" + uuid.uuid4().hex[:8]
    if args.probe:
        directory = ROOT / "evidence/preparation" / f"verifier-{name}-{identifier}"
    else:
        label = "elaboration" if args.check == "elaborate" else args.check
        directory = ROOT / "evidence/verification" / label / identifier
    execution = Execution(directory, f"Independent verifier {name}")
    try:
        if args.repair_of:
            repairs = []
            for relative in args.repair_of:
                path = (ROOT / relative).resolve()
                require(path.is_relative_to(ROOT / "evidence/preparation"),
                        "repair linkage must identify a project preparation receipt")
                repairs.append(dict(path=str(path.relative_to(ROOT)), sha256=sha(path)))
            execution.receipt["repairs"] = repairs
            execution.save()
        if args.check == "elaborate":
            elaborate(execution)
        elif args.check == "synthesis":
            synthesis(execution)
        else:
            behavior(execution, args.probe)
    except (AssertionError, OSError, ValueError, KeyError, TypeError) as exc:
        execution.finish("failed", str(exc))
        print(f"FAIL: {exc}", file=sys.stderr)
        print(f"Receipt: {directory.relative_to(ROOT)}/receipt.json", file=sys.stderr)
        return 1
    execution.finish("passed", "All comparisons in this bounded invocation completed")
    print(f"Receipt: {directory.relative_to(ROOT)}/receipt.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
