# WASI IO Issues to Fix

Code review of the ARM64 WASI IO implementation found the following issues that need to be addressed.

## P0 - Critical Security

### 1. `cot_fd_open` stack buffer overflow

**File:** `compiler/driver.zig` (ARM64 `cot_fd_open` override, ~line 749)

The override allocates 1040 bytes on the stack and copies the path string byte-by-byte from linear memory. There is **no bounds check** on `path_len` before copying. If a user calls `@fd_open` with a path longer than 1024 bytes, the copy will overflow the stack buffer, causing stack corruption.

**Fix:** Add a bounds check before the copy loop. If `path_len > 1024`, return `-ENAMETOOLONG` (-36 on macOS, -36 on Linux) immediately.

### 2. `cot_arg_ptr` unbounded copy into linear memory

**File:** `compiler/driver.zig` (ARM64 `cot_arg_ptr` override, ~line 903)

The override copies `argv[n]` into linear memory at fixed offset `0xAF000` with **no length limit**. A very long command-line argument could write past the end of the reserved area into adjacent memory. The buffer starts at `linmem + 0xAF000 = vmctx + 0xEF000` and linear memory extends to roughly `vmctx + 0x100000`, giving ~68KB. Arguments longer than that would overflow.

**Fix:** Add a maximum copy length (e.g., 4096 bytes). Truncate if the argument is longer.

### 3. `cot_random` doesn't enforce `getentropy` 256-byte limit

**File:** `compiler/driver.zig` (ARM64 `cot_random` override, ~line 811)

macOS `getentropy()` (syscall 500) has a maximum buffer size of 256 bytes. The override passes the user's `len` directly without checking. If `len > 256`, the syscall fails with EINVAL and the buffer is left **uninitialized**. Code that ignores the return value would use uninitialized memory as "random" data.

**Fix:** Either loop for buffers > 256 bytes (calling getentropy multiple times), or clamp len to 256 and document the limit.

## P1 - Correctness

### 4. `cot_arg_ptr` shared buffer - successive calls overwrite

**File:** `compiler/driver.zig` (ARM64 `cot_arg_ptr` override, ~line 903)

All `@arg_ptr` calls write to the same fixed offset `0xAF000` in linear memory. This means:
```
var p0 = @arg_ptr(0);  // writes argv[0] to 0xAF000
var p1 = @arg_ptr(1);  // overwrites with argv[1] at 0xAF000!
// p0 now points to argv[1]'s data, not argv[0]
```

**Fix:** Either use different offsets per call (e.g., `0xAF000 + n * 4096`), or document that the pointer is only valid until the next `@arg_ptr` call.

### 5. `cot_arg_len` and `cot_arg_ptr` missing bounds checks

**File:** `compiler/driver.zig` (ARM64 overrides, ~lines 878, 903)

Neither `@arg_len(n)` nor `@arg_ptr(n)` checks if `n >= argc`. If `n` is out of bounds, the code reads `argv[n]` which is an invalid pointer, causing a segfault or reading garbage memory.

**Fix:** Load argc from `vmctx+0x30000`, compare `n >= argc`, return 0 (or -1) if out of bounds.

### 6. Platform-specific flag constants in test file

**File:** `test/e2e/wasi_io.cot` (lines 54, 64, 91)

The `@fd_open` calls use `1537` as the flags value. This is `O_WRONLY | O_CREAT | O_TRUNC` on **macOS only** (`1 + 512 + 1024 = 1537`). On Linux, the same flags are `1 + 64 + 512 = 577`.

**Fix:** Either:
- Add platform-conditional compilation to the test
- Use a different test that doesn't depend on platform-specific flag values
- Document that the test is macOS-only

### 7. Inconsistent error convention between `cot_fd_write_simple` and `wasi_fd_write`

**File:** `compiler/driver.zig`

- `cot_fd_write_simple` (line ~687): On error, negates errno → returns `-errno`
- `wasi_fd_write` (line ~858): On error, returns raw macOS errno (positive)

These two write functions return errors in different formats. If user code ever switches between them, the error handling would break.

**Fix:** Make `wasi_fd_write` also negate errno on error, or document the difference clearly.

### 8. `cot_time` uses `gettimeofday` with platform-specific struct layout

**File:** `compiler/driver.zig` (ARM64 `cot_time` override, ~line 787)

The override uses `SYS_gettimeofday` (116) and loads `tv_usec` as a 32-bit value at offset 24 (`ldr w9, [sp, #24]`). This assumes macOS ARM64's `struct timeval` layout where `tv_sec` is 8 bytes and `tv_usec` is 4 bytes.

On Linux x86-64, `struct timeval.tv_usec` is `long` (8 bytes), so the struct layout is different. The x64 port should use `clock_gettime` (syscall 228) instead, which returns `timespec` with `tv_sec` (8 bytes) + `tv_nsec` (8 bytes) - simpler math since nsec is already in nanoseconds.

**Fix:** This isn't a bug on ARM64, but note it for the x64 port - use `clock_gettime` with `CLOCK_REALTIME` (0) instead of `gettimeofday`.

## P2 - Code Quality

### 9. `compileAndRun` / `compileAndRunWithStdin` duplication

**File:** `compiler/codegen/native_e2e_test.zig`

These two functions are ~95% identical, differing only in how stdin is provided. Should be refactored into a single function with an optional stdin parameter.

### 10. Magic numbers should be named constants

**Files:** `compiler/driver.zig`, `test/e2e/wasi_io.cot`

| Magic Number | Meaning | Used In |
|---|---|---|
| `0xAF000` | arg string buffer offset in linear memory | `cot_arg_ptr` |
| `0x30000` | argc storage offset in vmctx | `_main` wrapper, `cot_args_count` |
| `0x30008` | argv storage offset in vmctx | `_main` wrapper, `cot_arg_len/ptr` |
| `0x40000` | linear memory base offset in vmctx | all overrides |
| `1537` | macOS O_WRONLY\|O_CREAT\|O_TRUNC | test file |

These should be defined as named constants.

## Summary

| # | Issue | Severity | Fix Effort |
|---|-------|----------|------------|
| 1 | fd_open stack buffer overflow | P0 Security | Small - add bounds check |
| 2 | arg_ptr unbounded copy | P0 Security | Small - add max length |
| 3 | random no 256-byte limit | P0 Security | Small - add loop or clamp |
| 4 | arg_ptr shared buffer | P1 Correctness | Medium - use per-arg offsets |
| 5 | arg_len/arg_ptr no bounds check | P1 Correctness | Small - check n < argc |
| 6 | Platform-specific flags in test | P1 Correctness | Small - conditional or doc |
| 7 | Inconsistent error convention | P1 Correctness | Small - pick one pattern |
| 8 | gettimeofday struct layout | P1 Note for x64 | N/A on ARM64 |
| 9 | Test function duplication | P2 Quality | Small - refactor |
| 10 | Magic numbers | P2 Quality | Small - add constants |
