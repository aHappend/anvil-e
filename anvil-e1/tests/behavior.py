"""Public-interface simulation, independent comparisons and trace mutation."""
import hashlib
from bisect import bisect_left
import json
import math
import random
import re
import time
from pathlib import Path

from model import CONFIGS, Q, forward, forward_details, inventory
from primitives import verify_primitives


class ExactMismatch(AssertionError):
    def __init__(self, job, index, expected, observed):
        self.job, self.index = job, index
        self.expected, self.observed = expected, observed
        super().__init__(f"EXACT_DATA_MISMATCH job={job} index={index} "
                         f"expected={expected} observed={observed}")


def compare_trace(path, jobs, g, require_coverage=False):
    events = []
    completion = None
    records = {j["id"]: {"embeddings": [], "done": [], "abort": [],
                         "requests": [], "responses": [], "started": 0}
               for j in jobs}
    outstanding = None
    active = None
    last_cycle = -1
    coverage = None
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        fields = line.split()
        if not fields:
            continue
        kind = fields[0]
        lengths = {"JOB": 3, "REQ": 6, "RSP": 5, "EMB": 6,
                   "DONE": 4, "ABORT": 3, "COMPLETE": 2, "COVER": 17}
        if kind not in lengths:
            if re.fullmatch(r"tests/forward\.sv:\d+: \$finish called at \d+ \([^)]+\)",line):
                continue
            raise AssertionError(f"unexpected trace diagnostic line {lineno}: {line}")
        if len(fields) != lengths[kind]:
            raise AssertionError(f"malformed {kind} at line {lineno}")
        values = list(map(int, fields[1:]))
        events.append((lineno,kind,values))
        if kind == "COVER":
            if coverage is not None or active is not None:
                raise AssertionError("duplicate/premature coverage")
            coverage = values
            continue
        if kind == "COMPLETE":
            if completion is not None:
                raise AssertionError("duplicate COMPLETE")
            completion = values[0]
            if active is not None or outstanding is not None:
                raise AssertionError("completion with active ownership")
            continue
        jid = values[0]
        if jid not in records:
            raise AssertionError(f"unknown job {jid}")
        rec = records[jid]
        cycle = values[1]
        if cycle < last_cycle or completion is not None:
            raise AssertionError("out-of-order event or event after COMPLETE")
        last_cycle = cycle
        if kind == "JOB":
            if active is not None:
                raise AssertionError("new descriptor before retirement")
            active = jid
            rec["started"] += 1
            rec["job_edge"] = cycle
        elif active != jid:
            raise AssertionError("transaction outside active job")
        elif kind == "REQ":
            if outstanding is not None:
                raise AssertionError("multiple outstanding requests")
            outstanding = jid
            rec["requests"].append(values)
        elif kind == "RSP":
            if outstanding != jid:
                raise AssertionError("stale response")
            if cycle <= rec["requests"][-1][1]:
                raise AssertionError("zero-latency public response")
            outstanding = None
            rec["responses"].append(values)
        elif kind == "EMB":
            rec["embeddings"].append(values)
        elif kind == "DONE":
            if outstanding is not None:
                raise AssertionError("completion with outstanding memory")
            rec["done"].append(values)
            active = None
        elif kind == "ABORT":
            rec["abort"].append(values)
            outstanding = None
            active = None
    if completion != len(jobs) or outstanding is not None:
        raise AssertionError("incomplete trace or unretired request")
    if require_coverage and (coverage is None or any(v<=0 for v in coverage)):
        raise AssertionError(f"unobserved required protocol/operation coverage: {coverage}")
    ledger = []
    for job in jobs:
        rec = records[job["id"]]
        if rec["started"] != 1:
            raise AssertionError("missing/duplicate descriptor acceptance")
        if job["reset"]:
            if len(rec["abort"]) != 1 or rec["done"]:
                raise AssertionError("reset cancellation missing or completed")
            ledger.append({"job":job["id"],"status":"reset-aborted",
                           "retired_embeddings":len(rec["embeddings"])})
            continue
        if rec["abort"] or len(rec["done"]) != 1:
            raise AssertionError("missing/duplicate completion")
        if rec["done"][0][-1] != job["error"]:
            raise AssertionError(f"completion error job {job['id']}: "
                                 f"{rec['done'][0][-1]} expected {job['error']}")
        expected = job["fixed"]
        observed = rec["embeddings"]
        if len(observed) != len(expected):
            raise AssertionError(f"missing/duplicate output job {job['id']}")
        for i,(event,value) in enumerate(zip(observed,expected)):
            if event[2] != i or event[4] != int(i==len(expected)-1):
                raise AssertionError("embedding index/last mismatch")
            if event[3] != value:
                raise ExactMismatch(job["id"],i,value,event[3])
            if not -(1 << 31) <= event[3] < (1 << 31):
                raise AssertionError("embedding outside signed 32-bit domain")
        if observed and rec["done"][0][1] <= observed[-1][1]:
            raise AssertionError("completion retired before final embedding")
        result = {"job":job["id"],"status":"passed","output_words":len(expected),
                  "error":job["error"],"request_count":len(rec["requests"])}
        if expected:
            output = [v/Q for v in expected]
            reference = job["float"]
            norm = math.sqrt(sum(v*v for v in output))
            highnorm = math.sqrt(sum(v*v for v in reference))
            result["output_norm"] = norm
            if not job.get("official", False) and any(expected) and abs(norm-1)>0.002:
                raise AssertionError("output norm exceeds 0.002")
            if not job["saturation"] and not job.get("official", False):
                error = max(abs(v-r) for v,r in zip(output,reference))
                result["max_absolute_error"] = error
                if error>0.02:
                    raise AssertionError("high-precision output error exceeds 0.02")
                if highnorm:
                    cosine = sum(v*r for v,r in zip(output,reference))/(norm*highnorm)
                    result["cosine_similarity"] = cosine
                    if job["pre_norm"]>=0.01 and cosine<0.999:
                        raise AssertionError("cosine similarity below 0.999")
        ledger.append(result)
    return ledger, records, events


