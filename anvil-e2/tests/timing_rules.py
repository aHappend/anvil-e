"""Source-level sequential assignment checks, paired with synthesized-cell checks."""
import re


def tokens(source):
    cleaned = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',
                     lambda match: " " * len(match.group()), source, flags=re.S)
    return list(re.finditer(
        r"\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*|<=|>=|==|!=|=>|\+\+|--|"
        r"[+\-*/%&|^]=|[^\s]", cleaned))


def clocked_blocking_assignments(source):
    lexemes = tokens(source)
    text = [token.group() for token in lexemes]

    def balanced(index, opening="(", closing=")"):
        assert text[index] == opening, f"expected {opening}, got {text[index]}"
        depth = 1
        index += 1
        while index < len(text) and depth:
            depth += (text[index] == opening) - (text[index] == closing)
            index += 1
        assert depth == 0, "unterminated RTL expression"
        return index

    def statement(index):
        kind = text[index]
        if kind == "begin":
            index += 1
            if text[index] == ":":
                index += 2
            while text[index] != "end":
                index = statement(index)
            return index + 1
        if kind == "if":
            index = statement(balanced(index + 1))
            return statement(index + 1) if index < len(text) and text[index] == "else" else index
        if kind in ("case", "casez", "casex"):
            index = balanced(index + 1)
            while text[index] != "endcase":
                while text[index] != ":":
                    index = balanced(index) if text[index] == "(" else index + 1
                index = statement(index + 1)
            return index + 1
        if kind in ("for", "while", "repeat"):
            return statement(balanced(index + 1))
        if kind == "forever":
            return statement(index + 1)
        while text[index] != ";":
            index = balanced(index) if text[index] == "(" else index + 1
        return index + 1

    failures, processes = [], 0
    for index, kind in enumerate(text):
        if kind not in ("always", "always_ff"):
            continue
        begin = index + 1
        assert text[begin] == "@", "unsupported RTL always sensitivity"
        begin += 1
        if text[begin] == "(":
            end_sensitivity = balanced(begin)
        else:
            end_sensitivity = begin + 1
        sensitivity = text[begin:end_sensitivity]
        if kind != "always_ff" and not {"posedge", "negedge"}.intersection(sensitivity):
            continue
        processes += 1
        end = statement(end_sensitivity)
        for item in lexemes[end_sensitivity:end]:
            if item.group() in ("=", "+=", "-=", "*=", "/=", "%=", "&=", "|=",
                                "^=", "++", "--"):
                failures.append(source.count("\n", 0, item.start()) + 1)
    # Tasks execute in the caller's process. Reject blocking assignments there
    # too, rather than letting a clocked task hide a register update.
    for index, kind in enumerate(text):
        if kind == "task":
            end = text.index("endtask", index + 1)
            for item in lexemes[index + 1:end]:
                if item.group() in ("=", "+=", "-=", "*=", "/=", "%=", "&=", "|=",
                                    "^=", "++", "--"):
                    failures.append(source.count("\n", 0, item.start()) + 1)
    return processes, sorted(set(failures))


def check_clocked_sources(run, paths):
    from verify import ROOT
    examples = (
        ("always @(posedge clk) begin q<=d; end", False),
        ("always @(posedge clk) begin q=d; q<=d; end", True),
        ("always_ff @(posedge clk or negedge rst_n) if(!rst_n) q<=0; else q=d;", True),
        ("always @(posedge clk) case(s) 0:begin q<=d; end default:q=d; endcase", True),
        ("always @* begin q=d; end", False),
        ("function automatic f; input a; begin f=a; end endfunction\n"
         "always @(posedge clk) begin q<=f(d); end", False),
        ("always @(posedge clk) begin q<=d; end\n"
         "task automatic update; begin q=d; end endtask", True),
    )
    for source, reject in examples:
        assert bool(clocked_blocking_assignments(source)[1]) == reject, (
            "sequential-assignment checker sensitivity failure")
    records = []
    for path in paths:
        source = path.read_text()
        processes, failures = clocked_blocking_assignments(source)
        records.append({"file": str(path.relative_to(ROOT)),
                        "clocked_processes": processes,
                        "blocking_assignment_lines": failures})
    run.receipt["clocked_assignment_checks"] = records
    run.save()
    assert sum(record["clocked_processes"] for record in records) > 0
    assert not any(record["blocking_assignment_lines"] for record in records), (
        f"blocking assignment in clocked RTL/task: {records}")
