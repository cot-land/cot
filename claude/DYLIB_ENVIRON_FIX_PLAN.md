# Execution Plan: Fix environ access in dylib mode

## Status: IMPLEMENTED (Feb 27, 2026)

**Note**: The plan was for the wasm-based path (`generateLibWrappersMachO`). The actual fix targeted the direct native path (`generateMachODirect`) which is the default. The fix maps `envp_symbol_idx` to `_environ` (POSIX libc global) with `colocated: false` in CLIF IR, generating proper GOT relocations. Also fixed `machORelocType` to correctly emit `ARM64_RELOC_GOT_LOAD_PAGE21` (type 5) and `ARM64_RELOC_GOT_LOAD_PAGEOFF12` (type 6), and fixed `addDataRelocation` to set `pc_rel=true` for GOT page relocations.

## Problem

When Cot code is compiled as a dylib (`cot build --lib`), the `environ_count()`, `environ_len()`, and `environ_ptr()` runtime functions crash with SIGSEGV because the envp pointer at `vmctx + 0x30010` is never initialized.

In executable mode, the `_main` wrapper stores envp from C main's third argument:
```asm
// driver.zig ~line 2944-2951 (executable main wrapper)
add x10, x0, #0x30, lsl #12   // x10 = vmctx + 0x30000
str x19, [x10]                 // argc
str x20, [x10, #8]             // argv
str x21, [x10, #16]            // envp ← initialized from C main's x2
```

In dylib mode, `generateLibWrappersMachO` only initializes the heap base pointer — NO argc/argv/envp initialization. The vmctx data section is zero-filled, so envp = NULL → SIGSEGV when `environ_count()` dereferences it.

**Impact**: ALL stdlib process functions that use `buildEnvp()` crash from dylibs: `run()`, `run0()`, `run2()`, `output()`, `output0()`, etc.

**Verified**: fork+alloc+execve works correctly from dylibs when envp is skipped (`emptyEnvp()`). The bug is solely about envp initialization.

## Reference Implementations

| System | How environ is accessed in shared libraries |
|--------|---------------------------------------------|
| **POSIX standard** | `extern char **environ` — global variable maintained by libc |
| **Go c-shared** | `goenvs_unix()` reads `argv[argc+1...]` — envp computed from argv |
| **Zig stdlib** | Receives `envp` as argument to `_start`, stores in `std.os.environ` |
| **WASI** | `environ_get()` / `environ_sizes_get()` — explicit host function calls |
| **Cot executable** | `_main(argc, argv, envp)` stores envp at `vmctx + 0x30010` |

The POSIX-standard approach for shared libraries is `extern char **environ`. This is a global variable provided by libc, available in any process that links libc. Dylibs don't receive envp as an argument — they access it through this global.

## Approach

Two-part fix, porting directly from existing Cot patterns:

**Part 1**: In `generateLibWrappersMachO`, add envp initialization by reading from the POSIX `extern char **environ` global. Port the same ADRP+ADD+LDR pattern already used for `_cot_envp` in the executable main wrapper.

**Part 2**: Add null-check safety to `environ_count/len/ptr` assembly so they return 0 instead of crashing when envp is NULL. Port from Go's defensive null-checking pattern in `goenvs_unix`.

## Step 1: Declare `_environ` as undefined external symbol

**File**: `compiler/driver.zig`, inside `generateLibWrappersMachO`

After declaring `_vmctx_data` (line 3236-3243), declare `_environ` as an undefined external symbol:

```zig
// Declare _environ (POSIX libc global: extern char **environ)
// On macOS, this is provided by libSystem and resolved by dyld at load time.
const environ_ext_idx = next_ext_idx;
next_ext_idx += 1;
const environ_name_ref = ExternalName{ .User = .{ .namespace = 0, .index = environ_ext_idx } };
try module.declareExternalName(environ_ext_idx, "_environ");
```

**Reference**: Same pattern as how libc functions (`_malloc`, `_free`, `_fork`) are declared as undefined symbols — the linker resolves them from libSystem.

**Note**: On Linux, the symbol is `environ` (no leading underscore). The existing `is_macos` flag in driver.zig handles this prefix convention.

## Step 2: Add envp initialization to each dylib wrapper function

**File**: `compiler/driver.zig`, inside the per-export wrapper loop in `generateLibWrappersMachO` (~line 3287-3328)

After the heap base initialization (lines 3311-3316) and before the `mov x1, x0` (line 3318), add:

