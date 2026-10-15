"""Primitive acceptance against independent mathematical functions."""
import json
import math
import re
from fractions import Fraction
from pathlib import Path

Q = 1 << 24


def verify_primitives(execution):
    cases = []
    def add(op, x, error=0, category="accuracy"):
        value = min(2147483647, max(-2147483648, round(x * Q)))
        cases.append((len(cases), op, value, error, category))
    for i in range(513):
        add(0, -16 * i / 512)
        add(5, -8 + 16 * i / 512)
    for i in range(513):
        x = -128 + (256 - 1 / Q) * i / 512
        add(1, x)
        add(2, x)
    for x in (1/Q, 2/Q, 17/Q, 0.0001, 0.01, 0.1, 0.5, 1, 3, 7,
              31, 64, 127, 128-1/Q):
        add(3, x, category="saturation" if 1/x >= 128 else "accuracy")
        add(3, -x, category="saturation" if 1/x > 128 else "accuracy")
        add(4, x, category="saturation" if 1/math.sqrt(x) >= 128 else "accuracy")
    for op, x in ((0,1), (3,0), (4,0), (4,-1), (6,1), (7,1)):
        add(op,x,1,"domain")
    for x in (-128,-20,-8.01,8.01,20,127):
        add(5,x,category="saturation")
    path = execution.output / "primitive-input.txt"
    path.write_text("".join(f"{i} {op} {v} {err}\n" for i,op,v,err,_ in cases))
    binary = execution.output / "primitives.vvp"
    execution.run("primitive-compile", ["iverilog","-g2012","-s","primitives",
                  "-o",str(binary),"tests/primitives.sv","rtl/anvil_e1_nonlinear.sv"])
    trace = execution.run("primitive-simulation", ["vvp",str(binary),f"+input={path}"])
    results = {}
    complete = None
    for line in trace.read_text().splitlines():
        fields = line.split()
        if fields and fields[0] == "RESULT":
            if len(fields) != 4 or any(c in fields[2].lower() for c in "xz"):
                raise AssertionError("primitive malformed/XZ result")
            tag, value, error = map(int,fields[1:])
            if tag in results:
                raise AssertionError(f"duplicate primitive result {tag}")
            results[tag] = (value,error)
        elif fields and fields[0] == "COMPLETE":
            if complete is not None:
                raise AssertionError("duplicate completion")
            complete = int(fields[1])
        elif re.fullmatch(r"tests/primitives\.sv:\d+: \$finish called at \d+ \([^)]+\)", line):
            pass
        elif fields:
            raise AssertionError(f"unexpected simulator diagnostic: {line}")
    if complete != len(cases) or set(results) != set(range(len(cases))):
        raise AssertionError("missing primitive transactions")
    maxima = {str(op):0.0 for op in range(6)}
    ledger = []
    failures = []
    for tag,op,value,error,category in cases:
        observed,status = results[tag]
        if status != error:
            raise AssertionError(f"primitive status mismatch {tag}")
        if error:
            if observed != 0:
                raise AssertionError(f"error result not zero {tag}")
            ledger.append({"tag":tag,"op":op,"category":category,"status":"passed"})
            continue
        x=value/Q
        expected = (math.exp(max(x,-16)) if op==0 else math.sin(x) if op==1
                    else math.cos(x) if op==2 else 1/x if op==3
                    else 1/math.sqrt(x) if op==4 else
                    x*0.5*(1+math.tanh(math.sqrt(2/math.pi)*(x+0.044715*x**3))))
        saturated = min((Q*128-1)/Q,max(-128,expected))
        absolute = abs(observed/Q-saturated)
        metric = absolute/abs(expected) if op in (3,4) and category=="accuracy" else absolute
        limit = 2e-6 if op==0 else 2e-5 if op in (1,2) else 2e-4
        if category=="saturation" and op in (3,4):
            limit=0
        maxima[str(op)]=max(maxima[str(op)],metric)
        passed=metric<=limit
        ledger.append({"tag":tag,"op":op,"input_q24":value,"observed_q24":observed,
                       "expected_real":expected,"metric":metric,"threshold":limit,
                       "category":category,"status":"passed" if passed else "failed"})
        if not passed:
            failures.append(ledger[-1])
    (execution.output/"primitive-comparisons.json").write_text(json.dumps(
        {"cases":ledger,"max_errors":maxima,"failures":failures},indent=2)+"\n")
    if failures:
        raise AssertionError(f"primitive accuracy failure: {failures[0]}")
    verify_norm(execution)


