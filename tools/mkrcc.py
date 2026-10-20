#!/usr/bin/env python3
"""Minimal Qt binary resource (.rcc, format v2) writer.

Usage: mkrcc.py OUT.rcc SRC_DIR [PREFIX]
Every file under SRC_DIR is embedded at qrc:/[PREFIX/]<relative path>, uncompressed.
"""
import os
import struct
import sys


def qt_hash(name):
    h = 0
    enc = name.encode("utf-16-be")
    for i in range(0, len(enc), 2):
        c = int.from_bytes(enc[i:i + 2], "big")
        h = ((h << 4) + c) & 0xFFFFFFFF
        g = h & 0xF0000000
        if g:
            h ^= g >> 23
        h &= ~g & 0xFFFFFFFF
    return h


class Node:
    def __init__(self, name, data=None):
        self.name = name
        self.data = data          # bytes for files, None for directories
        self.children = {}


def build_tree(src, prefix=""):
    root = Node("")
    for dirpath, _, files in os.walk(src):
        for f in files:
            if f.startswith("."):
                continue
            full = os.path.join(dirpath, f)
            parts = os.path.relpath(full, src).split(os.sep)
            if prefix:
                parts = prefix.strip("/").split("/") + parts
            node = root
            for p in parts[:-1]:
                node = node.children.setdefault(p, Node(p))
            with open(full, "rb") as fh:
                node.children[parts[-1]] = Node(parts[-1], fh.read())
    return root


def write_rcc(root, out):
    names, name_off = bytearray(), {}
    data = bytearray()

    def name_offset(n):
        if n not in name_off:
            name_off[n] = len(names)
            enc = n.encode("utf-16-be")
            names.extend(struct.pack(">HI", len(enc) // 2, qt_hash(n)) + enc)
        return name_off[n]

    # Breadth-first numbering; children of a directory are contiguous and sorted by hash.
    order = [root]
    first_child = {}
    i = 0
    while i < len(order):
        node = order[i]
        if node.data is None:
            kids = sorted(node.children.values(), key=lambda k: qt_hash(k.name))
            first_child[id(node)] = len(order)
            order.extend(kids)
        i += 1

    tree = bytearray()
    for node in order:
        noff = name_offset(node.name) if node is not root else 0
        if node.data is None:
            tree += struct.pack(">IHII", noff, 0x02, len(node.children), first_child[id(node)])
        else:
            doff = len(data)
            data.extend(struct.pack(">I", len(node.data)) + node.data)
            tree += struct.pack(">IHHHI", noff, 0x00, 0, 1, doff)  # AnyCountry, C language
        tree += struct.pack(">Q", 0)  # last modified

    header_len = 20
    tree_off = header_len
    data_off = tree_off + len(tree)
    names_off = data_off + len(data)
    with open(out, "wb") as fh:
        fh.write(b"qres" + struct.pack(">IIII", 2, tree_off, data_off, names_off))
        fh.write(tree)
        fh.write(data)
        fh.write(names)


if __name__ == "__main__":
    write_rcc(build_tree(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""), sys.argv[1])