```asm
// Load environ from POSIX libc global
// On macOS arm64, the linker resolves _environ via GOT automatically
// when it sees ADRP+ADD targeting an external data symbol.
adrp x10, _environ@PAGE                    // reloc: Aarch64AdrPrelPgHi21
add  x10, x10, _environ@PAGEOFF            // reloc: Aarch64AddAbsLo12Nc
ldr  x10, [x10]                            // x10 = *_environ = envp pointer

// Store envp at vmctx + 0x30010 (idempotent, same as executable main wrapper)
add  x11, x0, #0x30, lsl #12               // x11 = vmctx + 0x30000
str  x10, [x11, #16]                        // envp at vmctx + 0x30010
str  xzr, [x11]                             // argc = 0 (no command-line args in dylib)
str  xzr, [x11, #8]                         // argv = NULL
```

**Reference pattern**: Lines 2944-2951 of the executable `__cot_main` wrapper do the same store at `vmctx + 0x30000/0x30008/0x30010`, just with different source registers.

**Relocations to add** (append to the `wrapper_relocs` array):
```zig
// ADRP x10, _environ@PAGE
.{
    .offset = adrp_environ_offset,
    .kind = Reloc.Aarch64AdrPrelPgHi21,
    .target = FinalizedRelocTarget{ .ExternalName = environ_name_ref },
    .addend = 0,
},
// ADD x10, x10, _environ@PAGEOFF
.{
    .offset = add_environ_offset,
    .kind = Reloc.Aarch64AddAbsLo12Nc,
    .target = FinalizedRelocTarget{ .ExternalName = environ_name_ref },
    .addend = 0,
},
```

**macOS linker behavior**: When the linker sees `Aarch64AdrPrelPgHi21` + `Aarch64AddAbsLo12Nc` targeting an undefined external data symbol (`_environ`), it automatically rewrites the ADRP+ADD to use GOT indirection (ADRP to GOT page, LDR from GOT slot). This is documented as "GOT transform" in Apple's ld64 source. No explicit GOT relocation types needed.

**Encoding**: Use the existing `A64` instruction encoder helpers:
```zig
// adrp x10, _environ@PAGE
try appendInst(&code, self.allocator, A64.adrp(10));
// add x10, x10, _environ@PAGEOFF
try appendInst(&code, self.allocator, A64.add_pageoff(10, 10));
// ldr x10, [x10]  (dereference environ pointer)
try appendInst(&code, self.allocator, 0xF940014A);  // LDR x10, [x10]
// add x11, x0, #0x30, lsl #12
try appendInst(&code, self.allocator, A64.add_imm_lsl12(11, 0, 0x30));
// str x10, [x11, #16]
try appendInst(&code, self.allocator, A64.str_imm(10, 11, 16));
// str xzr, [x11]
try appendInst(&code, self.allocator, A64.str_imm(31, 11, 0));
// str xzr, [x11, #8]
try appendInst(&code, self.allocator, A64.str_imm(31, 11, 8));
```

## Step 3: Add null-check safety to environ functions

**File**: `compiler/driver.zig`

