"""Frozen compact text fixture image; tensor enumeration follows the public ABI."""

import struct
from fractions import Fraction

from numerical_reference import XorShift32, decode, encode


def compact_shapes(model):
    layers, owners = (35, 15) if model == 1 else (42, 24)
    yield 0, 0xFFFF, (32, 8), True
    yield 1, 0xFFFF, (32, layers * 4), True
    yield 2, 0xFFFF, (layers * 4, 8), True
    yield 3, 0xFFFF, (4,), False
    yield 4, 0xFFFF, (8,), False
    for layer in range(layers):
        dimension = 8 if (layer + 1) % (5 if model == 1 else 6) == 0 else 4
        intermediate = 32 if model == 1 and layer >= owners else 16
        shapes = {
            0x100: ((8,), False),
            0x101: ((2 * dimension, 8), True),
            0x102: ((dimension,), False),
            0x103: ((dimension, 8), True),
            0x104: ((dimension,), False),
            0x105: ((dimension, 8), True),
            0x106: ((8, 2 * dimension), True),
            0x107: ((8,), False),
            0x108: ((8,), False),
            0x109: ((intermediate, 8), True),
            0x10A: ((intermediate, 8), True),
            0x10B: ((8, intermediate), True),
            0x10C: ((8,), False),
            0x10D: ((4, 8), True),
            0x10E: ((8, 4), True),
            0x10F: ((8,), False),
            0x110: ((), False),
        }
        for kind, (shape, matrix) in shapes.items():
            if layer >= owners and kind in (0x103, 0x104, 0x105):
                continue
            yield kind, layer, shape, matrix


def make_text_image(model, precision, seed):
    if model not in (1, 2) or precision not in (0, 1):
        raise ValueError("fixture requires a native model and admitted precision")
    shapes = list(compact_shapes(model))
    expected_count = 540 if model == 1 else 665
    if len(shapes) != expected_count:
        raise AssertionError("independent directory enumeration has wrong size")
    rng = XorShift32(seed)
    directory_bytes = 64 * len(shapes)
    image = bytearray(64 + directory_bytes)
    tensors = {}
    entries = []
    for kind, layer, shape, matrix in shapes:
        rows, columns = shape if matrix else (1, shape[0] if shape else 1)
        stride = ((18 * ((columns + 31) // 32) + 3) // 4 * 4
                  if precision and matrix else (columns + 1) // 2 * 4)
        payload = bytearray()
        values = []
        for _row in range(rows):
            packed = bytearray()
            row_values = []
            if precision and matrix:
                for block in range((columns + 31) // 32):
                    nibbles = []
                    for j in range(32):
                        if block * 32 + j < columns:
                            nibble = rng.next() & 15
                            row_values.append(Fraction(nibble - 8, 32))
                        else:
                            nibble = 8
                        nibbles.append(nibble)
                    packed += struct.pack("<e", 1 / 32)
                    packed += bytes(nibbles[j] | nibbles[j + 16] << 4 for j in range(16))
            else:
                for _column in range(columns):
                    word = rng.next()
                    if matrix:
                        value = Fraction((word & 31) - 16, 64)
                    elif kind == 0x110:
                        value = 1 + Fraction((word & 3) - 1, 128)
                    else:
                        value = 1 + Fraction((word & 7) - 3, 64)
                    bf16 = encode(value, exponent_bits=8, fraction_bits=7)
                    packed += struct.pack("<H", bf16)
                    row_values.append(decode(bf16, 8, 7)[2])
            packed += bytes(stride - len(packed))
            payload += packed
            values.append(row_values)
        offset = len(image)
        image += payload
        entry = bytearray(64)
        struct.pack_into("<HHBBHQQ", entry, 0, kind, layer,
                         1 if precision and matrix else 0, len(shape), 0,
                         offset, len(payload))
        struct.pack_into("<4II", entry, 24, *(shape + (1,) * (4 - len(shape))), stride)
        entries.append(entry)
        tensors[kind, layer] = values
    struct.pack_into("<4IQIIQ", image, 0, 0x31564E41, 0x10000, model,
                     precision, len(image), len(entries), 64, 64)
    image[64:64 + directory_bytes] = b"".join(entries)
    return bytes(image), tensors
