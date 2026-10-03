"""Reject changed dependency archives before extraction."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

path = Path(__file__).resolve().parents[2] / ".github/scripts/build-arm64-dependencies.py"
spec = importlib.util.spec_from_file_location("dependencies", path)
dependencies = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dependencies)


class DependencyArchiveTests(unittest.TestCase):
    def test_checksum_failure_extracts_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            archive = work / "source.tar.gz"
            archive.write_bytes(b"changed source archive")
            destination = work / "extracted"
            destination.mkdir()
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                dependencies.unpack(archive, destination, "0" * 64)
            self.assertEqual(list(destination.iterdir()), [])

    def test_verified_archive_cannot_escape_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            archive = work / "source.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                member = tarfile.TarInfo("../escaped")
                member.size = 1
                output.addfile(member, io.BytesIO(b"x"))
            destination = work / "extracted"
            destination.mkdir()
            with self.assertRaises(tarfile.FilterError):
                dependencies.unpack(archive, destination, hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertFalse((work / "escaped").exists())
