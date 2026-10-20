#!/usr/bin/env python3
"""Turn ECDICT's ecdict.csv into small JSON shards the QML app can load on demand.

Usage: build_dict.py ecdict.csv OUT_DIR

Each shard OUT_DIR/<k>.json (k = first two letters of the lowercased word) maps
word -> [phonetic, translation, lemma, tags]. Inflected forms (went, running, ...)
always carry their lemma so the app can show the base entry too.
"""
import csv
import json
import os
import re
import sys

TAG_NAMES = {"zk": "中考", "gk": "高考", "cet4": "四级", "cet6": "六级", "ky": "考研",
             "toefl": "托福", "ielts": "雅思", "gre": "GRE"}
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z'\-]*$")


def shard_key(w):
    k = w.lower()[:2]
    return k if re.fullmatch(r"[a-z]{1,2}", k) else "_"


def clean_translation(t):
    lines = [l.strip() for l in t.replace("\\n", "\n").split("\n") if l.strip()]
    core = [l for l in lines if not l.startswith("[网络]")]
    web = [l for l in lines if l.startswith("[网络]")]
    out = core[:5] or web[:1]
    if core and web and len(core) < 2:
        out += web[:1]
    s = "\n".join(out)
    return s[:300]


def main(src, out_dir):
    csv.field_size_limit(1 << 24)
    entries = {}
    lemma_of = {}
    with open(src, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            w = row["word"].strip()
            if not WORD_RE.match(w) or not row["translation"].strip():
                continue
            ex = dict(p.split(":", 1) for p in row["exchange"].split("/") if ":" in p)
            ranked = (int(row["bnc"] or 0) > 0 or int(row["frq"] or 0) > 0 or row["tag"]
                      or row["collins"] or row["oxford"] or "0" in ex)
            if not ranked:
                continue
            tags = " ".join(TAG_NAMES[t] for t in row["tag"].split() if t in TAG_NAMES)
            entries[w] = [row["phonetic"].strip(), clean_translation(row["translation"]), ex.get("0", ""), tags]
            for k in "pdi3srt":
                if k in ex:
                    for form in ex[k].split(","):
                        form = form.strip()
                        if form and form != w:
                            lemma_of.setdefault(form, w)

    # Make sure every inflected form resolves, even when ECDICT has no row for it.
    for form, lemma in lemma_of.items():
        if form in entries:
            if not entries[form][2]:
                entries[form][2] = lemma
        elif WORD_RE.match(form):
            entries[form] = ["", "", lemma, ""]

    shards = {}
    for w, e in entries.items():
        while e and e[-1] == "":
            e.pop()
        shards.setdefault(shard_key(w), {})[w] = e

    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for k, d in shards.items():
        with open(os.path.join(out_dir, k + ".json"), "w", encoding="utf-8") as fh:
            json.dump(d, fh, ensure_ascii=False, separators=(",", ":"))
        total += len(d)
    print(f"{total} entries in {len(shards)} shards")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
