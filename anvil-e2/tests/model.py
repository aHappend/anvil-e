"""Tensor-level oracle for Q40 operators and Q24 memory, independent of RTL control.

The floating implementation evaluates mathematical operators; the integer
implementation evaluates the documented quantization and nonlinear series.
No implementation source is imported, parsed, or used to produce expectations.
"""
import math
import random
from dataclasses import dataclass, replace

Q = 1 << 24
EPSILON_Q24 = round(1e-6 * Q)
LEGACY_RMS_EPSILON_Q80 = 17 << 56
ONE = 1 << 40
LN2 = 762123384786
PI = 3454217652358
TWO_PI = 6908435304715


def rnd(n, d):
    assert d != 0
    sign = -1 if (n < 0) != (d < 0) else 1
    q, r = divmod(abs(n), abs(d))
    return sign * (q + (2*r > abs(d) or (2*r == abs(d) and q % 2)))


OFFICIAL_RMS_EPSILON_Q80 = rnd(1 << 80, 1000000)


def sat(x):
    return min(2147483647, max(-2147483648, x))


def clamp40(x):
    return min(2147483647 << 16, max(-2147483648 << 16, x))


def materialize(x):
    return sat(rnd(x, 1 << 16))


def q40mul(a, b):
    return rnd(a*b, ONE)


def exp40(x):
    k, r = divmod(max(-16*ONE, x), LN2)
    term = total = ONE
    for i in range(1, 19):
        term = rnd(q40mul(term, r), i)
        total += term
    assert k <= 0
    return total >> -k


def trig40(x, cosine=False):
    # Preserve either signed half-turn endpoint: TWO_PI is 2*PI-1.
    a = (abs(x) % TWO_PI) * (-1 if x < 0 else 1)
    if a > PI:
        a -= TWO_PI
    elif a < -PI:
        a += TWO_PI
    term = total = ONE if cosine else a
    for i in range(1, 19):
        term = rnd(-q40mul(q40mul(term, a), a),
                   (2*i-1)*(2*i) if cosine else (2*i)*(2*i+1))
        total += term
    return clamp40(total)


@dataclass(frozen=True)
class Config:
    VISION_LAYERS: int = 1
    VISION_HIDDEN: int = 4
    VISION_FFN: int = 1
    VISION_HEADS: int = 1
    VISION_HEAD_DIM: int = 4
    PATCH_SIZE: int = 1
    POOL_KERNEL: int = 1
    VISION_SOFT_TOKENS: int = 1
    TEXT_LAYERS: int = 1
    TEXT_HIDDEN: int = 1
    PLE_DIM: int = 1
    TEXT_FFN: int = 1
    EMBED_DIM: int = 6
    VOCAB_SIZE: int = 262144
    POSITION_EMBEDDING_SIZE: int = 10240
    TEXT_Q_HEADS: int = 4
    LOCAL_KV_HEADS: int = 2
    FULL_KV_HEADS: int = 1
    LOCAL_HEAD_DIM: int = 2
    FULL_HEAD_DIM: int = 4
    SLIDING_WINDOW: int = 1
    MAX_SEQ_LEN: int = 262144
    RMS_EPSILON_Q80: int = LEGACY_RMS_EPSILON_Q80


CONFIGS = {
    "A": Config(),
    "B": Config(VISION_HIDDEN=8, VISION_HEADS=2, VISION_FFN=7,
                POOL_KERNEL=3, VISION_SOFT_TOKENS=4, TEXT_LAYERS=6,
                TEXT_HIDDEN=3, PLE_DIM=3, TEXT_FFN=5, EMBED_DIM=12,
                SLIDING_WINDOW=2),
    "C": Config(VISION_LAYERS=16, TEXT_LAYERS=24, TEXT_HIDDEN=2,
                PLE_DIM=2, TEXT_FFN=3, VISION_FFN=3, EMBED_DIM=12,
                SLIDING_WINDOW=2),
    "D": Config(TEXT_HIDDEN=2, PLE_DIM=2, TEXT_FFN=3, EMBED_DIM=768,
                VISION_FFN=3, SLIDING_WINDOW=2),
}


