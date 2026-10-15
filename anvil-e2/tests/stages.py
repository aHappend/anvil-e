"""Focused public-stage tests derived from memory layouts and tensor arithmetic."""
import dataclasses
import math
import random

from model import (Q, ONE, Integer, materialize, clamp40, rnd,
                   WEIGHTS, VISION, IMAGE, IDS, POSITIONS, MASKS, SCRATCH,
                   CONFIGS, LEGACY_RMS_EPSILON_Q80, OFFICIAL_RMS_EPSILON_Q80)


def execute_stage(run, name, module, parameters, descriptors, memory, expected,
                  expected_reads=None, fast=False):
    from verify import rtl_files
    memory_path = run.directory/(name+".mem")
    memory_path.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                                   for a, v in sorted(memory.items())))
    expected_path = run.directory/(name+".expected")
    expected_path.write_text("".join(f"{a:016x} {v & 0xffffffff:08x}\n"
                                     for a, v in expected.items()))
    ports = ["clk", "rst_n", "start_valid", "start_ready", "cmd_valid", "cmd_ready",
             "cmd_write", "cmd_addr", "cmd_wdata", "result_valid", "result_ready",
             "result_data", "result_error", "done_valid", "done_ready", "done_error"]
    overrides = ",".join(f".{k}({v})" for k, v in parameters.items())
    connections = ",".join([f".{p}({p})" for p in ports] +
                           [f".{p}({v})" for p, v in descriptors.items()])
    bench = f"""
module tb;
reg clk=0,rst_n=0,start_valid=0,cmd_ready=0,result_valid=0,result_error=0,done_ready=0;
always #5 clk=~clk;
reg [31:0] result_data=0;
wire start_ready,cmd_valid,cmd_write,result_ready,done_valid;
wire [63:0] cmd_addr;
wire [31:0] cmd_wdata;
wire [3:0] done_error;
{module} #({overrides}) dut ({connections});
reg [63:0] addresses[0:{len(memory)-1}];
reg [31:0] values[0:{len(memory)-1}];
reg [63:0] write_addresses[0:{len(expected)-1}];
reg [31:0] write_values[0:{len(expected)-1}];
integer fd,rc,n=0,cycles=0,lo,hi,mid,entry,i,j,wcount=0,reads=0,responses=0;
integer request_cycle=-1,response_cycle=-1,done_cycle=-1;
reg pending=0,active=0,held=0,held_done=0;
reg [96:0] payload;
task automatic known;
begin
 if ((^{{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}})===1'bx)
  $fatal(1,"STAGE_UNKNOWN");
 if(!rst_n && {{start_ready,cmd_valid,cmd_write,cmd_addr,cmd_wdata,result_ready,done_valid,done_error}}!=='0)
  $fatal(1,"STAGE_RESET");
end
endtask
initial begin
 fd=$fopen("{memory_path}","r"); if(fd==0) $fatal(1,"STAGE_INPUT");
 while(!$feof(fd)) begin
  rc=$fscanf(fd,"%h %h\\n",addresses[n],values[n]);
  if(rc==2) n=n+1;
  else if(!(rc==0 && $feof(fd)) && rc!=-1) $fatal(1,"STAGE_INPUT_FORMAT");
 end
 $fclose(fd); if(n!={len(memory)}) $fatal(1,"STAGE_INPUT_COUNT");
 fd=$fopen("{expected_path}","r"); if(fd==0) $fatal(1,"STAGE_EXPECTED_FILE");
 for(i=0;i<{len(expected)};i=i+1) begin
  rc=$fscanf(fd,"%h %h\\n",write_addresses[i],write_values[i]);
  if(rc!=2) $fatal(1,"STAGE_EXPECTED_FORMAT");
 end
 $fclose(fd);
 #1; known(); #11; rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>4000000) $fatal(1,"STAGE_TIMEOUT");
  start_valid=!active;
  cmd_ready={"1" if fast else "cycles%7>=3"};
  result_valid=pending && cycles>=response_cycle;
  if(done_valid && done_cycle<0) done_cycle=cycles;
  done_ready=done_cycle>=0 && cycles>done_cycle+20;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(held && (!cmd_valid || {{cmd_write,cmd_addr,cmd_wdata}}!==payload)) $fatal(1,"STAGE_STALL");
  held=cmd_valid && !cmd_ready; payload={{cmd_write,cmd_addr,cmd_wdata}};
  if(held_done && (!done_valid || done_error!==0)) $fatal(1,"STAGE_DONE_STALL");
  held_done=done_valid && !done_ready;
  if(start_valid && start_ready) begin if(active) $fatal(1,"STAGE_DUPLICATE"); active=1; end
  if(result_valid && result_ready) begin
   if(!pending || cycles<=request_cycle) $fatal(1,"STAGE_RESPONSE");
   pending=0; responses=responses+1;
  end
  if(cmd_valid && cmd_ready) begin
   if(pending || !active || cmd_addr[1:0]!==0) $fatal(1,"STAGE_REQUEST");
   pending=1; request_cycle=cycles; response_cycle=cycles+{"1" if fast else "2+reads%3"}; result_data=0;
   if(cmd_write) begin
    if(wcount>={len(expected)}) $fatal(1,"STAGE_EXCESS_WRITE");
    if(cmd_addr!==write_addresses[wcount] || cmd_wdata!==write_values[wcount])
     $fatal(1,"STAGE_WRITE_VALUE %h %h",cmd_addr,cmd_wdata);
    wcount=wcount+1;
    $display("W %h %h",cmd_addr,cmd_wdata);
   end else begin
    lo=0; hi=n-1; entry=-1;
    while(lo<=hi) begin
     mid=(lo+hi)/2;
     if(addresses[mid]==cmd_addr) begin entry=mid; lo=hi+1; end
     else if(addresses[mid]<cmd_addr) lo=mid+1;
     else hi=mid-1;
    end
    if(entry<0) $fatal(1,"STAGE_READ_ADDRESS %h",cmd_addr);
    result_data=values[entry]; reads=reads+1;
    $display("R %h",cmd_addr);
   end
  end
  if(done_valid && done_ready) begin
   if(done_error!==0 || pending || wcount!={len(expected)} || reads==0 ||
      responses!=reads+wcount || cycles<=done_cycle+20) $fatal(1,"STAGE_COMPLETION");
   $display("STAGE_COMPLETE %0d %0d %0d",reads,wcount,responses); $finish;
  end
 end
end
endmodule
"""
    tb = run.directory/(name+".sv")
    tb.write_text(bench)
    executable = run.directory/(name+".vvp")
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 *rtl_files(), tb], name+"-compile", timeout=20)
    out, _, _ = run.command(["vvp", executable], name+"-simulate", timeout=35)
    assert out.count("STAGE_COMPLETE ") == 1, "incomplete stage transcript"
    actual_reads = [int(line.split()[1], 16) for line in out.splitlines()
                    if line.startswith("R ")]
    if expected_reads is not None:
        assert actual_reads == expected_reads, "stage read ordering/address mismatch"
    actual_writes = [line for line in out.splitlines() if line.startswith("W ")]
    assert len(actual_writes) == len(expected), "stage output shape"
    run.receipt["coverage"].append({"case": name, "parameters": parameters,
                                    "compared_writes": len(expected),
                                    "compared_reads": len(actual_reads)})
    run.save()


