"""Sparse immutable *weight* image fixtures, never hidden-state or KV answers."""

import struct
from fractions import Fraction

from numerical_reference import XorShift32, decode, encode
from reader_fixtures import directory_image, text_shapes
from run_rotary import rotation
from text_reference import bf16, norm


def step(state):
    state ^= state << 13 & 0xFFFFFFFF
    state ^= state >> 17
    state ^= state << 5 & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def apply(columns, state):
    value = 0
    while state:
        bit = state & -state
        value ^= columns[bit.bit_length() - 1]
        state ^= bit
    return value


POWERS = [tuple(step(1 << bit) for bit in range(32))]
for _ in range(63):
    previous = POWERS[-1]
    POWERS.append(tuple(apply(previous, value) for value in previous))


def advance(state, count):
    if not 0 < state < 1 << 32 or not 0 <= count < 1 << 64:
        raise ValueError("invalid frozen xorshift skip")
    bit = 0
    while count:
        if count & 1:
            state = apply(POWERS[bit], state)
        count >>= 1
        bit += 1
    return state


def check_skip():
    for seed in (17, 43, 89):
        rng = XorShift32(seed)
        state = seed
        for count in range(1025):
            if advance(seed, count) != state:
                raise RuntimeError("linear xorshift skip disagrees with sequential generator")
            state = rng.next()
        if advance(advance(seed, (1 << 33) + 17), (1 << 32) + 43) != advance(
                seed, (1 << 33) + (1 << 32) + 60):
            raise RuntimeError("large tensor skip composition failed")


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def production_owner_image(model, precision, seed, owner, token, selector, head, component):
    """Materialize only actually readable owner weights, with full public geometry.

    The skipped RNG states still enumerate *all* native text tensors. Missing
    payload is an error at the responder, not an implicit zero-filled tensor.
    """
    hidden, dimension, heads = (1536 if model == 1 else 2560), (
        512 if (owner + 1) % (5 if model == 1 else 6) == 0 else 256), (
        1 if model == 1 else 2)
    if head >= heads or component & 1 or component + 1 >= dimension:
        raise ValueError("illegal production owner fixture")
    shapes = list(text_shapes(model))
    directory = directory_image(model, precision, shapes)
    needed = {(0x100, owner), (0x105 if selector else 0x103, owner)}
    if not selector:
        needed.add((0x104, owner))
    scales = {}
    matrix = None
    segments = [(0, directory)]
    matrix_words = {n: encode(Fraction(n, 64), exponent_bits=8, fraction_bits=7)
                    for n in range(-16, 16)}
    state = seed
    for index, (kind, layer, dims, is_matrix, _) in enumerate(shapes):
        rows, columns = dims if is_matrix else (1, dims[0] if dims else 1)
        key = kind, layer
        count = rows * columns
        if key not in needed:
            state = advance(state, count)
            continue
        entry = directory[64 + 64 * index:128 + 64 * index]
        offset, length = struct.unpack_from("<QQ", entry, 8)
        stride = struct.unpack_from("<I", entry, 40)[0]
        values = []
        payload = bytearray()
        if is_matrix:
            for row in range(rows):
                packed = bytearray()
                row_values = []
                if precision:
                    for _ in range(columns // 32):
                        nibbles = []
                        for _ in range(32):
                            state = step(state)
                            nibbles.append(state & 15)
                        packed += struct.pack("<e", 1 / 32)
                        packed += bytes(nibbles[j] | nibbles[j + 16] << 4 for j in range(16))
                        row_values.extend((n - 8) / 32 for n in nibbles)
                else:
                    for _ in range(columns):
                        state = step(state)
                        numerator = (state & 31) - 16
                        word = matrix_words[numerator]
                        packed += struct.pack("<H", word)
                        row_values.append(numerator / 64)
                payload += packed + bytes(stride - len(packed))
                if head * dimension <= row < (head + 1) * dimension:
                    values.append(row_values)
            matrix = values
        else:
            for _ in range(columns):
                state = step(state)
                value = 1 + Fraction((state & 7) - 3, 64)
                word = encode(value, exponent_bits=8, fraction_bits=7)
                payload += struct.pack("<H", word)
                values.append(decode(word, 8, 7)[2])
            payload += bytes(length - len(payload))
            scales[kind] = values
        if len(payload) != length:
            raise RuntimeError("production fixture length disagrees with public tensor directory")
        segments.append((offset, bytes(payload)))
    if matrix is None:
        raise RuntimeError("missing independently generated owner matrix")
    source = [bf16(Fraction(((13 * token + 5 * c + seed) & 31) - 16, 32))
              for c in range(hidden)]
    normalized = [float(value) for value in norm(source, scales[0x100])]
    projected = []
    for row in matrix:
        accumulator = 0.0
        for weight, value in zip(row, normalized):
            accumulator = f32(accumulator + f32(weight * value))
        projected.append(bf16(Fraction(accumulator)))
    # These bounded dyadic fixtures have at most 32 significant bits before
    # each f32 rounding, so binary64 products/sums here are exact, not fused.
    vector = norm(projected, None if selector else scales[0x104])
    bits = [encode(value, exponent_bits=8, fraction_bits=7) for value in vector]
    if not selector:
        global_ = dimension == 512
        half = dimension // 2
        pairs = [rotation(int(global_), dimension, i, token, bits[i], bits[i + half])
                 for i in range(half)]
        bits = [word & 65535 for word in pairs] + [word >> 16 for word in pairs]
    container = bytearray(b"KVFIX001" + struct.pack("<I", len(segments)))
    for offset, payload in segments:
        container += struct.pack("<QQ", offset, len(payload)) + payload
    source_bytes = b"".join(struct.pack("<H", encode(
        value, exponent_bits=8, fraction_bits=7)) for value in source)
    return bytes(container), source_bytes, bits
