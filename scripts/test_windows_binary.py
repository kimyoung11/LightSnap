"""Security gate regression tests using a synthetic PE, never executing a file."""
import runpy
import struct
import unittest
from pathlib import Path

inspect = runpy.run_path(str(Path(__file__).with_name("verify-windows-binary.py")))["inspect"]


def fixture():
    data = bytearray(0xA00)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HH", data, 0x84, 0x8664, 1)
    struct.pack_into("<H", data, 0x94, 240)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x20B)
    struct.pack_into("<Q", data, optional + 24, 0x140000000)
    struct.pack_into("<H", data, optional + 70, 0x4160)
    struct.pack_into("<II", data, optional + 112 + 5 * 8, 0x1700, 16)
    struct.pack_into("<II", data, optional + 112 + 10 * 8, 0x1200, 148)
    struct.pack_into("<IIII", data, optional + 240 + 8, 0x800, 0x1000, 0x800, 0x200)
    struct.pack_into("<I", data, optional + 240 + 36, 0x60000020)
    struct.pack_into("<I", data, 0x400, 148)
    struct.pack_into("<Q", data, 0x400 + 88, 0x140001500)
    struct.pack_into("<QQQQI", data, 0x400 + 112,
                     0x140001500, 0x140001508, 0x140001600, 1, 0x500)
    return data


class BinaryGate(unittest.TestCase):
    def test_complete_protections(self):
        self.assertTrue(all(inspect(fixture())["checks"].values()))

    def test_cfg_flag_alone_is_insufficient(self):
        data = fixture()
        struct.pack_into("<I", data, 0x400 + 144, 0)
        checks = inspect(data)["checks"]
        self.assertTrue(checks["cfg_pe_flag"])
        self.assertFalse(checks["cfg_instrumented"])
        self.assertFalse(checks["cfg_function_table"])

    def test_executable_writable_section_is_rejected(self):
        data = fixture()
        struct.pack_into("<I", data, 0x98 + 240 + 36, 0xE0000020)
        self.assertFalse(inspect(data)["checks"]["no_writable_executable_sections"])

    def test_missing_cookie(self):
        data = fixture()
        struct.pack_into("<Q", data, 0x400 + 88, 0)
        self.assertFalse(inspect(data)["checks"]["stack_cookie"])

    def test_table_must_exist_in_file(self):
        data = fixture()
        struct.pack_into("<Q", data, 0x400 + 136, 100000)
        with self.assertRaises(ValueError):
            inspect(data)

    def test_truncated_and_wrong_architecture(self):
        for data in (b"MZ", fixture()[:0x200]):
            with self.assertRaises(ValueError):
                inspect(data)
        data = fixture()
        struct.pack_into("<H", data, 0x84, 0x14C)
        with self.assertRaises(ValueError):
            inspect(data)

    def test_missing_aslr_dep(self):
        data = fixture()
        struct.pack_into("<H", data, 0x98 + 70, 0x4000)
        checks = inspect(data)["checks"]
        self.assertFalse(checks["aslr"])
        self.assertFalse(checks["high_entropy_aslr"])
        self.assertFalse(checks["dep"])


if __name__ == "__main__":
    unittest.main()
