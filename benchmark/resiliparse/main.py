#!/usr/bin/env python3

import argparse
import gzip
import time
from typing import List, Tuple
import struct
import sys

from resiliparse.extract.html2text import extract_plain_text


def load_html_docs(path: str) -> List[Tuple[str, int]]:
    docs: List[Tuple[str, int]] = []

    with gzip.open(path, "rb") as hfs:
        while len_bytes := hfs.read(8):
            html_size, = struct.unpack("<Q", len_bytes)
            html_bytes = hfs.read(html_size)
            docs.append((html_bytes.decode("utf-8"), html_size))

    return docs


def run_extract_benchmark(docs: List[str], repeats: int) -> List[Tuple[float, int]]:
    bench_out = [None] * len(docs)
    for r in range(repeats):
        print(f"Running iter: {r}", file=sys.stderr)
        for i, html in enumerate(docs):
            start = time.perf_counter()
            text = extract_plain_text(
                html, list_bullets=False, links=False, alt_texts=False, noscript=True
            )
            elapsed = time.perf_counter() - start
            num_bytes = len(bytes(text, encoding="utf-8"))
            if bench_out[i] is None or elapsed < bench_out[i][0]:
                bench_out[i] = (elapsed, num_bytes)

    return bench_out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("htmlbin_path")
    ap.add_argument("--repeats", type=int, default=5)
    args = ap.parse_args()
    docs = load_html_docs(args.htmlbin_path)
    if not docs:
        raise SystemExit("no HTML documents found")

    print(f"docs={len(docs)}", file=sys.stderr)
    total_in_bytes = sum(in_size for _, in_size in docs)
    print(f"total_in_bytes={total_in_bytes}", file=sys.stderr)

    times_and_out_sizes = run_extract_benchmark(list(d for d, _ in docs), args.repeats)
    total_sec = sum(t for t, _ in times_and_out_sizes)
    b_per_s = total_in_bytes / total_sec
    print(f"B/s={b_per_s:.3f}", file=sys.stderr)

    total_out_bytes = sum(s for _, s in times_and_out_sizes)
    print(f"total_out_bytes={total_out_bytes}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