class Integer:
    zero = 0

    def __init__(self, rms_epsilon_q80=LEGACY_RMS_EPSILON_Q80):
        assert isinstance(rms_epsilon_q80, int) and 0 <= rms_epsilon_q80 < 1 << 128
        self.rms_epsilon_q80 = rms_epsilon_q80

    def decode(self, x):
        return x << 16

    def boundary(self, x):
        return materialize(x) << 16

    def fusion_scale(self, x, d):
        root = math.isqrt(d << 80)
        return [sat(rnd((a >> 16)*root, ONE)) << 16 for a in x]

    def add(self, a, b):
        return clamp40(a+b)

    def mul(self, a, b):
        return clamp40(rnd(a*b, ONE))

    def mat(self, w, x):
        return [clamp40(rnd(sum(a*b for a, b in zip(row, x)), ONE)) for row in w]

    def mean(self, xs):
        return [clamp40(rnd(sum(row[i] for row in xs), len(xs)))
                for i in range(len(xs[0]))]

    def norm(self, x, w=None):
        square = sum(a*a for a in x)
        if w is not None:
            square = rnd(square, len(x)) + self.rms_epsilon_q80
        root = math.isqrt(square << 64)
        if not root:
            return [0]*len(x)
        unit = [ONE]*len(x) if w is None else [ONE+a for a in w]
        return [clamp40(rnd(rnd(a << 72, root)*b, ONE)) for a, b in zip(x, unit)]

    def scale(self, x, d, divide=False):
        root = math.isqrt(d << 80)
        return [clamp40(rnd(a << 40, root) if divide else rnd(a*root, ONE)) for a in x]

    def gelu(self, a):
        if a >= 8*ONE:
            return a
        if a <= -8*ONE:
            return 0
        x = a
        z = q40mul(877283352226,
                   x + q40mul(49164662436, q40mul(q40mul(x, x), x)))
        e = exp40(-2*abs(z))
        t = rnd((ONE-e)*ONE, ONE+e)
        if a < 0:
            t = -t
        return clamp40(rnd(q40mul(x, ONE+t), 2))

    def rotate(self, x, pos, theta):
        ln = {100: 5063438167381, 10000: 10126876334763,
              1000000: 15190314502144}[theta]
        d = len(x)
        out = x[:]
        for i in range(d//2):
            frequency = exp40(-rnd(2*i*ln, d))
            angle = (frequency*pos) % TWO_PI
            if angle > PI:
                angle -= TWO_PI
            c, s = trig40(angle, True), trig40(angle)
            out[i] = clamp40(rnd(x[i]*c-x[i+d//2]*s, ONE))
            out[i+d//2] = clamp40(rnd(x[i]*s+x[i+d//2]*c, ONE))
        return out

    def attention(self, q, ks, vs, uniform=False):
        if not ks:
            return [0]*len(q)
        root = math.isqrt(len(q) << 80)
        scores = [clamp40(rnd(sum(a*b for a, b in zip(q, k)), root)) for k in ks]
        m = max(scores)
        es = [ONE if uniform else
              (0 if s-m < -16*ONE else exp40(s-m))
              for s in scores]
        return [clamp40(rnd(sum(e*v[i] for e, v in zip(es, vs)), sum(es)))
                for i in range(len(q))]


class Floating:
    zero = 0.0

    def decode(self, x):
        return x / Q

    def add(self, a, b):
        return a+b

    def mul(self, a, b):
        return a*b

    def mat(self, w, x):
        return [sum(a*b for a, b in zip(row, x)) for row in w]

    def mean(self, xs):
        return [sum(row[i] for row in xs)/len(xs) for i in range(len(xs[0]))]

    def norm(self, x, w=None):
        square = sum(a*a for a in x)
        # Epsilon is provisioned in Q24 before arithmetic by the public contract.
        den = math.sqrt(square if w is None else square/len(x) + EPSILON_Q24/Q)
        if not den:
            return [0.0]*len(x)
        return [a/den*(1 if w is None else 1+w[i]) for i, a in enumerate(x)]

    def scale(self, x, d, divide=False):
        return [a/math.sqrt(d) if divide else a*math.sqrt(d) for a in x]

    def gelu(self, x):
        return x/2*(1+math.tanh(math.sqrt(2/math.pi)*(x+0.044715*x**3)))

    def rotate(self, x, pos, theta):
        d = len(x)
        out = x[:]
        for i in range(d//2):
            a = pos * theta**(-2*i/d)
            c, s = math.cos(a), math.sin(a)
            out[i] = x[i]*c-x[i+d//2]*s
            out[i+d//2] = x[i]*s+x[i+d//2]*c
        return out

    def attention(self, q, ks, vs, uniform=False):
        if not ks:
            return [0.0]*len(q)
        scores = [sum(a*b for a, b in zip(q, k))/math.sqrt(len(q)) for k in ks]
        m = max(scores)
        es = [1 if uniform else math.exp(s-m) for s in scores]
        return [sum(e*v[i] for e, v in zip(es, vs))/sum(es) for i in range(len(q))]


WEIGHTS = 0x10000000
VISION = 0x20000000
IMAGE = 0x30000000
IDS = 0x40000000
POSITIONS = 0x50000000
MASKS = 0x60000000
SCRATCH = 0x70000000


class Fixture:
    """Independent prefix-sum weight map and scratch allocation."""

    def __init__(self, config, seed, mode, dimension=None, zero=False):
        self.c, self.seed, self.mode = config, seed, mode
        self.dimension = dimension or config.EMBED_DIM
        self.rows, self.cols = ((4, 5) if config.VISION_SOFT_TOKENS == 4 else (1, 1))
        self.ids = [] if mode == 1 else [7, 19, 31]
        self.positions = [1, 4, 8][:len(self.ids)]
        self.masks = [1, 0, 1][:len(self.ids)]
        self.mem, self.tensors, self.offsets = {}, {}, {}
        self.rng = random.Random(seed)
        self.zero = zero
        self._weights()
        self.image = [self.number(0.45) for _ in
                      range(3*self.rows*self.cols*config.PATCH_SIZE**2)]
        for base, values in [(IMAGE, self.image), (IDS, self.ids),
                             (POSITIONS, self.positions), (MASKS, self.masks)]:
            for i, v in enumerate(values):
                self.mem[base+4*i] = v
        self.layout = self.arena()

    def number(self, width):
        return 0 if self.zero else round(self.rng.uniform(-width, width)*Q)

    def allocate(self, name, base, offset, rows, cols=1, scalar=False, table=False):
        self.offsets[name] = base+4*offset
        if table:
            data = {}
            for token in self.ids+[255999, 258882]:
                data[token] = [self.number(0.25) for _ in range(cols)]
                for j, v in enumerate(data[token]):
                    self.mem[base+4*(offset+token*cols+j)] = v
            self.tensors[name] = data
        else:
            width = 0.08 if cols == 1 and not scalar else 0.18
            data = [[(round(0.95*Q) if scalar else self.number(width))
                     for _ in range(cols)] for _ in range(rows)]
            self.tensors[name] = data if cols != 1 else [r[0] for r in data]
            for i, row in enumerate(data):
                for j, v in enumerate(row):
                    if (name != "position" or i < self.rows or
                            self.c.POSITION_EMBEDDING_SIZE <= i <
                            self.c.POSITION_EMBEDDING_SIZE+self.cols):
                        self.mem[base+4*(offset+i*cols+j)] = v
        return offset+rows*cols

    def _weights(self):
        c = self.c
        h, e, f, b, l = c.TEXT_HIDDEN, c.PLE_DIM, c.TEXT_FFN, c.EMBED_DIM, c.TEXT_LAYERS
        off = self.allocate("embed", WEIGHTS, 0, c.VOCAB_SIZE, h, table=True)
        for name, r, k in [("projection", b, h), ("norm", h, 1),
                            ("ple_model", l*e, h), ("ple_norm", e, 1)]:
            off = self.allocate(name, WEIGHTS, off, r, k)
        for layer in range(l):
            d = c.FULL_HEAD_DIM if layer % 6 == 5 else c.LOCAL_HEAD_DIM
            kv = c.FULL_KV_HEADS if layer % 6 == 5 else c.LOCAL_KV_HEADS
            shapes = [("input", h, 1), ("scalar", 1, 1), ("down", h, f),
                      ("gate", f, h), ("up", f, h), ("ple_gate", e, h),
                      ("ple_proj", h, e), ("ple_post", h, 1), ("post_att", h, 1),
                      ("post_ff", h, 1), ("pre_ff", h, 1), ("knorm", d, 1),
                      ("k", kv*d, h), ("o", h, c.TEXT_Q_HEADS*d),
                      ("qnorm", d, 1), ("q", c.TEXT_Q_HEADS*d, h), ("v", kv*d, h)]
            for name, r, k in shapes:
                off = self.allocate(f"t{layer}.{name}", WEIGHTS, off, r, k,
                                    scalar=name == "scalar")
        self.text_words = off
        vh, vf = c.VISION_HIDDEN, c.VISION_FFN
        off = self.allocate("patch", VISION, 0, vh, 3*c.PATCH_SIZE**2)
        off = self.allocate("position", VISION, off, 2*c.POSITION_EMBEDDING_SIZE, vh)
        for layer in range(c.VISION_LAYERS):
            shapes = [("input", vh, 1), ("q", vh, vh), ("k", vh, vh), ("v", vh, vh),
                      ("o", vh, vh), ("qnorm", c.VISION_HEAD_DIM, 1),
                      ("knorm", c.VISION_HEAD_DIM, 1), ("post_att", vh, 1),
                      ("pre_ff", vh, 1), ("gate", vf, vh), ("up", vf, vh),
                      ("down", vh, vf), ("post_ff", vh, 1)]
            for name, r, k in shapes:
                off = self.allocate(f"v{layer}.{name}", VISION, off, r, k)
        self.vision_words = self.allocate("bridge", VISION, off, h, vh)

    def arena(self):
        c = self.c
        p = self.rows*self.cols if self.mode else 0
        s = c.VISION_SOFT_TOKENS if self.mode else 0
        n = len(self.ids)+(s+2 if self.mode else 0)
        d, k = max(c.LOCAL_HEAD_DIM, c.FULL_HEAD_DIM), max(c.LOCAL_KV_HEADS, c.FULL_KV_HEADS)
        extents = [("v0", p*c.VISION_HIDDEN), ("v1", p*c.VISION_HIDDEN),
                   ("vq", p*c.VISION_HIDDEN), ("vk", p*c.VISION_HIDDEN),
                   ("vv", p*c.VISION_HIDDEN), ("soft", s*c.TEXT_HIDDEN),
                   ("ids", n), ("positions", n), ("masks", n),
                   ("x0", n*c.TEXT_HIDDEN), ("x1", n*c.TEXT_HIDDEN),
                   ("ple", n*c.TEXT_LAYERS*c.PLE_DIM),
                   ("q", n*c.TEXT_Q_HEADS*d), ("k", n*k*d), ("v", n*k*d)]
        off, result = 0, {}
        for name, size in extents:
            result[name] = SCRATCH+4*off
            off += size
        result["end"] = SCRATCH+4*off
        return result

    def matrix(self, name, ops):
        data = self.tensors[name]
        if data and not isinstance(data[0], list):
            data = [[x] for x in data]
        return [[ops.decode(x) for x in row] for row in data]

    def vector(self, name, ops):
        return [ops.decode(x) for x in self.tensors[name]]

    def run(self, ops, alteration=None, trace=None):
        c, layout = self.c, self.layout
        writes = {}

        def record(name, values):
            if trace is not None:
                trace[name] = values

        def boundary(rows):
            if isinstance(ops, Integer):
                return [[ops.boundary(v) for v in row] for row in rows]
            return rows

        def put(name, rows, stride=None, offset=0, metadata=False):
            if not isinstance(ops, Integer):
                return
            if rows and not isinstance(rows[0], list):
                rows = [rows]
            stride = stride or len(rows[0])
            for i, row in enumerate(rows):
                for j, v in enumerate(row):
                    address = layout[name]+4*(offset+i*stride+j)
                    word = v if metadata else materialize(v)
                    writes.setdefault(address, []).append(word & 0xffffffff)

        def mat(name, x):
            return ops.mat(self.matrix(name, ops), x)

        def norm(name, x):
            return ops.norm(x, self.vector(name, ops))

        def add(x, y):
            return [ops.add(a, b) for a, b in zip(x, y)]

        def layer(x, prefix, heads, kv, d, positions, masks, full, vision=False):
            qs, ks, vs = [], [], []
            for token, vec in enumerate(x):
                a = norm(prefix+".input", vec)
                q, k, v = mat(prefix+".q", a), mat(prefix+".k", a), mat(prefix+".v", a)
                for vectors, nh, nw in [(q, heads, "qnorm"), (k, kv, "knorm")]:
                    for head in range(nh):
                        hv = norm(prefix+"."+nw, vectors[head*d:(head+1)*d])
                        if vision:
                            row, col = divmod(token, self.cols)
                            if alteration == "axial_swap":
                                row, col = col, row
                            if alteration != "vision_rope":
                                hv = (ops.rotate(hv[:d//2], row, 100) +
                                      ops.rotate(hv[d//2:], col, 100))
                        else:
                            hv = ops.rotate(hv, positions[token], 1000000 if full else 10000)
                        vectors[head*d:(head+1)*d] = hv
                q, k, v = boundary([q, k, v])
                qs.append(q); ks.append(k); vs.append(v)
            if vision:
                put("vq", qs); put("vk", ks); put("vv", vs)
            else:
                dm = max(c.LOCAL_HEAD_DIM, c.FULL_HEAD_DIM)
                km = max(c.LOCAL_KV_HEADS, c.FULL_KV_HEADS)
                put("q", qs, heads*dm); put("k", ks, km*dm); put("v", vs, km*dm)
            result = []
            for i, vec in enumerate(x):
                att = []
                for head in range(heads):
                    kh = head//(heads//kv)
                    eligible = [j for j in range(len(x)) if masks[j] and
                                (full or abs(positions[i]-positions[j]) < c.SLIDING_WINDOW)]
                    att += ops.attention(qs[i][head*d:(head+1)*d],
                                         [ks[j][kh*d:(kh+1)*d] for j in eligible],
                                         [vs[j][kh*d:(kh+1)*d] for j in eligible],
                                         alteration == "uniform")
                    if alteration == f"{'vision' if vision else 'text'}_head_{head}":
                        att[-d:] = [ops.zero]*d
                vec = add(vec, norm(prefix+".post_att", mat(prefix+".o", att)))
                a = norm(prefix+".pre_ff", vec)
                gate, up = mat(prefix+".gate", a), mat(prefix+".up", a)
                ff = [ops.mul(ops.gelu(g), u) for g, u in zip(gate, up)]
                result.append(add(vec, norm(prefix+".post_ff", mat(prefix+".down", ff))))
            return result

        soft = []
        if self.mode:
            ps = c.PATCH_SIZE
            height, width = self.rows*ps, self.cols*ps
            image = [ops.decode(x) for x in self.image]
            pos = self.matrix("position", ops)
            x = []
            for r in range(self.rows):
                for col in range(self.cols):
                    patch = [image[ch*height*width+(r*ps+dy)*width+col*ps+dx]
                             for ch in range(3) for dy in range(ps) for dx in range(ps)]
                    vec = mat("patch", patch)
                    if alteration != "vision_position":
                        vec = add(add(vec, pos[r]), pos[c.POSITION_EMBEDDING_SIZE+col])
                    x.append(vec)
            x = boundary(x)
            put("v0", x)
            record("patch", x)
            for l in range(c.VISION_LAYERS):
                x = layer(x, f"v{l}", c.VISION_HEADS, c.VISION_HEADS,
                          c.VISION_HEAD_DIM, list(range(len(x))), [1]*len(x), True, True)
                x = boundary(x)
                put("v1" if l % 2 == 0 else "v0", x)
                record(f"vision.{l}", x)
            for r in range(0, self.rows, c.POOL_KERNEL):
                for col in range(0, self.cols, c.POOL_KERNEL):
                    members = [x[a*self.cols+b]
                               for a in range(r, min(r+c.POOL_KERNEL, self.rows))
                               for b in range(col, min(col+c.POOL_KERNEL, self.cols))]
                    pooled = members[0] if alteration == "pool_sample" else ops.mean(members)
                    soft.append(mat("bridge", pooled))
            if alteration == "bridge":
                soft = [[ops.zero]*c.TEXT_HIDDEN for _ in soft]
            soft = boundary(soft)
            put("soft", soft)
            record("soft", soft)
        frame = c.VISION_SOFT_TOKENS+2 if self.mode else 0
        ids = ([255999]+[258880]*len(soft)+[258882] if self.mode else [])+self.ids
        positions = list(range(frame))+[p+frame for p in self.positions]
        masks = [1]*frame+self.masks
        x = []
        for i, token in enumerate(ids):
            if self.mode and 0 < i <= len(soft):
                vec = soft[i-1]
            else:
                scale = ops.fusion_scale if isinstance(ops, Integer) else ops.scale
                vec = scale([ops.decode(a) for a in self.tensors["embed"][token]],
                            c.TEXT_HIDDEN)
            x.append(vec)
        x = boundary(x)
        put("ids", [ids], metadata=True)
        put("positions", [positions], metadata=True)
        put("masks", [masks], metadata=True)
        put("x0", x)
        record("fusion", [row[:] for row in x])
        cached = []
        pm = self.matrix("ple_model", ops)
        for i, vec in enumerate(x):
            per_layer = []
            for l in range(c.TEXT_LAYERS):
                ple = ops.mat(pm[l*c.PLE_DIM:(l+1)*c.PLE_DIM], vec)
                ple = norm("ple_norm", ops.scale(ple, c.TEXT_HIDDEN, True))
                ple = boundary([ple])[0]
                per_layer.append(ple)
                put("ple", [ple], offset=(i*c.TEXT_LAYERS+l)*c.PLE_DIM)
            cached.append(per_layer)
        record("cached_ple", cached)
        for l in range(c.TEXT_LAYERS):
            full = l % 6 == 5
            if alteration == "schedule":
                full = not full
                # Schedule mutation in RTL changes tensor geometry too; oracle
                # counterfactual instead isolates key eligibility below.
                full = l % 6 == 5
            d = c.FULL_HEAD_DIM if full else c.LOCAL_HEAD_DIM
            kv = c.FULL_KV_HEADS if full else c.LOCAL_KV_HEADS
            x = layer(x, f"t{l}", c.TEXT_Q_HEADS, kv, d, positions, masks,
                      False if alteration == "schedule" else full)
            for i, vec in enumerate(x):
                gate = [ops.gelu(a) for a in mat(f"t{l}.ple_gate", vec)]
                injection = [ops.mul(a, b) for a, b in zip(gate, cached[i][l])]
                if alteration != "ple":
                    vec = add(vec, norm(f"t{l}.ple_post", mat(f"t{l}.ple_proj", injection)))
                scalar = self.vector(f"t{l}.scalar", ops)[0]
                x[i] = [ops.mul(a, scalar) for a in vec]
            x = boundary(x)
            put("x1" if l % 2 == 0 else "x0", x)
            record(f"text.{l}", [row[:] for row in x])
        projected = [mat("projection", norm("norm", vec)) for vec in x]
        eligible = [v for v, mask in zip(projected, masks) if mask or alteration == "unmasked"]
        if not eligible:
            return [], writes
        pooled = ops.mean(eligible)
        record("projected", projected)
        record("pooled", pooled)
        output = (ops.norm(pooled)[:self.dimension] if alteration == "pretruncate"
                  else ops.norm(pooled[:self.dimension]))
        record("output", output)
        return ([materialize(v) for v in output] if isinstance(ops, Integer) else output), writes