def verify_norm(execution):
    """Public-pin RMS/L2 checks; expectations do not use model.py or DUT internals."""
    epsilon = round(Fraction(2**48, 10**6))
    if epsilon != 281474977 or epsilon == 17*Q:
        raise AssertionError("incorrect independently derived Q48 epsilon")
    cases = []
    for values in ([0], [0]*4, [1], [-1], [1, 0], [3, 0],
                   [1, 2], [1, -2, 3], [17, -17, 31, -31],
                   [16777, -16777, 8388, -8388],
                   [1, -2, 3, -4, 5, -6], [0]*16,
                   [2147483647, -2147483648, Q]):
        for l2 in (False, True):
            weights = [(i % 4 - 1)*Q//4 for i in range(len(values))]
            cases.append({"values":values, "weights":weights, "l2":l2,
                          "count":len(values)})
    for count in (0, 17):
        cases.append({"values":[], "weights":[], "l2":False, "count":count})

    def expected(case, eps):
        values = case["values"]
        if not values:
            return [(0, 0, 1, 1)]
        squares = sum(v*v for v in values)
        denominator = squares if case["l2"] else round(Fraction(squares, len(values)))+eps
        root = math.isqrt(denominator*2**64)
        result = []
        for i, (value, weight) in enumerate(zip(values, case["weights"])):
            normalized = round(Fraction(value*2**56, root)) if root else 0
            weighted = normalized if case["l2"] else round(
                Fraction(normalized*(Q+weight), Q))
            result.append((i, min(2**31-1, max(-2**31, weighted)),
                           int(i == len(values)-1), 0))
        return result

    path = execution.output/"norm-input.txt"
    path.write_text("".join(
        f"{tag} {int(case['l2'])} {case['count']}\n"+
        "".join(f"{v} {w}\n" for v, w in zip(case["values"], case["weights"]))
        for tag, case in enumerate(cases)))
    binary = execution.output/"norm.vvp"
    execution.run("norm-compile", ["iverilog", "-g2012", "-Wall", "-s", "norm",
                  "-o", str(binary), "tests/norm.sv", "rtl/anvil_e1_norm.sv"])
    trace = execution.run("norm-simulation", ["vvp", str(binary), f"+input={path}"])
    observed = {tag:[] for tag in range(len(cases))}
    completed = False
    next_tag = 0
    for line in trace.read_text().splitlines():
        fields = line.split()
        if fields and fields[0] == "NORM" and len(fields) == 6 and not completed:
            tag, index, data, last, error = map(int, fields[1:])
            if tag != next_tag:
                raise AssertionError("out-of-order normalization transaction")
            observed[tag].append((index, data, last, error))
            if last == 1:
                next_tag += 1
        elif fields == ["COMPLETE", str(len(cases))] and not completed:
            if next_tag != len(cases):
                raise AssertionError("incomplete normalization transactions")
            completed = True
        elif re.fullmatch(r"tests/norm\.sv:\d+: \$finish called at \d+ \([^)]+\)", line):
            pass
        elif fields:
            raise AssertionError(f"unexpected normalization diagnostic: {line}")
    if not completed:
        raise AssertionError("missing normalization completion")
    ledger = []
    discriminating = 0
    failures = []
    for tag, case in enumerate(cases):
        wanted = expected(case, epsilon)
        historical = expected(case, 17*Q)
        distinguishes = wanted != historical
        discriminating += distinguishes
        row = {"tag":tag, **case, "expected":wanted, "observed":observed[tag],
               "historical_q824_first_expected":historical,
               "distinguishes_epsilon":distinguishes,
               "status":"passed" if observed[tag] == wanted else "failed"}
        ledger.append(row)
        if observed[tag] != wanted:
            failures.append(row)
    (execution.output/"norm-comparisons.json").write_text(json.dumps({
        "epsilon_q48":epsilon, "epsilon_derivation":"round(Fraction(2**48, 10**6))",
        "expected_entrypoint":"primitives.verify_norm.expected; no Designer/model imports",
        "cases":ledger, "discriminating_rms_cases":discriminating,
        "failures":failures}, indent=2)+"\n")
    if failures or discriminating < 6:
        raise AssertionError(f"normalization contract failure: {failures or discriminating}")
