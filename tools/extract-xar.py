#!/usr/bin/env python3
"""Extract a XAR archive after validating member paths, sizes, and checksums."""

import bz2
import gzip
import hashlib
import lzma
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib


def fail(message):
    raise SystemExit(message)


if len(sys.argv) != 3:
    fail(f"usage: {sys.argv[0]} ARCHIVE OUTPUT_DIRECTORY")

archive_path, output_root = sys.argv[1:]
output_root = os.path.abspath(output_root)

with open(archive_path, "rb") as archive:
    header = archive.read(28)
    if len(header) != 28:
        fail("truncated XAR header")
    magic, header_size, version, toc_compressed, toc_size, _ = struct.unpack(
        ">IHHQQI", header
    )
    if magic != 0x78617221 or header_size < 28 or version != 1:
        fail("unsupported XAR header")
    archive.seek(header_size)
    toc_blob = archive.read(toc_compressed)
    toc = zlib.decompress(toc_blob)
    if len(toc) != toc_size:
        fail("XAR TOC size mismatch")
    root = ET.fromstring(toc)
    heap_start = header_size + toc_compressed

    def extract_member(node, parent_parts):
        name = node.findtext("name")
        if not name or name in (".", "..") or "/" in name or "\0" in name:
            fail(f"unsafe XAR member name: {name!r}")
        parts = parent_parts + [name]
        target = os.path.abspath(os.path.join(output_root, *parts))
        if not target.startswith(output_root + os.sep):
            fail(f"XAR member escapes output root: {target}")

        kind = node.findtext("type")
        if kind == "directory":
            os.makedirs(target, exist_ok=True)
        elif kind == "file":
            data = node.find("data")
            if data is None:
                fail(f"missing XAR data metadata: {target}")
            offset = int(data.findtext("offset"))
            length = int(data.findtext("length"))
            size = int(data.findtext("size"))
            if min(offset, length, size) < 0:
                fail(f"negative XAR data extent: {target}")
            archive.seek(heap_start + offset)
            payload = archive.read(length)
            if len(payload) != length:
                fail(f"truncated XAR member: {target}")
            style = data.find("encoding").attrib.get(
                "style", "application/octet-stream"
            )
            if style in ("application/octet-stream", "application/x-none"):
                decoded = payload
            elif style == "application/x-gzip":
                decoded = zlib.decompress(payload)
            elif style == "application/gzip":
                decoded = gzip.decompress(payload)
            elif style == "application/x-bzip2":
                decoded = bz2.decompress(payload)
            elif style in ("application/x-lzma", "application/x-xz"):
                decoded = lzma.decompress(payload)
            else:
                fail(f"unsupported XAR encoding {style}: {target}")
            if len(decoded) != size:
                fail(f"XAR member size mismatch: {target}")
            extracted = data.find("extracted-checksum")
            if extracted is not None and extracted.text:
                algorithm = extracted.attrib.get("style")
                digest = hashlib.new(algorithm, decoded).hexdigest()
                if digest.lower() != extracted.text.strip().lower():
                    fail(f"XAR member checksum mismatch: {target}")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as output:
                output.write(decoded)
        elif kind not in ("symlink", None):
            fail(f"unsupported XAR member type {kind}: {target}")

        for child in node.findall("file"):
            extract_member(child, parts)

    os.makedirs(output_root, exist_ok=True)
    toc_node = root.find("toc")
    if toc_node is None:
        fail("missing XAR TOC")
    for member in toc_node.findall("file"):
        extract_member(member, [])
