"""Layer-major reference retaining every logical layer state, never replaying."""

import math
import struct
from fractions import Fraction

from numerical_reference import decode, encode, sqrt_encode


def f32(value):
    return decode(encode(Fraction(value)))[2]


def bf16(value):
    return decode(encode(Fraction(value), exponent_bits=8, fraction_bits=7), 8, 7)[2]


def add(a, b):
    return f32(a + b)


def mul(a, b):
    return f32(a * b)


def project(matrix, vector):
    output = []
    for row in matrix:
        if len(row) != len(vector):
            raise ValueError("matrix/vector dimension mismatch")
        accumulator = Fraction(0)
        for weight, value in zip(row, vector):
            accumulator = add(accumulator, mul(weight, value))
        output.append(bf16(accumulator))
    return output


def norm(vector, scale=None):
    accumulator = Fraction(0)
    for value in vector:
        accumulator = add(accumulator, mul(value, value))
    variance = add(f32(accumulator / len(vector)), decode(0x358637BD)[2])
    inv = decode(sqrt_encode(1 / variance))[2]
    return [bf16(mul(mul(value, inv), scale[i]) if scale is not None
                 else mul(value, inv)) for i, value in enumerate(vector)]


def gelu(value):
    x = float(value)
    return bf16(0.5 * x * (1 + math.tanh(math.sqrt(2 / math.pi) *
                                         (x + 0.044715 * x**3))))


def residual(a, b):
    return [bf16(add(x, y)) for x, y in zip(a, b)]


def rotate(vector, position, global_attention):
    dimension = len(vector)
    half = dimension // 2
    theta = 1000000 if global_attention else 10000
    frequency_count = int(dimension * 0.25 / 2) if global_attention else half
    output = []
    for component in range(dimension):
        i = component % half
        angle = position * theta ** (-2 * i / dimension) if i < frequency_count else 0
        cosine = bf16(math.cos(angle))
        sine = bf16(math.sin(angle))
        rotated = -vector[component + half] if component < half else vector[component - half]
        output.append(bf16(add(mul(vector[component], cosine), mul(rotated, sine))))
    return output


def logits(tensors, model, seed, tokens=1):
    """Return all last-token logits plus independent observable leaf boundaries."""
    layer_count, owner_count = (35, 15) if model == 1 else (42, 24)
    globals_ = set(range(4, 35, 5) if model == 1 else range(5, 42, 6))
    local_anchor, global_anchor = (13, 14) if model == 1 else (22, 23)

    def tensor(kind, layer=0xFFFF):
        return tensors[kind, layer]

    def scale(kind, layer=0xFFFF):
        return tensor(kind, layer)[0]

    root_h = bf16(decode(sqrt_encode(Fraction(8)))[2])
    inv_h = bf16(decode(sqrt_encode(Fraction(1, 8)))[2])
    inv_two = bf16(decode(sqrt_encode(Fraction(1, 2)))[2])
    ids = [(7 * t + seed) % 32 for t in range(tokens)]
    initial = [[bf16(mul(weight, root_h)) for weight in tensor(0)[token_id]]
               for token_id in ids]
    identity = [[bf16(mul(weight, Fraction(2))) for weight in tensor(1)[token_id]]
                for token_id in ids]
    context = [[bf16(mul(value, inv_h)) for value in project(tensor(2), vector)]
               for vector in initial]
    per_layer = {}
    for layer in range(layer_count):
        per_layer[layer] = []
        for t in range(tokens):
            normalized = norm(context[t][4 * layer:4 * (layer + 1)], scale(3))
            combined = residual(identity[t][4 * layer:4 * (layer + 1)], normalized)
            per_layer[layer].append([bf16(mul(value, inv_two)) for value in combined])

    hidden = initial
    states = [initial]
    owner_kv = {}
    for layer in range(layer_count):
        dimension = 8 if layer in globals_ else 4
        layer_input = [norm(vector, scale(0x100, layer)) for vector in hidden]
        if layer < owner_count:
            keys, values = [], []
            for t, vector in enumerate(layer_input):
                keys.append(rotate(norm(project(tensor(0x103, layer), vector),
                                        scale(0x104, layer)), t, layer in globals_))
                values.append(norm(project(tensor(0x105, layer), vector)))
            owner_kv[layer] = (keys, values)
        owner = layer if layer < owner_count else (
            global_anchor if layer in globals_ else local_anchor)
        keys, values = owner_kv[owner]
        output = []
        for t, vector in enumerate(layer_input):
            query = project(tensor(0x101, layer), vector)
            concatenated = []
            for head in range(2):
                q = rotate(norm(query[head * dimension:(head + 1) * dimension],
                                scale(0x102, layer)), t, layer in globals_)
                scores = []
                first = 0 if layer in globals_ else max(0, t - 3)
                for s in range(first, t + 1):
                    dot = Fraction(0)
                    for x, y in zip(q, keys[s]):
                        dot = add(dot, mul(x, y))
                    scores.append(dot)
                maximum = max(scores)
                exponentials = [f32(math.exp(float(add(score, -maximum)))) for score in scores]
                denominator = Fraction(0)
                for value in exponentials:
                    denominator = add(denominator, value)
                probabilities = [bf16(f32(value / denominator)) for value in exponentials]
                for c in range(dimension):
                    result = Fraction(0)
                    for probability, s in zip(probabilities, range(first, t + 1)):
                        result = add(result, mul(probability, values[s][c]))
                    concatenated.append(bf16(result))
            branch = norm(project(tensor(0x106, layer), concatenated), scale(0x107, layer))
            attention_residual = residual(hidden[t], branch)
            mlp_input = norm(attention_residual, scale(0x108, layer))
            gate = project(tensor(0x109, layer), mlp_input)
            up = project(tensor(0x10A, layer), mlp_input)
            intermediate = [bf16(mul(gelu(x), y)) for x, y in zip(gate, up)]
            branch = norm(project(tensor(0x10B, layer), intermediate), scale(0x10C, layer))
            mlp_residual = residual(attention_residual, branch)
            gate = project(tensor(0x10D, layer), mlp_residual)
            gated = [bf16(mul(gelu(x), y)) for x, y in zip(gate, per_layer[layer][t])]
            branch = norm(project(tensor(0x10E, layer), gated), scale(0x10F, layer))
            final = residual(mlp_residual, branch)
            output.append([bf16(mul(value, scale(0x110, layer)[0])) for value in final])
        hidden = output
        states.append(hidden)
    final = norm(hidden[-1], scale(4))
    raw = project(tensor(0), final)
    finite_logits = [30 * math.tanh(float(value) / 30) for value in raw]
    return {
        "logits": finite_logits,
        "initial_bf16": [[encode(x, exponent_bits=8, fraction_bits=7) for x in row]
                         for row in initial],
        "ple_bf16": {str(layer): [[encode(x, exponent_bits=8, fraction_bits=7)
                                   for x in row] for row in vectors]
                     for layer, vectors in per_layer.items()},
        "owner_kv_bf16": {
            str(owner): [[[encode(x, exponent_bits=8, fraction_bits=7) for x in row]
                          for row in vectors] for vectors in pair]
            for owner, pair in owner_kv.items()
        },
        "layer_states_bf16": [[[encode(x, exponent_bits=8, fraction_bits=7) for x in row]
                               for row in vectors] for vectors in states],
        "reference_schedule": "layer-major with all logical layer states retained",
        "approximation_comparison": "final error <= 0.25 + 0.02 * abs(reference)",
    }
