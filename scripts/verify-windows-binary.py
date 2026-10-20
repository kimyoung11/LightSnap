#!/usr/bin/env python3
"""Validate MSVC x64 release protections without executing the PE file."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def inspect(data):
    def unpack(fmt, offset):
        size = struct.calcsize(fmt)
        if offset < 0 or offset + size > len(data):
            raise ValueError("Truncated PE structure")
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b"MZ":
        raise ValueError("Missing DOS header")
    pe, = unpack("<I", 0x3C)
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Missing PE signature")
    machine, sections = unpack("<HH", pe + 4)
    optional_size, = unpack("<H", pe + 20)
    optional = pe + 24
    magic, = unpack("<H", optional)
    if machine != 0x8664 or magic != 0x20B or optional_size < 240:
        raise ValueError("Expected x64 PE32+ executable")
    flags, = unpack("<H", optional + 70)
    image_base, = unpack("<Q", optional + 24)
    section_table = optional + optional_size
    entries = []
    writable_executable = False
    for index in range(sections):
        at = section_table + index * 40
        virtual_size, virtual_address, raw_size, raw = unpack("<IIII", at + 8)
        characteristics, = unpack("<I", at + 36)
        writable_executable |= bool(characteristics & 0x20000000 and characteristics & 0x80000000)
        entries.append((virtual_address, virtual_size, raw, raw_size))

    def rva_offset(rva, size):
        for address, virtual_size, raw, raw_size in entries:
            if address <= rva and rva + size <= address + raw_size:
                offset = raw + rva - address
                if offset + size <= len(data):
                    return offset
        raise ValueError("Invalid or unbacked RVA")

    config_rva, config_size = unpack("<II", optional + 112 + 10 * 8)
    if config_size < 148:
        raise ValueError("Missing CFG load configuration")
    config = rva_offset(config_rva, 148)
    actual_size, = unpack("<I", config)
    if actual_size < 148:
        raise ValueError("CFG load configuration is too short")
    cookie, = unpack("<Q", config + 88)
    check, dispatch, table, count = unpack("<QQQQ", config + 112)
    guard_flags, = unpack("<I", config + 144)
    reloc_rva, reloc_size = unpack("<II", optional + 112 + 5 * 8)
    checks = {
        "aslr": bool(flags & 0x40),
        "high_entropy_aslr": bool(flags & 0x20),
        "dep": bool(flags & 0x100),
        "cfg_pe_flag": bool(flags & 0x4000),
        "cfg_instrumented": bool(guard_flags & 0x100),
        "cfg_function_table": bool(guard_flags & 0x400 and table and count and check and dispatch),
        "stack_cookie": bool(cookie),
        "relocations_present": bool(reloc_rva and reloc_size),
        "no_writable_executable_sections": not writable_executable,
    }
    if table and count:
        # Validate that the declared CFG table is backed by actual file bytes.
        stride = 4 + ((guard_flags >> 28) & 0xF)
        rva_offset(table - image_base, count * stride)
    return {"sha256": hashlib.sha256(data).hexdigest(), "architecture": "x64", "checks": checks,
            "scope": "Static PE checks only; not an antivirus verdict or Authenticode verification."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = inspect(args.executable.read_bytes())
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    if not all(report["checks"].values()):
        raise SystemExit("Required Windows binary protections are missing")


if __name__ == "__main__":
    main()
