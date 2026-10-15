"""Independent equation-level float and integer operation-boundary references.

No design Python helpers or DUT state are used. Quantized weights are the common
inputs, not the expected activations. Fixed arithmetic follows ARCHITECTURE.md.
RMS epsilon is independently rounded directly to Q48; the quantized-input
mathematical path uses that exact rational value. L2 has no epsilon. Historical
epsilon-isolation callers must explicitly request their old 17/2^24 value.
"""
import math
from dataclasses import dataclass
from fractions import Fraction

Q = 1 << 24
F = 1 << 40
EPSILON_Q48 = round(Fraction(1 << 48, 1_000_000))
SATURATION_COUNT = 0


@dataclass(frozen=True)
class Geometry:
    V: int
    H: int
    P: int
    I: int
    E: int
    L: int
    QH: int
    LK: int
    FK: int
    LD: int
    FD: int
    W: int
    S: int

    def parameters(self):
        names = ("VOCAB_SIZE", "HIDDEN_SIZE", "PER_LAYER_INPUT_SIZE",
                 "INTERMEDIATE_SIZE", "EMBEDDING_DIM", "NUM_LAYERS",
                 "NUM_Q_HEADS", "LOCAL_KV_HEADS", "FULL_KV_HEADS",
                 "LOCAL_HEAD_DIM", "FULL_HEAD_DIM", "SLIDING_WINDOW",
                 "MAX_SEQ_LEN")
        return dict(zip(names, self.__dict__.values()))


CONFIGS = {
    "A": Geometry(16, 4, 4, 8, 6, 6, 2, 1, 1, 2, 4, 2, 8),
    "B": Geometry(20, 6, 4, 10, 12, 12, 4, 2, 1, 2, 4, 3, 8),
    "C": Geometry(16, 4, 4, 8, 6, 24, 4, 2, 1, 2, 4, 2, 4),
}


def inventory(g):
    globals_ = {
        "embed_tokens.weight": (g.V, g.H),
        "embedding_projection.weight": (g.E, g.H),
        "norm.weight": (g.H,),
        "ple.per_layer_model_projection.weight": (g.L * g.P, g.H),
        "ple.per_layer_projection_norm.weight": (g.P,),
    }
    entries = [("language_model." + n, s) for n, s in sorted(globals_.items())]
    for layer in range(g.L):
        d, kv = (g.FD, g.FK) if layer % 6 == 5 else (g.LD, g.LK)
        suffixes = {
            "input_layernorm.weight": (g.H,), "layer_scalar": (1,),
            "mlp.down_proj.weight": (g.H, g.I),
            "mlp.gate_proj.weight": (g.I, g.H),
            "mlp.up_proj.weight": (g.I, g.H),
            "ple_block.per_layer_input_gate.weight": (g.P, g.H),
            "ple_block.per_layer_projection.weight": (g.H, g.P),
            "ple_block.post_per_layer_input_norm.weight": (g.H,),
            "post_attention_layernorm.weight": (g.H,),
            "post_feedforward_layernorm.weight": (g.H,),
            "pre_feedforward_layernorm.weight": (g.H,),
            "self_attn.k_norm.weight": (d,),
            "self_attn.k_proj.weight": (kv * d, g.H),
            "self_attn.o_proj.weight": (g.H, g.QH * d),
            "self_attn.q_norm.weight": (d,),
            "self_attn.q_proj.weight": (g.QH * d, g.H),
            "self_attn.v_proj.weight": (kv * d, g.H),
        }
        entries += [(f"language_model.layers.{layer}." + n, s)
                    for n, s in sorted(suffixes.items())]
    offset = 0
    result = []
    for name, shape in entries:
        size = 4 * math.prod(shape)
        result.append({"name": name, "shape": list(shape), "offset_bytes": offset,
                       "size_bytes": size})
        offset += size
    return result


def nearest(n, d):
    if d <= 0:
        raise ValueError("nonpositive divisor")
    a, r = divmod(abs(n), d)
    a += 2 * r > d or (2 * r == d and a % 2 == 1)
    return -a if n < 0 else a


def sat(n):
    global SATURATION_COUNT
    SATURATION_COUNT += not (-(1 << 31) <= n < (1 << 31))
    return max(-(1 << 31), min((1 << 31) - 1, n))


def mul40(a, b):
    return nearest(a * b, F)


def exp40(x):
    ln2 = 762123384786
    exponent, residual = divmod(max(x, -16 * F), ln2)
    term = total = F
    for k in range(1, 19):
        term = nearest(mul40(term, residual), k)
        total += term
    return total >> -exponent


