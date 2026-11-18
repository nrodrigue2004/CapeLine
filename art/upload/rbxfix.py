"""Make a Roblox binary model that Lune (rbx-dom) can read, keeping its asset ids.

    python3 -I rbxfix.py IN OUT

- every chunk is written uncompressed (IN may be gzip, lz4 or zstd)
- PROP chunks rbx-dom misreads are dropped (MeshPart.Tags), they fall back to defaults
- Content-typed properties (type 0x22: MeshContent, TextureContent, ColorMapContent, ...) become the
  legacy string properties (MeshId, TextureID, ColorMap, ...) that rbx-dom and Rojo read, so the uploaded
  mesh and texture ids survive the round trip.
Prints a JSON summary of each class's converted ids.
"""

import gzip
import json
import struct
import sys

import lz4.block
import zstandard

DROP = {"Tags"}
LEGACY = {
    "MeshContent": "MeshId",
    "TextureContent": "TextureID",
    "ColorMapContent": "ColorMap",
    "NormalMapContent": "NormalMap",
    "RoughnessMapContent": "RoughnessMap",
    "MetalnessMapContent": "MetalnessMap",
}


def chunks(data):
    at = 32
    while at < len(data):
        name = data[at : at + 4]
        clen, ulen = struct.unpack_from("<II", data, at + 4)
        body = data[at + 16 : at + 16 + (clen or ulen)]
        at += 16 + (clen or ulen)
        if clen:
            if body[:4] == b"\x28\xb5\x2f\xfd":
                body = zstandard.ZstdDecompressor().decompress(body, max_output_size=ulen)
            else:
                body = lz4.block.decompress(body, uncompressed_size=ulen)
        yield name, body
        if name == b"END\0":
            break


def interleaved_i32(b, at, n):
    vals = []
    for i in range(n):
        raw = bytes(b[at + k * n + i] for k in range(4))
        v = struct.unpack(">I", raw)[0]
        vals.append((v >> 1) ^ -(v & 1))
    return vals, at + 4 * n


def content_uris(body, at, n):
    """The per-instance uri ('' when the source is not a Uri) of a type 0x22 Content property."""
    kinds, at = interleaved_i32(body, at, n)
    count = struct.unpack_from("<I", body, at)[0]
    at += 4
    uris = []
    for _ in range(count):
        ln = struct.unpack_from("<I", body, at)[0]
        uris.append(body[at + 4 : at + 4 + ln].decode())
        at += 4 + ln
    it = iter(uris)
    return [next(it) if k == 1 else "" for k in kinds]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if not data.startswith(b"<roblox!"):
        raise SystemExit("not a binary Roblox file: " + src)
    out = bytearray(data[:32])
    counts, classes, summary = {}, {}, {}
    for name, body in chunks(data):
        if name == b"INST":
            cid, ln = struct.unpack_from("<iI", body, 0)
            classes[cid] = body[8 : 8 + ln].decode()
            counts[cid] = struct.unpack_from("<I", body, 9 + ln)[0]
        if name == b"PROP":
            cid, ln = struct.unpack_from("<iI", body, 0)
            prop = body[8 : 8 + ln].decode()
            kind = body[8 + ln]
            if prop in DROP:
                continue
            if kind == 0x22:
                legacy = LEGACY.get(prop)
                if legacy is None:
                    continue  # an Object/None content rbx-dom can't place: leave it at its default
                uris = content_uris(body, 9 + ln, counts[cid])
                new = struct.pack("<iI", cid, len(legacy)) + legacy.encode() + b"\x01"
                for u in uris:
                    new += struct.pack("<I", len(u)) + u.encode()
                body = new
                s = summary.setdefault(classes[cid] + "." + legacy, [0, 0])
                s[0] += sum(1 for u in uris if u)
                s[1] += len(uris)
        out += name + struct.pack("<III", 0, len(body), 0) + body
    open(dst, "wb").write(bytes(out))
    print(json.dumps(summary))


main()
