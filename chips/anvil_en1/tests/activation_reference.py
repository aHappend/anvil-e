"""Binary64 transcendental expectations and inward-rounded admissible intervals."""

import math
import struct
from fractions import Fraction

from numerical_reference import INF, QNAN, decode, encode


def bits_float(word):
    return struct.unpack("<f", struct.pack("<I", word))[0]


def inside_bound(value, lower):
    word = encode(Fraction(value))
    rounded = bits_float(word)
    if lower and rounded < value:
        word = word - 1 if word >> 31 else word + 1
    if not lower and rounded > value:
        word = word + 1 if word >> 31 else word - 1
    return word


def activation_vectors(dense=False):
    words = {0, 0x80000000, 1, 0x80000001, 0x007FFFFF, 0x807FFFFF,
             0x00800000, 0x80800000, INF, INF | 0x80000000, QNAN, 0x7F800001}
    step = 32 if dense else 2
    for i in range(-16 * step, 16 * step + 1):
        words.add(encode(Fraction(i, step)))
    index = 0
    for operation in (0, 1, 2, 3):
        for word in sorted(words):
            sign, category, value = decode(word)
            index += 1
            exact = False
            if category == "nan":
                expected, exact = QNAN, True
            elif category == "inf":
                if operation == 0:
                    expected = 0xBF800000 if sign else 0x3F800000
                elif operation in (1, 2):
                    expected = QNAN if sign else INF
                else:
                    expected = 0 if sign else 0x3F800000
                exact = True
            elif value == 0:
                expected = 0x3F000000 if operation == 3 else word
                exact = True
            if exact:
                yield index, operation, word, expected, expected, 0, index % 4, 1
                continue
            x = float(value)
            if operation == 0:
                expected = math.copysign(1, x) if abs(x) >= 8 else math.tanh(x)
                tolerance = 2**-10
            elif operation == 1:
                expected = 0.5 * x * (1 + math.tanh(math.sqrt(2 / math.pi) *
                                                   (x + 0.044715 * x**3)))
                tolerance = 2**-7 * max(1, abs(x))
            else:
                e = math.exp(-abs(x))
                sigmoid = e / (1 + e) if x < 0 else 1 / (1 + e)
                expected = x * sigmoid if operation == 2 else sigmoid
                # Supplemental native-audio primitive check, not a relaxed text threshold.
                tolerance = 2**-10 * max(1, abs(x)) if operation == 2 else 2**-10
            lower = inside_bound(expected - tolerance, True)
            upper = inside_bound(expected + tolerance, False)
            yield index, operation, word, lower, upper, 0, index % 4, 0
