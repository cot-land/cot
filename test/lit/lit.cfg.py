"""lit configuration for COT compiler tests.

Reference: ~/claude/references/llvm-project/mlir/test/lit.cfg.py
This follows MLIR's standard lit test configuration pattern.
"""

import lit.formats
import os

config.name = "COT"
config.test_format = lit.formats.ShTest(True)
config.suffixes = ['.ac', '.zig']

# Find tools
config.test_source_root = os.path.dirname(__file__)
cot_build_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'cot', 'build')
llvm_bin = '/opt/homebrew/Cellar/llvm@20/20.1.8/bin'

config.substitutions.append(('%cot', os.path.join(cot_build_dir, 'cot')))
config.substitutions.append(('%FileCheck', os.path.join(llvm_bin, 'FileCheck')))
