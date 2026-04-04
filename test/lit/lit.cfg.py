"""lit configuration for COT compiler tests.

Reference: ~/claude/references/llvm-project/mlir/test/lit.cfg.py
This follows MLIR's standard lit test configuration pattern.
"""

import lit.formats
import os

config.name = "COT"
config.test_format = lit.formats.ShTest(True)
config.suffixes = ['.ac', '.zig', '.ts']

# Find tools
config.test_source_root = os.path.dirname(__file__)
project_root = os.path.join(os.path.dirname(__file__), '..', '..')

# Try new super-build location first, then legacy
new_cot = os.path.join(project_root, 'build', 'cot', 'cot')
old_cot = os.path.join(project_root, 'cot', 'build', 'cot')
cot_exe = new_cot if os.path.exists(new_cot) else old_cot

llvm_bin = '/opt/homebrew/Cellar/llvm@20/20.1.8/bin'

config.substitutions.append(('%cot', cot_exe))
config.substitutions.append(('%FileCheck', os.path.join(llvm_bin, 'FileCheck')))
