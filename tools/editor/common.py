"""Editor tooling uses the same verified Godot version and template cache as viewer."""
from pathlib import Path
import importlib.util
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('papng_native_common',ROOT/'tools/native/common.py')
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
PROJECT=ROOT/'demos/godot/editor';native.PROJECT=PROJECT
TOOLS=native.TOOLS;engine=native.engine;environment=native.environment;run_godot=native.run_godot