Add `cbz x9, .done` after loading the envp pointer in each environ function. This prevents crashes if envp is NULL for any reason (e.g., a platform that doesn't provide `_environ`).

### environ_count (line 1925)

Current:
```asm
add x8, x0, #0x30, lsl #12     // x8 = vmctx + 0x30000
ldr x9, [x8, #16]               // x9 = envp
movz x0, #0                     // count = 0
// .loop:
ldr x10, [x9, x0, lsl #3]      // x10 = envp[count]  ← CRASHES if x9=0
```

Fixed (add one instruction after `ldr x9`):
```asm
add x8, x0, #0x30, lsl #12     // x8 = vmctx + 0x30000
ldr x9, [x8, #16]               // x9 = envp
cbz x9, .done                   // NULL envp → return 0
movz x0, #0                     // count = 0
// .loop: ...
```

**Reference**: Go's `goenvs_unix()` at `references/go/src/runtime/runtime1.go:83-96` loops until `argv_index(argv, argc+1+n) != nil` — implicit null guard via the loop condition.

### environ_len (line 1941)

Add `cbz x9, .null` early (already has a null branch but it checks AFTER deref):

Current line 1944: `ldr x9, [x9, x2, lsl #3]` — this loads `envp[n]`. If `envp` (x9 from line 1943) is NULL, this crashes.

Fix: Add a null check for the envp pointer before indexing:
```asm
ldr x9, [x8, #16]               // x9 = envp
cbz x9, .null                   // NULL envp → return 0  (NEW)
ldr x9, [x9, x2, lsl #3]       // x9 = envp[n]
```

### environ_ptr (line 1962)

Same pattern — add null check for envp after loading from vmctx:
```asm
ldr x9, [x8, #16]               // x9 = envp
cbz x9, .null                   // NULL envp → return 0  (NEW)
ldr x9, [x9, x2, lsl #3]       // x9 = envp[n]
```

### x64 equivalents (lines 3792-3870)

Apply the same null-check pattern to the x64 implementations:
```asm
mov rax, [rdi + 0x30010]        // rax = envp
test rax, rax                   // check NULL
jz .done                        // NULL → return 0
```

## Step 4: Fix `machORelocType` for GOT relocations (if needed)

**File**: `compiler/codegen/native/object_module.zig`, line 640

Current code maps `Arm64AdrGotPage21` to `ARM64_RELOC_PAGE21` (type 3). The correct Mach-O type for GOT page references is `ARM64_RELOC_GOT_LOAD_PAGE21` (type 5).

However, Step 2 uses `Aarch64AdrPrelPgHi21` (non-GOT) and relies on the macOS linker's automatic GOT transform for external symbols. If this works (most likely), then no changes to `machORelocType` are needed.

**Test first**: If the linker complains about referencing `_environ` with non-GOT relocations, then fix the reloc mapping:
```zig
.Arm64AdrGotPage21 => 5,  // ARM64_RELOC_GOT_LOAD_PAGE21
.Arm64Ld64GotLo12Nc => 6, // ARM64_RELOC_GOT_LOAD_PAGEOFF12
```

And switch Step 2 to use explicit GOT relocation types.

## Step 5: Verification

### Test 1: environ_count from dylib (was crashing)

```bash
cat > /tmp/test_envp.cot << 'EOF'
import "std/sys"
export fn testEnvCount() i64 { return environ_count() }
EOF
cot build /tmp/test_envp.cot --lib -o /tmp/libtest_envp.dylib

cat > /tmp/test_host.c << 'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main() {
    void *lib = dlopen("/tmp/libtest_envp.dylib", RTLD_NOW);
    long (*fn)(void) = dlsym(lib, "testEnvCount");
    printf("environ_count: %ld\n", fn());  // Should print > 0, NOT crash
    dlclose(lib);
}
EOF
cc -o /tmp/test_host /tmp/test_host.c && /tmp/test_host
```

### Test 2: run0() from dylib (was returning wrong exit code)

```bash
cat > /tmp/test_run.cot << 'EOF'
import "std/sys"
import "std/process"
export fn testRun0False() i64 { return run0("/usr/bin/false") }
export fn testRun0True() i64 { return run0("/usr/bin/true") }
EOF
cot build /tmp/test_run.cot --lib -o /tmp/libtest_run.dylib

cat > /tmp/test_host2.c << 'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main() {
    void *lib = dlopen("/tmp/libtest_run.dylib", RTLD_NOW);
    long (*fn_true)(void) = dlsym(lib, "testRun0True");
    long (*fn_false)(void) = dlsym(lib, "testRun0False");
    printf("true: %ld (expect 0)\n", fn_true());
    printf("false: %ld (expect 1)\n", fn_false());
    dlclose(lib);
}
EOF
cc -o /tmp/test_host2 /tmp/test_host2.c && /tmp/test_host2
```

### Test 3: Existing standalone tests still pass

```bash
cot test test/e2e/process.cot          # All 13 tests pass
cot test test/e2e/features.cot         # 341 tests pass
```

### Test 4: output() from dylib (captures stdout)

```bash
cat > /tmp/test_output.cot << 'EOF'
import "std/sys"
import "std/process"
export fn testOutput() i64 {
    var result = output("/bin/echo", "hello")
    return @lenOf(result)
}
EOF
cot build /tmp/test_output.cot --lib -o /tmp/libtest_output.dylib
# Host: call testOutput(), expect 6 ("hello\n")
```

## Key Files

| File | Lines | Change |
|------|-------|--------|
| `compiler/driver.zig` | 3245-3360 | Add envp initialization to dylib wrapper |
| `compiler/driver.zig` | 1925-1935 | Add null-check to `arm64_environ_count` |
| `compiler/driver.zig` | 1941-1957 | Add null-check to `arm64_environ_len` |
| `compiler/driver.zig` | 1962-1993 | Add null-check to `arm64_environ_ptr` |
| `compiler/driver.zig` | 3792-3870 | Add null-check to x64 environ functions |

## What This Does NOT Fix

- **argc/argv from dylib**: Command-line arguments are not meaningful for dylibs (the host has its own args). Setting argc=0, argv=NULL is correct.
- **x64 dylib wrappers**: `generateLibWrappersMachO` is macOS-only. x64/Linux dylib support (`generateLibWrappersELF`) doesn't exist yet.
- **Cotty PTY spawning**: The environ fix unblocks `run0()/run()/output()` from dylibs. Cotty's PTY spawning uses a different code path (`Pty.spawn()`) that may have separate issues.

## Risk Assessment

- **Low risk**: Adding null-checks to environ functions (Part 2) is purely defensive
- **Medium risk**: The ADRP+ADD → GOT transform for `_environ` relies on macOS linker behavior. If it doesn't work, fall back to explicit GOT relocs (Step 4).
- **No risk to existing tests**: Executable mode is unchanged — envp is still stored from main's arguments
