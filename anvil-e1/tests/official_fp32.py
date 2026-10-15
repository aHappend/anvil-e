"""Raw-BF16 coefficient forward pass with explicit non-fused FP32 boundaries."""
import math
import struct


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def add(a, b):
    return f32(a + b)


def mul(a, b):
    return f32(a * b)


def div(a, b):
    return f32(a / b)


def reduce32(values):
    total = 0.0
    for value in values:
        total = add(total, value)
    return total


def matrix(w, x):
    return [reduce32(mul(a, b) for a, b in zip(w[i:i+len(x)], x))
            for i in range(0, len(w), len(x))]


def norm(x, w=None):
    squares = reduce32(mul(v, v) for v in x)
    denominator = f32(math.sqrt(add(div(squares, f32(len(x))), f32(1e-6))
                               if w is not None else squares))
    return [mul(div(v, denominator), add(1.0, w[i]) if w is not None else 1.0)
            if denominator else 0.0 for i, v in enumerate(x)]


def gelu(x):
    cubic = mul(mul(x, x), x)
    argument = mul(f32(math.sqrt(2/math.pi)), add(x, mul(f32(0.044715), cubic)))
    return mul(mul(x, 0.5), add(1.0, f32(math.tanh(argument))))


def rope(x, position, full):
    d = len(x)
    result = list(x)
    for i in range(d//2):
        frequency = f32((1000000.0 if full else 10000.0) ** div(f32(-2*i), f32(d)))
        angle = mul(f32(position), frequency)
        s, c = f32(math.sin(angle)), f32(math.cos(angle))
        result[i] = add(mul(x[i], c), -mul(x[i+d//2], s))
        result[i+d//2] = add(mul(x[i], s), mul(x[i+d//2], c))
    return result


def attention(q, keys, values, eligible):
    if not eligible:
        return [0.0]*len(q)
    scale = f32(math.sqrt(len(q)))
    scores = [div(reduce32(mul(a, b) for a, b in zip(q, keys[k])), scale)
              for k in eligible]
    maximum = max(scores)
    probabilities = [f32(math.exp(add(s, -maximum))) for s in scores]
    denominator = reduce32(probabilities)
    return [div(reduce32(mul(p, values[k][j]) for p, k in zip(probabilities, eligible)),
                denominator) for j in range(len(q))]


def forward_fp32(g, weights, ids, positions, masks, dim):
    if not any(masks):
        raise ValueError("all masked")
    if not all(0 <= i < g.V for i in ids):
        raise ValueError("invalid token")
    root = f32(math.sqrt(g.H))
    def global_(suffix):
        return weights["language_model."+suffix]
    x, ple = [], []
    diagnostics = []
    for token in ids:
        e = [mul(v, root) for v in global_("embed_tokens.weight")[token*g.H:(token+1)*g.H]]
        x.append(e)
        p = [div(v, root) for v in matrix(global_("ple.per_layer_model_projection.weight"), e)]
        ple.append([norm(p[l*g.P:(l+1)*g.P], global_("ple.per_layer_projection_norm.weight"))
                    for l in range(g.L)])
    for layer in range(g.L):
        full = layer % 6 == 5
        d, kv = (g.FD, g.FK) if full else (g.LD, g.LK)
        def w(suffix):
            return weights[f"language_model.layers.{layer}."+suffix]
        u = [norm(v, w("input_layernorm.weight")) for v in x]
        projected = {}
        for kind, heads in (("q", g.QH), ("k", kv), ("v", kv)):
            projected[kind] = []
            for t, vector in enumerate(matrix(w(f"self_attn.{kind}_proj.weight"), v) for v in u):
                groups = [vector[h*d:(h+1)*d] for h in range(heads)]
                if kind != "v":
                    groups = [rope(norm(v, w(f"self_attn.{kind}_norm.weight")), positions[t], full)
                              for v in groups]
                projected[kind].append(groups)
        result = []
        for t, current in enumerate(x):
            eligible = [k for k in range(len(ids)) if masks[k] and
                        (full or abs(positions[k]-positions[t]) < g.W)]
            heads = []
            for h in range(g.QH):
                kh = h//(g.QH//kv)
                heads += attention(projected["q"][t][h],
                    [v[kh] for v in projected["k"]], [v[kh] for v in projected["v"]], eligible)
            branch = norm(matrix(w("self_attn.o_proj.weight"), heads),
                          w("post_attention_layernorm.weight"))
            current = [add(a, b) for a, b in zip(current, branch)]
            u = norm(current, w("pre_feedforward_layernorm.weight"))
            gate = [gelu(v) for v in matrix(w("mlp.gate_proj.weight"), u)]
            up = matrix(w("mlp.up_proj.weight"), u)
            branch = norm(matrix(w("mlp.down_proj.weight"), [mul(a, b) for a, b in zip(gate, up)]),
                          w("post_feedforward_layernorm.weight"))
            current = [add(a, b) for a, b in zip(current, branch)]
            gate = [gelu(v) for v in matrix(w("ple_block.per_layer_input_gate.weight"), current)]
            branch = norm(matrix(w("ple_block.per_layer_projection.weight"),
                                 [mul(a, b) for a, b in zip(gate, ple[t][layer])]),
                          w("ple_block.post_per_layer_input_norm.weight"))
            result.append([mul(add(a, b), w("layer_scalar")[0]) for a, b in zip(current, branch)])
        x = result
        diagnostics.append({"layer": layer, "hidden": x})
    projected = [matrix(global_("embedding_projection.weight"), norm(v, global_("norm.weight")))
                 for v in x]
    means = [div(reduce32(v[j] for v, m in zip(projected, masks) if m), f32(sum(masks)))
             for j in range(dim)]
    return norm(means), {"layer_hidden": diagnostics, "pooled_prefix": means,
                         "pre_norm": math.sqrt(sum(v*v for v in means))}