def fusion280(run):
    h, s, n = 3, 280, 285
    offsets = {"ids": SCRATCH, "positions": SCRATCH+4*n,
               "masks": SCRATCH+8*n, "x": SCRATCH+12*n}
    soft_base = IMAGE
    memory, expected, reads = {}, {}, []
    ids = [7, 19, 31]
    positions, masks = [2, 9, 21], [1, 0, 1]
    for base, values in ((IDS, ids), (POSITIONS, positions), (MASKS, masks)):
        memory.update({base+4*i: v for i, v in enumerate(values)})
    for token in [255999, 258882]+ids:
        memory.update({WEIGHTS+4*(token*h+j): (token % 13-6)*(j+1)*Q//19
                       for j in range(h)})
    memory.update({soft_base+4*(i*h+j): (i % 23-11)*(j+1)*Q//37
                   for i in range(s) for j in range(h)})
    sequence = [255999]+[258880]*s+[258882]+ids
    for i, token in enumerate(sequence):
        supplied = i>=s+2
        if supplied:
            k = i-s-2
            reads.extend([IDS+4*k, POSITIONS+4*k, MASKS+4*k])
        expected[offsets["ids"]+4*i] = token
        expected[offsets["positions"]+4*i] = positions[i-s-2]+s+2 if supplied else i
        expected[offsets["masks"]+4*i] = masks[i-s-2] if supplied else 1
        for j in range(h):
            address = soft_base+4*((i-1)*h+j) if 0<i<=s else WEIGHTS+4*(token*h+j)
            reads.append(address)
            expected[offsets["x"]+4*(i*h+j)] = (
                memory[address] if 0<i<=s else materialize(
                    Integer().fusion_scale([Integer().decode(memory[address])], h)[0]))
    execute_stage(run, "fusion280", "anvil_e2_multimodal_fusion",
                  {"TEXT_HIDDEN": h, "VISION_SOFT_TOKENS": s}, {
                      "mode": "2'd2", "text_tokens": "32'd3", "weights": f"64'h{WEIGHTS:x}",
                      "token_ids": f"64'h{IDS:x}", "positions": f"64'h{POSITIONS:x}",
                      "masks": f"64'h{MASKS:x}", "soft_base": f"64'h{soft_base:x}",
                      "fused_ids": f"64'h{offsets['ids']:x}",
                      "fused_positions": f"64'h{offsets['positions']:x}",
                      "fused_masks": f"64'h{offsets['masks']:x}",
                      "x0_base": f"64'h{offsets['x']:x}", "valid_tokens": ""}, memory, expected, reads)