def fixtures(execution, config, seed, minimal=False, representative=False):
    g = CONFIGS[config]
    entries = inventory(g)
    rng = random.Random(seed)
    weights = {}
    saturation = {}
    image = {}
    for entry in entries:
        name, size = entry["name"], entry["size_bytes"]//4
        if name.endswith("layer_scalar"):
            values = [Q + rng.randrange(-Q//32,Q//32)]
        elif "norm.weight" in name or "layernorm.weight" in name:
            values = [rng.randrange(-Q//16,Q//16) for _ in range(size)]
        else:
            values = [rng.randrange(-Q//8,Q//8) for _ in range(size)]
        weights[name] = values
        saturation[name] = [(1<<31)-1 if i%3 else -(1<<31)
                            for i in range(size)]
        for base, packed in ((0x1000,values),(0x40000,saturation[name]),
                             (0x60000,[0]*size)):
            for i,value in enumerate(packed):
                image[(base+entry["offset_bytes"])//4+i] = value & 0xffffffff
    zero = {n:[0]*len(v) for n,v in weights.items()}
    jobs = []
    def add(n=1, dim=None, masks=None, error=0, fault=-1, reset=0,
            mode="normal", change=None):
        jid = len(jobs)
        dim = g.E if dim is None else dim
        ids = [(3*t+1)%g.V for t in range(n)]
        positions = [(t+1)%g.S for t in range(n)]
        masks = [1]*n if masks is None else masks
        bases = [0x20000+jid*128,0x24000+jid*128,0x28000+jid*128]
        for base, data in zip(bases,(ids,positions,masks)):
            for i,value in enumerate(data):
                image[base//4+i] = value
        wb, chosen = (0x60000,zero) if mode=="zero" else (
            (0x40000,saturation) if mode=="saturation" else (0x1000,weights))
        job = {"id":jid,"n":n,"dim":dim,"wb":wb,"bases":bases,
               "scratch":0x80000,"error":error,"fault":fault,"reset":reset,
               "fixed":[],"float":[],"pre_norm":0,"saturation":mode=="saturation"}
        if not error and not reset:
            job["fixed"] = forward(g,chosen,ids,positions,masks,dim,True)
            if mode != "saturation":
                job["float"], job["pre_norm"] = forward_details(
                    g,chosen,ids,positions,masks,dim,False)
        if change:
            change(job,image)
        jobs.append(job)
    add(n=g.S if representative else 1,
        masks=[int(t%3!=1) for t in range(g.S)] if representative else None)
    if representative:
        minimal = True
    if not minimal:
        # Directed scenarios are distributed across seeds, not removed; each
        # run still executes every legal dimension and independent fixture data.
        add(n=g.S if seed==17 else 1,dim=2*g.E//3,
            masks=[int(t%3!=1) for t in range(g.S)] if seed==17 else None)
        add(n=2 if seed==89 else 1,dim=g.E//3,
            masks=[1,0] if seed==89 else None)
        add(n=1,dim=g.E//6)
        if seed==89:
            add(mode="zero")
            add(mode="saturation")
        add(n=g.S,masks=[0]*g.S,error=4)
        add(n=0,error=1)
        add(dim=3*g.E,error=1)
        add(error=1,change=lambda j,m:j.update(wb=0x1001))
        add(error=5,change=lambda j,m:j.update(scratch=0xfffffffffffffffc))
        for field,bad in ((0,g.V),(1,g.S),(2,2)):
            add(error=2,change=lambda j,m,f=field,b=bad:
                m.update({j["bases"][f]//4:b}))
        add(n=2,masks=[1,0],error=2,change=lambda j,m:
            m.update({j["bases"][0]//4+1:g.V}))
        add(error=3,fault=0)
        add(error=3,fault=3)
        if seed==203:
            for reset in (1,2,3):
                add(reset=reset)
            add()
    prefix = execution.output/f"{config}-{seed}"
    image_path = Path(str(prefix)+".hex")
    image_path.write_text("".join(f"@{addr:x}\n{value:08x}\n"
                                  for addr,value in sorted(image.items())))
    job_path = Path(str(prefix)+".jobs")
    job_path.write_text("".join(
        f"{j['id']} {j['n']} {j['dim']} {j['wb']:x} "
        f"{j['bases'][0]:x} {j['bases'][1]:x} {j['bases'][2]:x} "
        f"{j['scratch']:x} {j['fault']} {j['reset']}\n" for j in jobs))
    Path(str(prefix)+".expected.json").write_text(json.dumps(jobs,indent=2)+"\n")
    return image_path,job_path,jobs


def run_cost_probe(execution):
    binary = compile_forward(execution,"B")
    image,jobs_path,jobs = fixtures(execution,"B",17,representative=True)
    trace = execution.run("B-17-simulation",["vvp",str(binary),
        f"+image={image}",f"+jobs={jobs_path}","+seed=17"])
    ledger,_,_ = compare_trace(trace,jobs,CONFIGS["B"])
    (execution.output/"comparisons.json").write_text(json.dumps(ledger,indent=2)+"\n")
    negative_control(execution,trace,jobs,CONFIGS["B"])


def pooled_norm(g,weights,ids,positions,masks,dim):
    from model import forward_details
    return forward_details(g,weights,ids,positions,masks,dim,False)[1]


def compile_forward(execution, config, wrapper=False, profile=False):
    g = CONFIGS[config]
    tag = config + ("-official" if wrapper else "")
    binary = execution.output/f"{tag}.vvp"
    execution.run("compile-"+tag,["iverilog","-g2012"]+
        (["-DOFFICIAL_WRAPPER"] if wrapper else [])+
        (["-DINTERNAL_PROFILE"] if profile else [])+["-s","forward",
        "-o",str(binary)]+[f"-Pforward.{n}={v}" for n,v in g.parameters().items()]+
        ["tests/forward.sv"]+[str(p) for p in sorted(Path("rtl").glob("*.sv"))])
    return binary


def negative_control(execution, trace, jobs, g):
    directory = execution.output/"negative_control"
    directory.mkdir()
    clean_ledger,_,_ = compare_trace(trace,jobs,g)
    original = trace.read_text()
    lines = original.splitlines()
    selected = next(i for i,l in enumerate(lines) if l.startswith("EMB "))
    fields = lines[selected].split()
    before = int(fields[4])
    after = before+1 if before < (1<<31)-1 else before-1
    fields[4] = str(after)
    lines[selected] = " ".join(fields)
    altered = directory/"altered.trace"
    altered.write_text("\n".join(lines)+"\n")
    summary = {"original_trace":str(trace),
        "original_sha256":hashlib.sha256(original.encode()).hexdigest(),
        "altered_trace":str(altered),"line":selected+1,
        "job":int(fields[1]),"index":int(fields[3]),
        "before":before,"after":after,
        "entrypoint":"behavior.compare_trace(path, jobs, geometry)"}
    (directory/"unchanged-comparisons.json").write_text(json.dumps(clean_ledger,indent=2)+"\n")
    (directory/"unchanged.trace").write_text(original)
    (directory/"expected.json").write_text(json.dumps(jobs,indent=2)+"\n")
    summary["unchanged_status"] = "passed"
    try:
        compare_trace(altered,jobs,g)
    except ExactMismatch as error:
        if (error.job,error.index,error.expected,error.observed) != (
                summary["job"],summary["index"],before,after):
            raise AssertionError("negative control rejected at unintended transaction")
        (directory/"diagnostics.log").write_text(str(error)+"\n")
        summary["status"] = "specific-exact-mismatch-rejected"
    else:
        raise AssertionError("negative control incorrectly accepted")
    (directory/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")


def run_forward_probe(execution):
    binary = compile_forward(execution,"A")
    image,jobs_path,jobs = fixtures(execution,"A",17,minimal=True)
    trace = execution.run("A-17-simulation",["vvp",str(binary),
        f"+image={image}",f"+jobs={jobs_path}","+seed=17"],maximum=30)
    ledger,_,_ = compare_trace(trace,jobs,CONFIGS["A"])
    (execution.output/"comparisons.json").write_text(json.dumps(ledger,indent=2)+"\n")


def run_integration_probe(execution, configs, seeds):
    run_matrix(execution, configs, seeds)


def verify_behavior(execution,configs,seeds):
    if configs != ["A","B","C"] or seeds != [17,89,203]:
        raise ValueError("behavior requires unchanged nine-run matrix")
    verify_primitives(execution)
    run_matrix(execution, configs, seeds)


def run_matrix(execution, configs, seeds):
    ledger = []
    planned = [{"config":config,"seed":seed,"status":"not-run"}
               for config in configs for seed in seeds]
    def save_runs():
        (execution.output/"run-ledger.json").write_text(
            json.dumps(planned,indent=2)+"\n")
    save_runs()
    control = None
    for config in configs:
        binary = compile_forward(execution,config)
        coverage_totals = [0]*16
        for seed in seeds:
            execution.remaining()
            run = next(r for r in planned
                       if r["config"]==config and r["seed"]==seed)
            run["status"] = "fixture-reference"
            save_runs()
            started = time.monotonic()
            image,jobs_path,jobs = fixtures(execution,config,seed)
            fixture_s = time.monotonic() - started
            run["fixture_reference_s"] = fixture_s
            run["status"] = "simulation"
            save_runs()
            execution.remaining()
            started = time.monotonic()
            try:
                trace = execution.run(f"{config}-{seed}-simulation",["vvp",str(binary),
                    f"+image={image}",f"+jobs={jobs_path}",f"+seed={seed}"])
            except (AssertionError, RuntimeError, TimeoutError, OSError) as error:
                run["status"] = "failed"
                run["detail"] = f"{type(error).__name__}: {error}"
                raise
            finally:
                simulation_s = time.monotonic() - started
                run["simulation_s"] = simulation_s
                save_runs()
            started = time.monotonic()
            run["status"] = "scoreboard-coverage"
            save_runs()
            execution.remaining()
            results,records,events = compare_trace(trace,jobs,CONFIGS[config])
            observed = [values for _,kind,values in events if kind=="COVER"]
            if len(observed)!=1:
                raise AssertionError("missing observed public protocol coverage")
            coverage_totals = [a+b for a,b in zip(coverage_totals,observed[0])]
            successful = {j["id"] for j in jobs if j["error"] == 0 and not j["reset"]}
            touched = sorted({r[3] for jid, rec in records.items() if jid in successful
                              for r in rec["requests"]
                              if r[2]==0})
            touched_set = set(touched)
            for entry in inventory(CONFIGS[config]):
                begin = 0x1000+entry["offset_bytes"]
                index = bisect_left(touched, begin)
                if index == len(touched) or touched[index] >= begin+entry["size_bytes"]:
                    raise AssertionError("missing tensor execution "+entry["name"])
                if not entry["name"].endswith("embed_tokens.weight"):
                    if any(address not in touched_set for address in
                           range(begin, begin+entry["size_bytes"], 4)):
                        raise AssertionError("incomplete coefficient execution "+entry["name"])
            ledger.append({"config":config,"seed":seed,"jobs":results,
                           "tensor_families_observed":len(inventory(CONFIGS[config])),
                           "operation_evidence": "Complete non-embedding coefficient reads in "
                           "successful jobs plus independent full-equation output comparisons; "
                           "nonzero-position RoPE and sliding/full layers included",
                           "full_layers_observed": [l for l in range(CONFIGS[config].L) if l%6==5],
                           "public_protocol_coverage": observed[0],
                           "trace":str(trace),"status":"passed",
                           "fixture_reference_s":fixture_s,
                           "simulation_s":simulation_s,
                           "simulation_cpu_user_s":execution.children[-1]["cpu_user_s"],
                           "simulation_cpu_system_s":execution.children[-1]["cpu_system_s"],
                           "simulation_cycles":max(values[1] for _,kind,values in events
                                                   if kind in ("REQ","RSP","EMB","DONE","ABORT")),
                           "public_transaction_events":len(events),
                           "trace_bytes":trace.stat().st_size,
                           "scoreboard_coverage_s":time.monotonic()-started})
            run.update(ledger[-1])
            save_runs()
            (execution.output/"matrix.json").write_text(json.dumps(ledger,indent=2)+"\n")
            if control is None:
                control = (trace,jobs,CONFIGS[config])
        if any(v<=0 for v in coverage_totals):
            raise AssertionError(f"{config}: missing required observed coverage {coverage_totals}")
        (execution.output/f"{config}-coverage.json").write_text(
            json.dumps(coverage_totals)+"\n")
    negative_control(execution,*control)
