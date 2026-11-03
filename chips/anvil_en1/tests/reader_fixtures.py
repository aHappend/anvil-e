"""Directory-only fixtures: virtual payload extents, never neural input answers."""

import struct


def text_shapes(model):
    if model not in (1, 2):
        raise ValueError("native model required")
    layers, owners, hidden, intermediate, heads, period = (
        (35, 15, 1536, 6144, 1, 5) if model == 1 else
        (42, 24, 2560, 10240, 2, 6))
    for kind, dims in (
            (0, (262144, hidden)), (1, (262144, layers * 256)),
            (2, (layers * 256, hidden)), (3, (256,)), (4, (hidden,))):
        yield kind, 0xFFFF, dims, len(dims) == 2, 0
    for layer in range(layers):
        dimension = 512 if (layer + 1) % period == 0 else 256
        width = intermediate * (2 if model == 1 and layer >= owners else 1)
        shapes = (
            (0x100, (hidden,)), (0x101, (8 * dimension, hidden)),
            (0x102, (dimension,)), (0x103, (heads * dimension, hidden)),
            (0x104, (dimension,)), (0x105, (heads * dimension, hidden)),
            (0x106, (hidden, 8 * dimension)), (0x107, (hidden,)),
            (0x108, (hidden,)), (0x109, (width, hidden)),
            (0x10A, (width, hidden)), (0x10B, (hidden, width)),
            (0x10C, (hidden,)), (0x10D, (256, hidden)),
            (0x10E, (hidden, 256)), (0x10F, (hidden,)), (0x110, ()),
        )
        for kind, dims in shapes:
            if layer >= owners and kind in (0x103, 0x104, 0x105):
                continue
            yield kind, layer, dims, len(dims) == 2, 0


def input_shapes(audio, items):
    if not 0 < items < 1 << 32:
        raise ValueError("nonzero 32-bit original input extent required")
    if audio:
        yield 0x3010, 0xFFFF, (items, 128), False, 0
        yield 0x3011, 0xFFFF, (items,), False, 2
    else:
        yield 0x3000, 0xFFFF, (items, 768), False, 0
        yield 0x3001, 0xFFFF, (items, 2), False, 3


def directory_image(model, precision, shapes, image_class=0):
    """Return only readable directory bytes, with valid 64-bit virtual payloads.

    The reader must not read payload in this test. No huge sparse file, weight
    tensor or host allocation is used to represent those validated extents.
    """
    shapes = list(shapes)
    entries = []
    offset = 64 + 64 * len(shapes)
    for kind, layer, dims, matrix, scalar_type in shapes:
        dtype = precision if matrix else scalar_type
        rows, columns = dims if len(dims) == 2 else (1, dims[0] if dims else 1)
        if dtype == 0:
            stride = (columns + 1) // 2 * 4
        elif dtype == 1:
            stride = (18 * ((columns + 31) // 32) + 3) // 4 * 4
        else:
            stride = columns * 4
        length = rows * stride
        if stride >= 1 << 32 or offset + length >= 1 << 64:
            raise ValueError("unrepresentable tensor image extent")
        entry = bytearray(64)
        struct.pack_into("<HHBBHQQ", entry, 0, kind, layer, dtype, len(dims), 0,
                         offset, length)
        struct.pack_into("<4II", entry, 24, *(dims + (1,) * (4 - len(dims))), stride)
        entries.append(entry)
        offset += length
    header = bytearray(64)
    struct.pack_into("<4IQIIQ", header, 0,
                     0x31494E41 if image_class == 3 else 0x31564E41,
                     0x10000, model, 0 if image_class == 3 else precision,
                     offset, len(entries), 64, 64)
    return bytes(header + b"".join(entries))