def patch(run, size=16, rows=1, cols=2, position_size=10240):
    h = 1 if cols==10240 else 4
    memory, expected, reads = {}, {}, []
    height, width = rows*size, cols*size
    for i in range(3*height*width):
        memory[IMAGE+4*i] = ((i*17)%41-20)*Q//43
    w = [[((r*13+j*7)%29-14)*Q//103 for j in range(3*size*size)]
         for r in range(h)]
    for r in range(h):
        for j, value in enumerate(w[r]):
            memory[VISION+4*(r*3*size*size+j)] = value
    pos_base = VISION+4*h*3*size*size
    for r in range(rows):
        for j in range(h):
            memory[pos_base+4*(r*h+j)] = ((r+j)%11-5)*Q//31
    for col in range(cols):
        for j in range(h):
            memory[pos_base+4*((position_size+col)*h+j)] = ((col*3-j)%13-6)*Q//37
    for r in range(rows):
        for col in range(cols):
            addresses = [IMAGE+4*(c*height*width+(r*size+dy)*width+col*size+dx)
                         for c in range(3) for dy in range(size) for dx in range(size)]
            ops = Integer()
            vector = ops.mat([[ops.decode(v) for v in row] for row in w],
                             [ops.decode(memory[a]) for a in addresses])
            for j, value in enumerate(vector):
                reads.extend(a for pair in zip(addresses, [
                    VISION+4*(j*3*size*size+k) for k in range(3*size*size)]) for a in pair)
                rp, cp = pos_base+4*(r*h+j), pos_base+4*((position_size+col)*h+j)
                reads.extend([rp, cp])
                expected[SCRATCH+4*((r*cols+col)*h+j)] = materialize(ops.add(
                    ops.add(value, ops.decode(memory[rp])), ops.decode(memory[cp])))
    execute_stage(run, f"patch{size}-grid{rows}x{cols}", "anvil_e2_vision_patch_embed",
                  {"VISION_HIDDEN": h, "PATCH_SIZE": size, "POSITION_EMBEDDING_SIZE": position_size},
                  {"patch_rows": f"32'd{rows}", "patch_cols": f"32'd{cols}",
                   "weights": f"64'h{VISION:x}", "image": f"64'h{IMAGE:x}",
                   "output_base": f"64'h{SCRATCH:x}"}, memory, expected, reads,
                  fast=cols==10240)


def focused(run):
    fusion280(run)
    patch(run)
    # Full published position-table extent, final legal column 10239.
    patch(run, size=1, rows=1, cols=10240)


def extremes(run):
    maximum, minimum = 2147483647, -2147483648
    vector = [maximum, minimum, Q//2]
    weights = [[maximum, minimum, Q], [minimum, maximum, -Q],
               [Q, Q, 1], [Q, Q, -1]]
    row_positions = [maximum, minimum, 0, 0]
    column_positions = [0, 0, 0, 0]
    ops = Integer()
    projected = ops.mat([[ops.decode(v) for v in row] for row in weights],
                        [ops.decode(v) for v in vector])
    assert projected[:2] == [maximum << 16, minimum << 16], "both saturation limits required"
    assert projected[2:] == [-(1 << 15), -3*(1 << 15)], "guarded cancellation required"
    assert [materialize(v) for v in projected[2:]] == [0, -2], "signed nearest-even ties"
    memory = {IMAGE+4*i: v for i, v in enumerate(vector)}
    memory.update({VISION+4*(r*3+j): v
                   for r, row in enumerate(weights) for j, v in enumerate(row)})
    memory.update({VISION+4*(12+j): v for j, v in enumerate(row_positions)})
    memory.update({VISION+4*(16+j): v for j, v in enumerate(column_positions)})
    expected = {SCRATCH+4*i: materialize(ops.add(ops.add(v, ops.decode(row_positions[i])),
                                               ops.decode(column_positions[i])))
                for i, v in enumerate(projected)}
    reads = []
    for r in range(4):
        for j in range(3):
            reads.extend([IMAGE+4*j, VISION+4*(r*3+j)])
        reads.extend([VISION+4*(12+r), VISION+4*(16+r)])
    execute_stage(run, "extreme-saturation-and-ties", "anvil_e2_vision_patch_embed",
                  {"VISION_HIDDEN": 4, "PATCH_SIZE": 1, "POSITION_EMBEDDING_SIZE": 1},
                  {"patch_rows": "32'd1", "patch_cols": "32'd1",
                   "weights": f"64'h{VISION:x}", "image": f"64'h{IMAGE:x}",
                   "output_base": f"64'h{SCRATCH:x}"}, memory, expected, reads)
    run.receipt["assertions"].append({
        "integer_extremes": "positive/negative matrix and residual saturation; "
                            "cancellation and positive/negative nearest-even ties",
        "projected_q40": projected, "expected_q24": list(expected.values()),
    })
    run.save()


def guard_boundaries(run):
    """Analytical boundary assertions independent of a particular RTL operator."""
    ops = Integer()
    for q in (-2147483648, -16777217, -1, 0, 1, 16777217, 2147483647):
        assert ops.decode(q) == q*65536
        assert materialize(ops.decode(q)) == q
        assert ops.boundary(ops.decode(q)) == ops.decode(q)
    for n, expected in ((-5, -2), (-3, -2), (-1, 0),
                        (1, 0), (3, 2), (5, 2)):
        assert materialize(n*32768) == expected
    low, high = -2147483648 << 16, 2147483647 << 16
    assert clamp40(low-1) == low and clamp40(high+1) == high
    assert ops.add(high, 1) == high and ops.add(low, -1) == low
    assert ops.norm([0, 0]) == [0, 0]
    assert ops.norm([0], [0]) == [0]
    a = ops.decode(Q)
    denominator = math.isqrt((a*a + (17 << 56)) << 64)
    assert ops.norm([a], [0]) == [clamp40(rnd(a << 72, denominator))]
    assert (65535*(low*low)).bit_length() <= 128
    assert (((1 << 32)-1)*(low*low)).bit_length() <= 128
    run.receipt["assertions"].append({
        "guard_precision": "exact promotion/materialization, signed ties, saturation, "
                           "zero L2, RMS epsilon17<<56, 16/32-bit reduction bounds",
        "activation_fraction_bits": 40, "external_fraction_bits": 24,
    })
    run.save()


def rms_epsilon(run):
    """Exact rational conversion and observed epsilon-independent L2 results."""
    from verify import parameter_value, parameter_args, parameter_items
    quotient, remainder = divmod(1 << 80, 1000000)
    expected = quotient + int(2*remainder > 1000000 or
                              (2*remainder == 1000000 and quotient % 2))
    assert expected == OFFICIAL_RMS_EPSILON_Q80 == 1208925819614629175
    assert LEGACY_RMS_EPSILON_Q80 == 1224979098644774912 == 17 << 56
    assert all(c.RMS_EPSILON_Q80 == LEGACY_RMS_EPSILON_Q80 for c in CONFIGS.values())
    assert parameter_value("RMS_EPSILON_Q80", expected) == "128'd1208925819614629175"
    official_config = dataclasses.replace(CONFIGS["A"], RMS_EPSILON_Q80=expected)
    assert all(k != "RMS_EPSILON_Q80" for k, _ in parameter_items(CONFIGS["A"]))
    assert "-Panvil_e2_top.RMS_EPSILON_Q80=128'd1208925819614629175" in parameter_args(
        official_config)
    legacy = guarded_norm(run)
    official = guarded_norm(run, epsilon=expected)
    l2_pairs = [(a, b) for a, b in zip(legacy, official) if a["l2"]]
    assert l2_pairs and all(a["actual_q40"] == b["actual_q40"] for a, b in l2_pairs)
    assert any(a["actual_q40"] != b["actual_q40"]
               for a, b in zip(legacy, official) if not a["l2"]), "inert RMS parameter"
    run.receipt["assertions"].append({
        "rms_epsilon_conversion": {"numerator": 1 << 80, "denominator": 1000000,
                                   "quotient": quotient, "remainder": remainder,
                                   "nearest_even": expected},
        "legacy_default_q80": LEGACY_RMS_EPSILON_Q80,
        "official_override_q80": expected,
        "l2_vectors_identical_across_parameters": len(l2_pairs),
        "rms_parameter_observably_changes_results": True,
    })
    run.save()


def guarded_norm(run, diagnostic=False, epsilon=None):
    """Public streaming RMS/L2 with independent guarded expected operands."""
    from verify import rtl_files, parameter_value
    selected = LEGACY_RMS_EPSILON_Q80 if epsilon is None else epsilon
    ops = Integer(selected)
    results = []
    cases = [
        ([ops.decode(Q//3), ops.decode(-Q//2), ops.decode(Q//7), ops.decode(-Q//11)],
         [ops.decode(Q//17), ops.decode(-Q//19), 0, ops.decode(Q//23)], False),
        ([0, 0, 0, 0], [0]*4, True),
        ([(-2147483648 << 16), (2147483647 << 16), 1, -1], [0]*4, True),
    ]
    # Square-root groups consume sixteen radicand bits; cross each reachable
    # small-bank boundary with exact squares and adjacent nonsquares.
    for bit in (0, 7, 8, 15, 16, 23, 24, 31, 32, 39, 40, 46):
        value = 1 << bit
        cases.append(([value], [0], True))
        cases.append(([-value, 1, value-1], [0]*3, True))
    cases.extend([
        ([0], [0], True),
        ([0], [0], False),
        ([1, -1], [ops.decode(-Q), ops.decode(Q)], False),
        ([(-2147483648 << 16)], [0], True),
        ([(2147483647 << 16)]*4, [0]*4, True),
        ([(-2147483648 << 16)]*4, [0]*4, True),
    ])
    covered_groups = set()
    for case, (values, weights, l2) in enumerate(cases):
        expected = ops.norm(values, None if l2 else weights)
        count = len(values)
        square_sum = sum(v*v for v in values)
        denominator_square = square_sum if l2 else rnd(square_sum, count)+selected
        root_groups = ((denominator_square.bit_length()+64+15)//16
                       if denominator_square else 0)
        loads = "\n".join(
            f"values[{i}]=48'h{v & ((1 << 48)-1):012x}; "
            f"weights[{i}]=32'h{(w >> 16) & 0xffffffff:08x}; "
            f"expected[{i}]=48'h{e & ((1 << 48)-1):012x};"
            for i, (v, w, e) in enumerate(zip(values, weights, expected)))
        text = f"""
module tb #(parameter logic [127:0] RMS_EPSILON_Q80 = (128'd17 << 56));
reg clk=0,rst_n=0,start_valid=0,in_valid=0,out_ready=0;
always #5 clk=~clk;
wire start_ready,in_ready,out_valid,out_last,out_error;
wire signed [47:0] out_data;
wire [31:0] out_index;
reg signed [47:0] in_data=0;
reg signed [31:0] in_weight=0;
reg signed [47:0] values[0:3],expected[0:3];
reg signed [31:0] weights[0:3];
integer cycles=0,loaded=0,beats=0,stalls=0,output_wait=0;
reg started=0,held=0;
reg [81:0] payload;
anvil_e2_norm #(.MAX_WIDTH(4){",.RMS_EPSILON_Q80(RMS_EPSILON_Q80)" if epsilon is not None else ""}) dut(
 .clk(clk),.rst_n(rst_n),.start_valid(start_valid),.start_ready(start_ready),
 .start_count(32'd{count}),.start_l2(1'b{int(l2)}),.in_valid(in_valid),.in_ready(in_ready),
 .in_data(in_data),.in_weight(in_weight),.out_valid(out_valid),.out_ready(out_ready),
 .out_data(out_data),.out_index(out_index),.out_last(out_last),.out_error(out_error));
task automatic known;
begin
 if ((^{{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}})===1'bx)
  $fatal(1,"NORM_UNKNOWN");
 if (!rst_n && {{start_ready,in_ready,out_valid,out_data,out_index,out_last,out_error}}!=='0)
  $fatal(1,"NORM_RESET");
end
endtask
initial begin
 {loads}
 #0;known();#1;known();#11;rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1; if(cycles>1000) $fatal(1,"NORM_TIMEOUT");
  start_valid=!started;
  in_valid=started && loaded<{count};
  if(loaded<{count}) begin in_data=values[loaded];in_weight=weights[loaded];end
  if(out_valid && output_wait<4) output_wait=output_wait+1;
  out_ready=output_wait>=4 && cycles%5==0;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(start_valid && start_ready) started=1;
  if(in_valid && in_ready) loaded=loaded+1;
  if(held && (!out_valid || {{out_data,out_index,out_last,out_error}}!==payload))
   $fatal(1,"NORM_STABILITY");
  held=out_valid && !out_ready;
  payload={{out_data,out_index,out_last,out_error}};
  if(held) stalls=stalls+1;
  if(out_valid && out_ready) begin
   if(beats>={count} || out_index!==32'(beats) || out_data!==expected[beats] ||
      out_last!==(beats=={count-1}) || out_error!==0) $fatal(1,"NORM_MISMATCH");
   $display("N %0d %h",out_index,out_data); beats=beats+1;
   if(beats=={count}) begin
    if(loaded!={count} || stalls==0) $fatal(1,"NORM_COVERAGE");
    $display("NORM_COMPLETE {count} %0d",stalls);$finish;
   end
  end
 end
end
endmodule
"""
        if diagnostic:
            text = text.replace("endmodule", """
always @(posedge clk) begin
 $display("NORM_PUBLIC cycle=%0d start=%b/%b in=%b/%b out=%b/%b index=%0d data=%h",
          cycles,start_valid,start_ready,in_valid,in_ready,out_valid,out_ready,out_index,out_data);
 $fflush();
end
endmodule
""")
        name = f"guarded-norm-{case}" if epsilon is None else f"guarded-norm-e{epsilon}-{case}"
        tb, executable = run.directory/(name+".sv"), run.directory/(name+".vvp")
        tb.write_text(text)
        overrides = ([] if epsilon is None else
                     [f"-Ptb.RMS_EPSILON_Q80={parameter_value('RMS_EPSILON_Q80', epsilon)}"])
        run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable, *overrides,
                     *rtl_files(), tb], name+"-compile", timeout=5)
        out, _, _ = run.command(["vvp", executable], name+"-simulate", timeout=5)
        assert out.count("NORM_COMPLETE ") == 1
        actual = [int(line.split()[2], 16) for line in out.splitlines() if line.startswith("N ")]
        assert actual == [v & ((1 << 48)-1) for v in expected]
        result = {
            "case": name, "input_q40": values, "weights_q24": [w >> 16 for w in weights],
            "expected_q40": expected, "compared_components": count, "l2": l2,
            "denominator_square": denominator_square, "root_groups": root_groups,
            "rms_epsilon_q80": selected, "actual_q40": actual,
            "selection": "RTL default (no override)" if epsilon is None else "explicit unsigned128",
        }
        run.receipt["coverage"].append(result)
        results.append(result)
        covered_groups.add(root_groups)
        run.save()
    assert covered_groups == {0, 5, 6, 7, 8, 9, 10, 11}, "norm root group coverage"
    run.receipt["assertions"].append({
        "guarded_root_groups": sorted(covered_groups),
        "compared_vectors": len(cases),
        "root_group_12": "unreachable: legal 65535-term Q40 square sums have at most 110 bits",
    })
    run.save()
    return results


def guarded_nonlinear(run):
    """Check the six public operators against independent integer equations."""
    from model import exp40, trig40, PI, TWO_PI, LN2
    from verify import rtl_files
    rng = random.Random(170891)
    low, high = -2147483648 << 16, 2147483647 << 16
    boundaries = [low, high, -8*ONE-1, -8*ONE, -8*ONE+1,
                  -ONE, -1, 0, 1, ONE, 8*ONE-1, 8*ONE, 8*ONE+1]
    cases = []
    for operation in range(8):
        values = list(boundaries)
        if operation == 0:
            values += [-16*ONE-1, -16*ONE, -16*ONE+1]
            values += [-i*LN2+j for i in range(1, 24) for j in (-1, 0, 1)]
        if operation in (1, 2):
            values += [a+j for a in (-TWO_PI, -PI, PI, TWO_PI)
                       for j in (-1, 0, 1)]
        values += [rng.randint(low, high) for _ in range(24)]
        if operation == 5:
            values += [rng.randint(-8*ONE+1, 8*ONE-1) for _ in range(64)]
        for value in dict.fromkeys(values):
            error = (operation > 5 or operation == 0 and value > 0 or
                     operation == 3 and value == 0 or operation == 4 and value <= 0)
            if error:
                expected = 0
            elif operation == 0:
                expected = clamp40(exp40(value))
            elif operation in (1, 2):
                expected = trig40(value, cosine=operation == 2)
            elif operation == 3:
                expected = clamp40(rnd(1 << 80, value))
            elif operation == 4:
                expected = clamp40(rnd(1 << 88, math.isqrt(value << 56)))
            else:
                expected = Integer().gelu(value)
            cases.append((operation, value, expected, int(error)))
    loads = "\n".join(
        f"ops[{i}]=3'd{op}; inputs[{i}]=48'h{value & ((1 << 48)-1):012x}; "
        f"expected[{i}]=48'h{expected & ((1 << 48)-1):012x}; errors[{i}]=1'b{error};"
        for i, (op, value, expected, error) in enumerate(cases))
    text = f"""
module tb;
reg clk=0,rst_n=0,in_valid=0,out_ready=0;
always #5 clk=~clk;
reg [2:0] in_op=0;
reg signed [47:0] in_data=0;
wire in_ready,out_valid,out_error;
wire signed [47:0] out_data;
anvil_e2_nonlinear dut(.*);
reg [2:0] ops[0:{len(cases)-1}];
reg signed [47:0] inputs[0:{len(cases)-1}],expected[0:{len(cases)-1}];
reg errors[0:{len(cases)-1}];
integer i,j,waits,compared=0,stalls=0,cancellations=0,cycles=0;
task automatic known;
begin
 if ((^{{in_ready,out_valid,out_data,out_error}})===1'bx)
  $fatal(1,"NONLINEAR_UNKNOWN");
 if(!rst_n && {{in_ready,out_valid,out_data,out_error}}!=='0)
  $fatal(1,"NONLINEAR_RESET");
end
endtask
always @(posedge clk) begin
 known();
 cycles=cycles+1;
 if(cycles>1000000) $fatal(1,"NONLINEAR_TIMEOUT");
end
always @(negedge clk) known();
task automatic launch(input [2:0] op,input signed [47:0] value);
begin
 @(negedge clk); in_op=op; in_data=value; in_valid=1;
 @(posedge clk);
 if(in_ready!==1 || out_valid!==0) $fatal(1,"NONLINEAR_INPUT_OWNERSHIP");
 #1; in_valid=0;
 if(in_ready!==0) $fatal(1,"NONLINEAR_PREMATURE_READY");
end
endtask
task automatic await_result;
begin
 waits=0;
 @(negedge clk);
 while(!out_valid) begin
  if(in_ready!==0) $fatal(1,"NONLINEAR_LOST_OWNERSHIP");
  waits=waits+1; if(waits>1000) $fatal(1,"NONLINEAR_RESULT_TIMEOUT");
  @(negedge clk);
 end
end
endtask
task automatic cancel;
begin
 #1;rst_n=0; #1;known();
 #11;rst_n=1;
 repeat(120) begin
  @(posedge clk);known();
  if(out_valid!==0 || in_ready!==1) $fatal(1,"NONLINEAR_CANCELED_WORK");
 end
 cancellations=cancellations+1;
end
endtask
initial begin
 {loads}
 #0;known(); #1;known(); #11;rst_n=1;
 for(i=0;i<{len(cases)};i=i+1) begin
  launch(ops[i],inputs[i]);
  await_result();
  for(j=0;j<5;j=j+1) begin
   @(posedge clk);
   if(out_valid!==1 || out_data!==expected[i] || out_error!==errors[i] ||
      in_ready!==0)
    $fatal(1,"NONLINEAR_MISMATCH case=%0d op=%0d x=%h actual=%h expected=%h error=%b/%b",
           i,ops[i],inputs[i],out_data,expected[i],out_error,errors[i]);
   stalls=stalls+1;
   @(negedge clk);
  end
  out_ready=1;
  @(posedge clk);
  if(out_valid!==1) $fatal(1,"NONLINEAR_MISSING_TRANSFER");
  $display("NONLINEAR_RESULT %0d %h %b",i,out_data,out_error);
  compared=compared+1;
  #1;
  if(out_valid!==0 || in_ready!==1) $fatal(1,"NONLINEAR_RETIREMENT");
  @(negedge clk);out_ready=0;
 end
 launch(3'd5,48'sd1429365116109);
 @(negedge clk);
 if(out_valid!==0) $fatal(1,"NONLINEAR_PENDING_RESET_PRECONDITION");
 cancel();
 launch(3'd3,48'sd1);
 await_result();
 if(out_ready!==0) $fatal(1,"NONLINEAR_STALLED_RESET_PRECONDITION");
 cancel();
 if(compared!={len(cases)} || stalls!=5*compared || cancellations!=2)
  $fatal(1,"NONLINEAR_COVERAGE");
 $display("NONLINEAR_COMPLETE %0d %0d %0d",compared,stalls,cancellations);
 $finish;
end
endmodule
"""
    tb = run.directory/"guarded-nonlinear.sv"
    executable = run.directory/"guarded-nonlinear.vvp"
    tb.write_text(text)
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 *rtl_files(), tb], "guarded-nonlinear-compile", timeout=5)
    out, _, _ = run.command(["vvp", executable], "guarded-nonlinear-simulate", timeout=10)
    actual = [line.split() for line in out.splitlines()
              if line.startswith("NONLINEAR_RESULT ")]
    assert len(actual) == len(cases)
    for index, (row, (_, _, expected, error)) in enumerate(zip(actual, cases)):
        assert row == ["NONLINEAR_RESULT", str(index),
                       f"{expected & ((1 << 48)-1):012x}", str(error)]
    assert f"NONLINEAR_COMPLETE {len(cases)} {5*len(cases)} 2" in out
    run.receipt["coverage"].append({
        "case": "guarded-nonlinear", "random_seed": 170891,
        "compared_results": len(cases), "stalled_output_edges": 5*len(cases),
        "reset_cancellations": 2,
        "boundaries": "all six operators, invalid opcodes/domains, signed endpoints, "
                      "zero shortcuts, exp tail/LN2, trig wrapping, GELU +/-8, "
                      "reciprocal/rsqrt saturation, pending and held-output reset",
        "operands": [{"op": op, "input_q40": value, "expected_q40": expected,
                      "expected_error": error} for op, value, expected, error in cases],
    })
    run.save()


def guarded_division_diagnostic(run):
    """Distinguish simulator wide-division cost from norm sequencing."""
    values = [Integer().decode(Q//3), Integer().decode(-Q//2),
              Integer().decode(Q//7), Integer().decode(-Q//11)]
    square = rnd(sum(v*v for v in values), len(values)) + (17 << 56)
    divisor = math.isqrt(square << 64)
    numerator = values[0] << 72
    expected = numerator//divisor
    tb = run.directory/"division.sv"
    executable = run.directory/"division.vvp"
    tb.write_text(f"""
module tb;
reg signed [127:0] numerator=128'h{numerator:032x};
reg signed [127:0] divisor=128'h{divisor:032x};
reg signed [127:0] quotient;
initial begin
 $display("DIVISION_INPUT %h %h",numerator,divisor);$fflush();
 quotient=numerator/divisor;
 if(quotient!==128'h{expected:032x}) $fatal(1,"DIVISION_MISMATCH");
 $display("DIVISION_COMPLETE %h",quotient);$finish;
end
endmodule
""")
    run.receipt["assertions"].append({
        "diagnostic_only": "native signed128 division on independent RMS operands",
        "numerator": numerator, "divisor": divisor, "expected_floor_quotient": expected,
    })
    run.save()
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable, tb],
                "division-compile", timeout=5)
    out, _, _ = run.command(["vvp", executable], "division-simulate", timeout=5)
    assert out.count("DIVISION_COMPLETE ") == 1


def guarded_divider(run):
    """Exact public-pin signed numerator / unsigned denominator contract."""
    from verify import rtl_files
    low, high = -(1 << 127), (1 << 127)-1
    cases = [(0, 1), (1, 2), (-1, 2), (3, 2), (-3, 2),
             (5, 2), (-5, 2), (7, 2), (-7, 2),
             (low, 1), (high, 1), (low, 2), (high, 2),
             (low, (1 << 128)-1), (high, (1 << 128)-1),
             (low, 1 << 127), (high, 1 << 127), (0, 0), (high, 0)]
    values = [Integer().decode(Q//3), Integer().decode(-Q//2),
              Integer().decode(Q//7), Integer().decode(-Q//11)]
    root = math.isqrt((rnd(sum(v*v for v in values), 4)+(17 << 56)) << 64)
    cases.extend((v << 72, root) for v in values)
    cases.extend(((1 << i)-1, (1 << (i//2))+1) for i in (32, 64, 96, 127))
    # Exercise exact shortcuts and every quotient-prefix boundary.
    for shift in (0, 1, 2, 40, 41, 43, 63, 64, 95, 126, 127):
        divisor = 1 << shift
        for numerator in (0, 1, divisor//2, divisor//2+1,
                          divisor-1, divisor, divisor+1, high, -high, low):
            if low <= numerator <= high:
                cases.append((numerator, divisor))
                if numerator != low:
                    cases.append((-numerator, divisor))
    for bits in range(1, 129):
        numerator = (1 << (bits-1)) if bits < 128 else 1 << 127
        for delta in (-1, 0, 1):
            magnitude = numerator+delta
            if 0 <= magnitude <= 1 << 127:
                for divisor in (3, 5, 17, (1 << min(bits, 127))-1):
                    if divisor:
                        if magnitude <= high:
                            cases.append((magnitude, divisor))
                        cases.append((-magnitude, divisor))
    rng = random.Random(17089)
    for _ in range(128):
        numerator = rng.randrange(low, high+1)
        denominator = rng.randrange(1, 1 << rng.randrange(1, 129))
        cases.append((numerator, denominator))
    digit_boundaries = []
    for bits in (48, 49, 64, 80, 111, 127, 128):
        shift = max(0, bits-48)
        divisor = ((1 << 47)+1) << shift
        divisor += (1 << shift)-1
        for magnitude in (divisor-1, divisor, divisor+1, 1 << 127):
            if magnitude <= 1 << 127:
                cases.append((-magnitude, divisor))
                if magnitude <= high:
                    cases.append((magnitude, divisor))
        if bits <= 111:
            for quotient, residue in ((65535, divisor-1), (65535, 0),
                                      (65536, 0), (65537, 1)):
                magnitude = quotient*divisor+residue
                assert magnitude <= high
                cases.extend(((magnitude, divisor), (-magnitude, divisor)))
                digit_boundaries.append({
                    "divisor_bits": bits, "quotient": quotient,
                    "residue": residue, "numerator": magnitude,
                })
    correction_example = next(
        item for item in digit_boundaries
        if item["divisor_bits"] == 80 and item["residue"] > 0)
    # An analytical adversary for the leading-word estimate, not an oracle:
    # the exact expected result below still comes exclusively from Python RN.
    divisor = ((1 << 47)+1)*(1 << 32)+(1 << 32)-1
    trial = divisor*65536-1
    estimate = (trial >> 32)//(divisor >> 32)
    assert estimate == 65536 and trial//divisor == 65535
    assert correction_example["numerator"] == trial
    cases = list(dict.fromkeys(cases))
    assignments = []
    expected = []
    for i, (n, d) in enumerate(cases):
        result = rnd(n, d) if d else 0
        error = not d or not low <= result <= high
        result = 0 if error else result
        expected.append({"numerator": n, "denominator": d,
                         "expected": result, "error": bool(error)})
        assignments.append(
            f"numerators[{i}]=128'h{n & ((1 << 128)-1):032x};"
            f"denominators[{i}]=128'h{d:032x};"
            f"expected[{i}]=128'h{result & ((1 << 128)-1):032x};"
            f"errors[{i}]=1'b{int(error)};")
    text = f"""
module tb;
reg clk=0,rst_n=0,in_valid=0,out_ready=0;
always #5 clk=~clk;
reg signed [127:0] in_numerator=0;
reg [127:0] in_denominator=0;
wire in_ready,out_valid,out_error;
wire signed [127:0] out_data;
anvil_e2_divide dut(.*);
reg signed [127:0] numerators[0:{len(cases)-1}],expected[0:{len(cases)-1}];
reg [127:0] denominators[0:{len(cases)-1}];
reg errors[0:{len(cases)-1}];
integer sent=0,received=0,cycles=0,stalls=0;
reg held=0;
reg [128:0] payload;
task automatic known;
begin
 if ((^{{in_ready,out_valid,out_data,out_error}})===1'bx) $fatal(1,"DIVIDER_UNKNOWN");
 if (!rst_n && {{in_ready,out_valid,out_data,out_error}}!=='0) $fatal(1,"DIVIDER_RESET");
end
endtask
initial begin
 {''.join(assignments)}
 #0;known();#1;known();#11;rst_n=1;
end
always @(negedge clk) begin
 known();
 if(rst_n) begin
  cycles=cycles+1;if(cycles>{len(cases)*48}) $fatal(1,"DIVIDER_TIMEOUT");
  in_valid=sent<{len(cases)};
  if(in_valid) begin in_numerator=numerators[sent];in_denominator=denominators[sent];end
  out_ready=cycles%11==0;
 end
end
always @(posedge clk) begin
 known();
 if(rst_n) begin
  if(in_valid && in_ready) sent=sent+1;
  if(held && (!out_valid || {{out_error,out_data}}!==payload)) $fatal(1,"DIVIDER_STABILITY");
  held=out_valid && !out_ready;payload={{out_error,out_data}};
  if(held) stalls=stalls+1;
  if(out_valid && out_ready) begin
   if(received>=sent || out_data!==expected[received] || out_error!==errors[received])
    $fatal(1,"DIVIDER_MISMATCH case=%0d data=%h error=%b",received,out_data,out_error);
   $display("DIVIDER_RESULT %0d %h %b",received,out_data,out_error);
   received=received+1;
   if(received=={len(cases)}) begin
    if(sent!={len(cases)} || stalls==0) $fatal(1,"DIVIDER_COVERAGE");
    $display("DIVIDER_COMPLETE %0d %0d",received,stalls);$finish;
   end
  end
 end
end
endmodule
"""
    tb, executable = run.directory/"guarded-divider.sv", run.directory/"guarded-divider.vvp"
    tb.write_text(text)
    run.command(["iverilog", "-g2012", "-Wall", "-s", "tb", "-o", executable,
                 *rtl_files(), tb], "guarded-divider-compile", timeout=5)
    out, _, _ = run.command(["vvp", executable], "guarded-divider-simulate", timeout=5)
    assert out.count("DIVIDER_COMPLETE ") == 1
    assert out.count("DIVIDER_RESULT ") == len(cases)
    run.receipt["coverage"].append({
        "case": "guarded-divider", "compared_results": len(cases), "operands": expected,
        "boundaries": "signed128 extrema, unsigned128 divisors, signed ties, "
                      "zero divisor, exact guarded RMS ratios, output stalls, "
                      "power-of-two shortcuts, all quotient-prefix lengths",
        "random_seed": 17089,
        "digit_boundaries": digit_boundaries,
        "candidate_65536_correction": {
            "numerator": trial, "denominator": divisor,
            "leading_estimate": estimate, "exact_floor": trial//divisor,
        },
        "divisor_128_bits": "covered via magnitude-smaller/power-of-two paths; "
                            "nonpower divisors exceed every signed128 magnitude",
    })
    run.save()
