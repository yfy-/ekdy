#!/usr/bin/env python3

import argparse
import gzip
import hashlib
import os
import os.path
import struct

from fastwarc.warc import ArchiveIterator, WarcRecordType
from resiliparse.parse.encoding import detect_encoding, bytes_to_str


def is_html_content_type(ct: str | None) -> bool:
    if ct is None:
        return False

    return ct == "text/html" or ct == "application/xhtml+xml"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(100 * 1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("warc_path")
    ap.add_argument("-c", "--cache-path", default=".warc-cache")
    args = ap.parse_args()

    warc_checksum = sha256_file(args.warc_path)
    out_path = os.path.join(args.cache_path, f"{warc_checksum}.htmlbin.gz")

    if os.path.exists(out_path):
        print(f"{out_path} already exists, so will save space!")
        return 0

    payload = bytearray()

    doc_count = 0
    with open(args.warc_path, "rb") as f:
        for record in ArchiveIterator(
            f,
            record_types=WarcRecordType.response,
            auto_decode="all",
        ):
            if not record.is_http:
                continue

            if not is_html_content_type(record.http_content_type):
                continue

            raw_html = record.reader.read()
            if not raw_html:
                continue

            doc_count += 1
            enc = record.http_charset or detect_encoding(
                raw_html,
                from_html_meta=True,
            )

            html = bytes_to_str(raw_html, encoding=enc or "utf-8")
            utf8_decoded = html.encode("utf-8")
            payload += struct.pack("<Q", len(utf8_decoded))
            payload += utf8_decoded

    os.makedirs(args.cache_path, exist_ok=True)
    with gzip.open(out_path, "wb") as ofs:
        ofs.write(payload)

    print(f"Wrote {doc_count} docs to {out_path}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
