"""Exact independent RMS/LayerNorm reductions at the admitted materializations."""

from fractions import Fraction

from numerical_reference import XorShift32, arithmetic, encode


def expected_norm(source, scale, layer_norm):
    fp = lambda operation, a, b=0: arithmetic(0, operation, a, b)[0]
    wide = [fp(2, value) for value in source]
    length = encode(Fraction(len(wide)))
    mean = 0
    if layer_norm:
        for value in wide:
            mean = fp(0, mean, value)
        mean = arithmetic(1, 0, mean, length)[0]
    centered = [fp(0, value, mean ^ 0x80000000) if layer_norm else value for value in wide]
    variance = 0
    for value in centered:
        variance = fp(0, variance, fp(1, value, value))
    variance = arithmetic(1, 0, variance, length)[0]
    variance = fp(0, variance, 0x358637BD)
    inverse = arithmetic(1, 2, variance, 0)[0]
    output = []
    for index, value in enumerate(centered):
        normalized = fp(1, value, inverse)
        if scale is not None:
            normalized = fp(1, normalized, fp(2, scale[index]))
        output.append(fp(3, normalized))
    return output


def norm_cases(production=False):
    lengths = (1, 3, 4, 8, 255, 256, 257, 511, 512, 513, 1536, 2560, 16384) if production else (
        1, 3, 4, 8)
    index = 0
    for seed in (17, 43, 89):
        for length in lengths:
            for layer_norm, learned in ((0, 0), (0, 1), (1, 1)):
                index += 1
                source = [encode(Fraction(((13 * seed + 5 * c + seed) & 31) - 16, 32),
                                 exponent_bits=8, fraction_bits=7) for c in range(length)]
                rng = XorShift32(seed)
                scales = [encode(1 + Fraction((rng.next() & 7) - 3, 64),
                                 exponent_bits=8, fraction_bits=7) for _ in range(length)]
                output = expected_norm(source, scales if learned else None, layer_norm)
                yield index, layer_norm, learned, source, scales, output
