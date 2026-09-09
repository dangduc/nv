#!/usr/bin/env python3
"""Compatibility entry point for the promoted native suite."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[4] / "Tests/FuzzySearch/Core/run.py"), run_name="__main__")
