"""Independent exact-real IEEE format references; no RTL scheduling is modeled."""

from fractions import Fraction
from math import isqrt


QNAN = 0x7FC00000
INF = 0x7F800000


def decode(bits, exponent_bits=8, fraction_bits=23):
    sign = bits >> (exponent_bits + fraction_bits)
    exponent = (bits >> fraction_bits) & ((1 << exponent_bits) - 1)
    fraction = bits & ((1 << fraction_bits) - 1)
    if exponent == (1 << exponent_bits) - 1:
        return sign, "nan" if fraction else "inf", None
    bias = (1 << (exponent_bits - 1)) - 1
    significand = fraction if exponent == 0 else fraction + (1 << fraction_bits)
    power = (exponent or 1) - bias - fraction_bits
    value = Fraction(significand) * Fraction(2) ** power
    return sign, "finite", -value if sign else value


def round_even(value):
    quotient, remainder = divmod(value.numerator, value.denominator)
    twice = 2 * remainder
    return quotient + (twice > value.denominator or
                       (twice == value.denominator and quotient & 1))


def binary_exponent(value):
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < Fraction(2) ** exponent:
        exponent -= 1
    return exponent


def encode(value, negative_zero=False, exponent_bits=8, fraction_bits=23):
    sign = int(value < 0 or (value == 0 and negative_zero))
    prefix = sign << (exponent_bits + fraction_bits)
    value = abs(value)
    if not value:
        return prefix
    bias = (1 << (exponent_bits - 1)) - 1
    exponent = max(1 - bias, binary_exponent(value))
    significand = round_even(value / Fraction(2) ** (exponent - fraction_bits))
    if significand == 1 << (fraction_bits + 1):
        significand >>= 1
        exponent += 1
    if exponent > bias:
        return prefix | (((1 << exponent_bits) - 1) << fraction_bits)
    if significand < 1 << fraction_bits:
        return prefix | significand
    return prefix | ((exponent + bias) << fraction_bits) | (significand -
                                                          (1 << fraction_bits))


def sqrt_encode(value):
    """Round sqrt(value) by exact squared midpoint comparisons."""
    exponent = binary_exponent(value) // 2
    unit = Fraction(2) ** (max(-126, exponent) - 23)
    squared = value / (unit * unit)
    lower = isqrt(squared.numerator // squared.denominator)
    midpoint_squared = Fraction(2 * lower + 1, 2) ** 2
    rounded = lower + (squared > midpoint_squared or
                       (squared == midpoint_squared and lower & 1))
    return encode(rounded * unit)


def arithmetic(engine, operation, a, b):
    sa, ca, va = decode(a)
    sb, cb, vb = decode(b)
    if engine == 0:
        if operation == 2:
            sign, category, value = decode(a & 0xFFFF, 8, 7)
            return (QNAN if category == "nan" else
                    (sign << 31) | INF if category == "inf" else
                    encode(value, bool(sign))), 0
        if operation == 3:
            return (0x7FC0 if ca == "nan" else
                    (sa << 15) | 0x7F80 if ca == "inf" else
                    encode(va, bool(sa), 8, 7)), 0
        if operation == 4:
            sign, category, value = decode(a & 0xFFFF, 5, 10)
            return (QNAN if category == "nan" else
                    (sign << 31) | INF if category == "inf" else
                    encode(value, bool(sign))), 0
        if operation not in (0, 1):
            return 0, 6
        if ca == "nan" or cb == "nan":
            return QNAN, 0
        if operation == 0:
            if ca == cb == "inf" and sa != sb:
                return QNAN, 0
            if ca == "inf" or cb == "inf":
                return a if ca == "inf" else b, 0
            return encode(va + vb, bool(sa and sb)), 0
        if ((ca == "inf" and cb == "finite" and vb == 0) or
                (cb == "inf" and ca == "finite" and va == 0)):
            return QNAN, 0
        if ca == "inf" or cb == "inf":
            return ((sa ^ sb) << 31) | INF, 0
        return encode(va * vb, bool(sa ^ sb)), 0
    if operation == 3:
        return 0, 6
    if operation in (1, 2):
        if ca == "nan" or (sa and (ca == "inf" or va != 0)):
            return QNAN, 0
        if ca == "inf":
            return (INF if operation == 1 else 0), 0
        if va == 0:
            return (sa << 31) | (INF if operation == 2 else 0), 0
        return sqrt_encode(va if operation == 1 else 1 / va), 0
    if ca == "nan" or cb == "nan" or ca == cb == "inf":
        return QNAN, 0
    if ca == cb == "finite" and va == vb == 0:
        return QNAN, 0
    if ca == "inf" or (cb == "finite" and vb == 0):
        return ((sa ^ sb) << 31) | INF, 0
    if cb == "inf" or va == 0:
        return (sa ^ sb) << 31, 0
    return encode(va / vb, bool(sa ^ sb)), 0


class XorShift32:
    def __init__(self, seed):
        if not 0 < seed < 2**32:
            raise ValueError("xorshift32 requires a nonzero 32-bit seed")
        self.state = seed

    def next(self):
        x = self.state
        x = (x ^ (x << 13)) & 0xFFFFFFFF
        x = (x ^ (x >> 17)) & 0xFFFFFFFF
        x = (x ^ (x << 5)) & 0xFFFFFFFF
        self.state = x
        return x


def arithmetic_vectors(seeds=(17, 43, 89), random_count=24, exhaustive=False):
    edges = (
        0, 0x80000000, 1, 0x80000001, 0x007FFFFF, 0x807FFFFF,
        0x00800000, 0x00800001, 0x3EAAAAAB, 0x3F000000, 0x3F7FFFFF,
        0x3F800000, 0x3F800001, 0x3FC00000, 0x40000000, 0xBF800000,
        0x7F7FFFFF, 0xFF7FFFFF, INF, 0xFF800000, QNAN, 0x7F800001,
        0x33000000, 0x33800000, 0x3F808000, 0x3F818000,
    )
    index = 0

    def row(engine, operation, a, b, stall):
        nonlocal index
        expected, error = arithmetic(engine, operation, a, b)
        index += 1
        return index, engine, operation, a, b, expected, error, stall

    for engine, operations in ((0, range(8)), (1, range(4))):
        for operation in operations:
            for a in edges:
                for b in edges if operation in (0, 1) else (0,):
                    yield row(engine, operation, a, b, index % 4)
            for seed in seeds:
                rng = XorShift32(seed)
                for _ in range(random_count):
                    yield row(engine, operation, rng.next(), rng.next(), index % 4)
    for half in range(65536) if exhaustive else (
            0, 1, 0x3FF, 0x400, 0x3C00, 0x7BFF, 0x7C00,
            0x7C01, 0x7E00, 0x8000, 0x8001, 0xBC00, 0xFC00, 0xFFFF):
        for operation in (2, 4):
            yield row(0, operation, half, 0, 1)