def nonlinear(op, x):
    if op == "exp":
        if x > 0:
            raise ValueError("positive exponential")
        return sat(nearest(exp40(x << 16), 1 << 16))
    if op == "gelu":
        if x >= 8 * Q:
            return x
        if x <= -8 * Q:
            return 0
        a = x << 16
        z = mul40(877283352226,
                  a + mul40(49164662436, mul40(mul40(a, a), a)))
        e = exp40(-2 * abs(z))
        t = nearest((F - e) * F, F + e)
        if x < 0:
            t = -t
        return sat(nearest(nearest(mul40(a, F + t), 2), 1 << 16))
    if op not in ("sin", "cos"):
        raise ValueError(op)
    period, pi = 6908435304715, 3454217652358
    a = (x << 16) % period
    if a > pi:
        a -= period
    term = total = a if op == "sin" else F
    for k in range(1, 19):
        divisor = 2*k*(2*k+1) if op == "sin" else (2*k-1)*2*k
        term = nearest(-mul40(mul40(term, a), a), divisor)
        total += term
    return sat(nearest(total, 1 << 16))


class Arithmetic:
    def __init__(self, fixed, floating_epsilon=EPSILON_Q48/(Q*Q)):
        self.fixed = fixed
        self.floating_epsilon = floating_epsilon

    def add(self, a, b):
        return sat(a+b) if self.fixed else a+b

    def product(self, a, b):
        return sat(nearest(a*b, Q)) if self.fixed else a*b

    def matrix(self, weights, x):
        n = len(x)
        sums = [sum(a*b for a, b in zip(weights[i:i+n], x))
                for i in range(0, len(weights), n)]
        return [sat(nearest(s, Q)) for s in sums] if self.fixed else sums

    def norm(self, x, weights=None):
        if self.fixed:
            squares = sum(a*a for a in x)
            square = squares if weights is None else nearest(squares, len(x)) + EPSILON_Q48
            root = math.isqrt(square << 64)
            normalized = [nearest(a << 56, root) if root else 0 for a in x]
            if weights is None:
                return [sat(a) for a in normalized]
            return [sat(nearest(a*(Q+w), Q)) for a, w in zip(normalized, weights)]
        divisor = math.sqrt(sum(a*a for a in x) /
                            (len(x) if weights is not None else 1) +
                            (self.floating_epsilon if weights is not None else 0))
        return [(a/divisor if divisor else 0) *
                (1+weights[i] if weights is not None else 1)
                for i, a in enumerate(x)]

    def gelu(self, x):
        return nonlinear("gelu", x) if self.fixed else (
            x/2*(1+math.tanh(math.sqrt(2/math.pi)*(x+0.044715*x**3))))

    def rope(self, x, position, full):
        d = len(x)
        result = list(x)
        for i in range(d//2):
            if self.fixed:
                logarithm = 15190314502144 if full else 10126876334763
                exponent = -nearest(logarithm*2*i, d)
                frequency = exp40(exponent)
                angle40 = frequency*position % 6908435304715
                if angle40 > 3454217652358:
                    angle40 -= 6908435304715
                angle = nearest(angle40, 1 << 16)
                s, c = nonlinear("sin", angle), nonlinear("cos", angle)
                result[i] = sat(nearest(x[i]*c-x[i+d//2]*s, Q))
                result[i+d//2] = sat(nearest(x[i]*s+x[i+d//2]*c, Q))
            else:
                angle = position*(1000000 if full else 10000)**(-2*i/d)
                s, c = math.sin(angle), math.cos(angle)
                result[i] = x[i]*c-x[i+d//2]*s
                result[i+d//2] = x[i]*s+x[i+d//2]*c
        return result

    def attention(self, query, keys, values, indices):
        if not indices:
            return [0]*len(query)
        if self.fixed:
            root = math.isqrt(len(query) << 80)
            scores = [sat(nearest(sum(a*b for a,b in zip(query, keys[t])) << 16,
                                  root)) for t in indices]
            maximum = max(scores)
            probs = [nonlinear("exp", s-maximum) if s-maximum >= -16*Q else 0
                     for s in scores]
            denom = sum(probs)
            return [sat(nearest(sum(p*values[t][j] for p,t in zip(probs, indices)),
                                denom)) for j in range(len(query))]
        scores = [sum(a*b for a,b in zip(query, keys[t])) / math.sqrt(len(query))
                  for t in indices]
        maximum = max(scores)
        probs = [math.exp(s-maximum) for s in scores]
        return [sum(p*values[t][j] for p,t in zip(probs,indices))/sum(probs)
                for j in range(len(query))]


def forward_details(g, quantized_weights, ids, positions, masks, output_dim, fixed,
                    diagnostics=None, raw_weights=None,
                    floating_epsilon=EPSILON_Q48/(Q*Q)):
    if not any(masks):
        raise ValueError("all tokens masked")
    if output_dim not in (g.E, 2*g.E//3, g.E//3, g.E//6):
        raise ValueError("invalid output dimension")
    if fixed and raw_weights is not None:
        raise ValueError("raw floating coefficients are not integer-oracle inputs")
    weights = raw_weights if raw_weights is not None else quantized_weights if fixed else {
        n: [v/Q for v in values] for n, values in quantized_weights.items()}
    a = Arithmetic(fixed, floating_epsilon)
    def global_(name):
        return weights["language_model."+name]
    root = math.isqrt(g.H << 80)
    x = []
    ple = []
    for token in ids:
        e = global_("embed_tokens.weight")[token*g.H:(token+1)*g.H]
        e = [sat(nearest(v*root, F)) if fixed else v*math.sqrt(g.H) for v in e]
        x.append(e)
        projected = a.matrix(global_("ple.per_layer_model_projection.weight"), e)
        projected = [sat(nearest(v*F, root)) if fixed else v/math.sqrt(g.H)
                     for v in projected]
        ple.append([a.norm(projected[l*g.P:(l+1)*g.P],
                           global_("ple.per_layer_projection_norm.weight"))
                    for l in range(g.L)])
    for layer in range(g.L):
        full = layer % 6 == 5
        d, kv = (g.FD,g.FK) if full else (g.LD,g.LK)
        def w(name):
            return weights[f"language_model.layers.{layer}."+name]
        u = [a.norm(v,w("input_layernorm.weight")) for v in x]
        projected = {}
        for kind, heads in (("q",g.QH),("k",kv),("v",kv)):
            vectors = [a.matrix(w(f"self_attn.{kind}_proj.weight"), v) for v in u]
            projected[kind] = []
            for t, vector in enumerate(vectors):
                groups = [vector[h*d:(h+1)*d] for h in range(heads)]
                if kind != "v":
                    groups = [a.rope(a.norm(v,w(f"self_attn.{kind}_norm.weight")),
                                     positions[t],full) for v in groups]
                projected[kind].append(groups)
        next_x = []
        for t, current in enumerate(x):
            eligible = [k for k in range(len(ids)) if masks[k] and
                        (full or abs(positions[k]-positions[t]) < g.W)]
            attention = []
            for h in range(g.QH):
                kh = h//(g.QH//kv)
                attention += a.attention(projected["q"][t][h],
                    [v[kh] for v in projected["k"]],
                    [v[kh] for v in projected["v"]], eligible)
            branch = a.norm(a.matrix(w("self_attn.o_proj.weight"),attention),
                            w("post_attention_layernorm.weight"))
            current = [a.add(v,b) for v,b in zip(current,branch)]
            u = a.norm(current,w("pre_feedforward_layernorm.weight"))
            gate = [a.gelu(v) for v in a.matrix(w("mlp.gate_proj.weight"),u)]
            up = a.matrix(w("mlp.up_proj.weight"),u)
            branch = a.norm(a.matrix(w("mlp.down_proj.weight"),
                                    [a.product(v,b) for v,b in zip(gate,up)]),
                            w("post_feedforward_layernorm.weight"))
            current = [a.add(v,b) for v,b in zip(current,branch)]
            gate = [a.gelu(v) for v in
                    a.matrix(w("ple_block.per_layer_input_gate.weight"),current)]
            branch = a.norm(a.matrix(w("ple_block.per_layer_projection.weight"),
                [a.product(v,b) for v,b in zip(gate,ple[t][layer])]),
                w("ple_block.post_per_layer_input_norm.weight"))
            current = [a.product(a.add(v,b),w("layer_scalar")[0])
                       for v,b in zip(current,branch)]
            next_x.append(current)
        x = next_x
        if diagnostics is not None:
            diagnostics.append({"layer": layer, "hidden_q824": x})
    projected = [a.matrix(global_("embedding_projection.weight"),
                         a.norm(v,global_("norm.weight"))) for v in x]
    valid = sum(masks)
    sums = [sum(v[j] for v,m in zip(projected,masks) if m)
            for j in range(output_dim)]
    means = [sat(nearest(v,valid)) if fixed else v/valid for v in sums]
    norm = math.sqrt(sum((v/Q if fixed else v)**2 for v in means))
    return a.norm(means), norm


def forward(g, quantized_weights, ids, positions, masks, output_dim, fixed):
    return forward_details(g,quantized_weights,ids,positions,masks,output_dim,fixed)[0]
