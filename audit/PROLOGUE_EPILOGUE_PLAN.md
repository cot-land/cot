# Prologue/Epilogue Implementation Plan

**Date:** February 3, 2026
**Task:** #105 - Implement prologue/epilogue generation
**Reference:** `~/learning/wasmtime/cranelift/codegen/src/machinst/abi.rs`

## Overview

This plan ports Cranelift's frame layout and prologue/epilogue generation to Cot. The implementation follows Cranelift's architecture exactly.

---

## Phase 1: FrameLayout Struct

**File:** `compiler/codegen/native/machinst/abi.zig`
**Reference:** `cranelift/codegen/src/machinst/abi.rs:1035-1092`

### 1.1 Add FrameLayout struct

```zig
/// Structure describing the layout of a function's stack frame.
/// Port of cranelift/codegen/src/machinst/abi.rs FrameLayout
pub const FrameLayout = struct {
    /// Word size in bytes.
    word_bytes: u32,

    /// Size of incoming arguments on the stack.
    incoming_args_size: u32,

    /// Size of incoming args including space for tail calls.
    tail_args_size: u32,

    /// Size of the setup area (return address + frame pointer).
    setup_area_size: u32,

    /// Size of callee-saved register save area.
    clobber_size: u32,

    /// Size of fixed frame storage (stack slots + spill slots).
    fixed_frame_storage_size: u32,

    /// Size of all stack slots.
    stackslots_size: u32,

    /// Size reserved for outgoing call arguments.
    outgoing_args_size: u32,

    /// Clobbered callee-saved registers to save/restore.
    clobbered_callee_saves: []const Writable(RealReg),

    /// Function call classification.
    function_calls: FunctionCalls,

    const Self = @This();

    /// Size of FP to SP while frame is active.
    pub fn activeSize(self: Self) u32 {
        return self.outgoing_args_size + self.fixed_frame_storage_size + self.clobber_size;
    }

    /// Offset from SP to sized stack slots area.
    pub fn spToSizedStackSlots(self: Self) u32 {
        return self.outgoing_args_size;
    }

    /// Offset of a spill slot from SP.
    pub fn spillslotOffset(self: Self, spillslot: SpillSlot) i64 {
        const islot: i64 = @intCast(spillslot.index());
        const spill_off = islot * @as(i64, self.word_bytes);
        return @as(i64, self.stackslots_size) + spill_off;
    }

    /// Offset from SP to FP.
    pub fn spToFp(self: Self) u32 {
        return self.outgoing_args_size + self.fixed_frame_storage_size + self.clobber_size;
    }
};
```

### 1.2 Add FunctionCalls enum

```zig
/// Classification of function calls in the function.
/// Port of cranelift/codegen/src/machinst/abi.rs FunctionCalls
pub const FunctionCalls = enum {
    /// No function calls.
    none,
    /// Contains normal function calls.
    normal,
    /// Contains tail calls.
    tail,
};
```

---

## Phase 2: Callee Struct

**File:** `compiler/codegen/native/machinst/abi.zig`
**Reference:** `cranelift/codegen/src/machinst/abi.rs:1136-1180`

### 2.1 Add Callee struct

```zig
/// ABI object for a function body.
/// Port of cranelift/codegen/src/machinst/abi.rs Callee
pub fn Callee(comptime M: type) type {
    return struct {
        allocator: Allocator,

        /// Calling convention.
        call_conv: CallConv,

        /// Offsets to each sized stackslot.
        sized_stackslots: std.ArrayListUnmanaged(u32),

        /// Total size of all stackslots.
        stackslots_size: u32,

        /// Size reserved for outgoing arguments.
        outgoing_args_size: u32,

        /// Computed frame layout (set by compute_frame_layout).
        frame_layout: ?FrameLayout,

        const Self = @This();

        /// Initialize a Callee from a CLIF Function.
        /// Port of cranelift/codegen/src/machinst/abi.rs Callee::new
        pub fn init(
            allocator: Allocator,
            f: *const Function,
            call_conv: CallConv,
        ) !Self {
            var sized_stackslots = std.ArrayListUnmanaged(u32){};
            var end_offset: u32 = 0;

            // Compute sized stackslot locations
            // Port of cranelift abi.rs:1237-1260
            for (f.stack_slots.items) |data| {
                // Align to word boundary or requested alignment
                const align = @max(M.word_bytes, @as(u32, 1) << data.align_shift);
                const mask = align - 1;
                const start_offset = (end_offset + mask) & ~mask;

                // End offset is start + size
                end_offset = start_offset + data.size;

                try sized_stackslots.append(allocator, start_offset);
            }

            // Word-align total stackslots size
            const mask = M.word_bytes - 1;
            const stackslots_size = (end_offset + mask) & ~mask;

            return Self{
                .allocator = allocator,
                .call_conv = call_conv,
                .sized_stackslots = sized_stackslots,
                .stackslots_size = stackslots_size,
                .outgoing_args_size = 0,
                .frame_layout = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sized_stackslots.deinit(self.allocator);
        }

        /// Get the offset of a sized stack slot.
        pub fn sizedStackslotOffset(self: Self, slot: StackSlot) u32 {
            return self.sized_stackslots.items[slot.asU32()];
        }

        /// Accumulate outgoing args size (called during lowering).
        pub fn accumulateOutgoingArgsSize(self: *Self, size: u32) void {
            self.outgoing_args_size = @max(self.outgoing_args_size, size);
        }

        /// Compute frame layout post-regalloc.
        /// Port of cranelift abi.rs:2201-2224
        pub fn computeFrameLayout(
            self: *Self,
            spillslots: usize,
            clobbered: []const Writable(RealReg),
            function_calls: FunctionCalls,
        ) void {
            const bytes = M.word_bytes;
            var total_stacksize = self.stackslots_size + bytes * @as(u32, @intCast(spillslots));
            const mask = M.stack_align - 1;
            total_stacksize = (total_stacksize + mask) & ~mask;

            self.frame_layout = M.computeFrameLayout(
                self.call_conv,
                clobbered,
                function_calls,
                0, // incoming_args_size (simplified for now)
                0, // tail_args_size
                self.stackslots_size,
                total_stacksize,
                self.outgoing_args_size,
            );
        }

        /// Get the computed frame layout.
        pub fn frameLayout(self: Self) *const FrameLayout {
            return &(self.frame_layout orelse @panic("frame layout not computed"));
        }
    };
}
```

---

## Phase 3: ABIMachineSpec Trait

**File:** `compiler/codegen/native/machinst/abi.zig`
**Reference:** `cranelift/codegen/src/machinst/abi.rs:470-520`

### 3.1 Define ABIMachineSpec interface

```zig
/// Machine-specific ABI implementation.
/// ISA backends must implement these functions.
pub fn ABIMachineSpec(comptime Self: type) type {
    return struct {
        /// Word size in bytes (8 for 64-bit).
        pub const word_bytes: u32 = Self.word_bytes;

        /// Stack alignment requirement.
        pub const stack_align: u32 = Self.stack_align;

        /// Compute frame layout for this machine.
        pub fn computeFrameLayout(
            call_conv: CallConv,
            clobbered: []const Writable(RealReg),
            function_calls: FunctionCalls,
            incoming_args_size: u32,
            tail_args_size: u32,
            stackslots_size: u32,
            fixed_frame_storage_size: u32,
            outgoing_args_size: u32,
        ) FrameLayout {
            return Self.computeFrameLayout(
                call_conv, clobbered, function_calls,
                incoming_args_size, tail_args_size, stackslots_size,
                fixed_frame_storage_size, outgoing_args_size,
            );
        }

        /// Generate prologue frame setup.
        pub fn genPrologueFrameSetup(
            call_conv: CallConv,
            frame_layout: *const FrameLayout,
        ) SmallInstVec(Self.Inst) {
            return Self.genPrologueFrameSetup(call_conv, frame_layout);
        }

        /// Generate clobber save.
        pub fn genClobberSave(
            call_conv: CallConv,
            frame_layout: *const FrameLayout,
        ) LargeInstVec(Self.Inst) {
            return Self.genClobberSave(call_conv, frame_layout);
        }

        /// Generate clobber restore.
        pub fn genClobberRestore(
            call_conv: CallConv,
            frame_layout: *const FrameLayout,
        ) LargeInstVec(Self.Inst) {
            return Self.genClobberRestore(call_conv, frame_layout);
        }

        /// Generate epilogue frame restore.
        pub fn genEpilogueFrameRestore(
            call_conv: CallConv,
            frame_layout: *const FrameLayout,
        ) SmallInstVec(Self.Inst) {
            return Self.genEpilogueFrameRestore(call_conv, frame_layout);
        }

        /// Generate return instruction.
        pub fn genReturn(
            call_conv: CallConv,
            frame_layout: *const FrameLayout,
        ) SmallInstVec(Self.Inst) {
            return Self.genReturn(call_conv, frame_layout);
        }
    };
}
```

---

## Phase 4: AArch64 ABI Implementation

**File:** `compiler/codegen/native/isa/aarch64/abi.zig`
**Reference:** `cranelift/codegen/src/isa/aarch64/abi.rs:560-1000`

### 4.1 Add machine constants

```zig
/// AArch64 word size in bytes.
pub const word_bytes: u32 = 8;

/// AArch64 stack alignment (16 bytes).
pub const stack_align: u32 = 16;
```

### 4.2 Implement computeFrameLayout

```zig
/// Compute frame layout for AArch64.
/// Port of cranelift aarch64/abi.rs compute_frame_layout
pub fn computeFrameLayout(
    call_conv: CallConv,
    clobbered: []const Writable(RealReg),
    function_calls: FunctionCalls,
    incoming_args_size: u32,
    tail_args_size: u32,
    stackslots_size: u32,
    fixed_frame_storage_size: u32,
    outgoing_args_size: u32,
) FrameLayout {
    // Setup area: FP + LR = 16 bytes
    const setup_area_size: u32 = if (function_calls != .none) 16 else 0;

    // Clobber size: 8 bytes per saved register, 16-byte aligned
    var clobber_size: u32 = @intCast(clobbered.len * 8);
    clobber_size = (clobber_size + 15) & ~@as(u32, 15);

    return FrameLayout{
        .word_bytes = word_bytes,
        .incoming_args_size = incoming_args_size,
        .tail_args_size = tail_args_size,
        .setup_area_size = setup_area_size,
        .clobber_size = clobber_size,
        .fixed_frame_storage_size = fixed_frame_storage_size,
        .stackslots_size = stackslots_size,
        .outgoing_args_size = outgoing_args_size,
        .clobbered_callee_saves = clobbered,
        .function_calls = function_calls,
    };
}
```

### 4.3 Implement genPrologueFrameSetup

```zig
/// Generate prologue frame setup for AArch64.
/// Port of cranelift aarch64/abi.rs gen_prologue_frame_setup
pub fn genPrologueFrameSetup(
    call_conv: CallConv,
    frame_layout: *const FrameLayout,
) SmallInstVec(Inst) {
    _ = call_conv;
    var insts = SmallInstVec(Inst){};

    if (frame_layout.setup_area_size > 0) {
        // stp fp (x29), lr (x30), [sp, #-16]!
        insts.appendAssumeCapacity(Inst{
            .store_pair = .{
                .op = .stp64,
                .rt = fpReg(),
                .rt2 = linkReg(),
                .mem = PairAMode{
                    .sp_pre_indexed = .{
                        .simm7 = SImm7Scaled.maybeFromI64(-16, .i64) orelse unreachable,
                    },
                },
                .flags = MemFlags.trusted(),
            },
        });

        // mov fp, sp (via add fp, sp, #0)
        insts.appendAssumeCapacity(Inst{
            .alu_rr_imm12 = .{
                .alu_op = .add,
                .size = .size64,
                .rd = writableFpReg(),
                .rn = stackReg(),
                .imm12 = Imm12{ .bits = 0, .shift12 = false },
            },
        });
    }

    return insts;
}
```

### 4.4 Implement genClobberSave

```zig
/// Generate callee-save register saves for AArch64.
/// Port of cranelift aarch64/abi.rs gen_clobber_save
pub fn genClobberSave(
    call_conv: CallConv,
    frame_layout: *const FrameLayout,
) LargeInstVec(Inst) {
    _ = call_conv;
    var insts = LargeInstVec(Inst){};

    // Total stack adjustment = clobber_size + fixed_frame_storage_size + outgoing_args_size
    const total_adj = frame_layout.clobber_size +
        frame_layout.fixed_frame_storage_size +
        frame_layout.outgoing_args_size;

    if (total_adj > 0) {
        // sub sp, sp, #total_adj
        if (Imm12.maybeFromU64(total_adj)) |imm12| {
            insts.appendAssumeCapacity(Inst{
                .alu_rr_imm12 = .{
                    .alu_op = .sub,
                    .size = .size64,
                    .rd = writableStackReg(),
                    .rn = stackReg(),
                    .imm12 = imm12,
                },
            });
        } else {
            // Large adjustment needs scratch register
            // TODO: Handle large stack frames
        }
    }

    // Save clobbered callee-saves
    // Store pairs where possible
    const clobbers = frame_layout.clobbered_callee_saves;
    var offset: i32 = @intCast(frame_layout.outgoing_args_size + frame_layout.fixed_frame_storage_size);
    var i: usize = 0;

    while (i < clobbers.len) {
        if (i + 1 < clobbers.len) {
            // Store pair
            insts.append(Inst{
                .store_pair = .{
                    .op = .stp64,
                    .rt = clobbers[i].toReg(),
                    .rt2 = clobbers[i + 1].toReg(),
                    .mem = PairAMode{
                        .signed_offset = .{
                            .reg = stackReg(),
                            .simm7 = SImm7Scaled.maybeFromI64(offset, .i64) orelse unreachable,
                        },
                    },
                    .flags = MemFlags.trusted(),
                },
            }) catch break;
            offset += 16;
            i += 2;
        } else {
            // Store single
            insts.append(Inst{
                .store = .{
                    .op = .str64,
                    .rt = clobbers[i].toReg(),
                    .mem = AMode{
                        .unsigned_offset = .{
                            .rn = stackReg(),
                            .uimm12 = @intCast(offset),
                        },
                    },
                    .flags = MemFlags.trusted(),
                },
            }) catch break;
            offset += 8;
            i += 1;
        }
    }

    return insts;
}
```

### 4.5 Implement genClobberRestore

```zig
/// Generate callee-save register restores for AArch64.
/// Port of cranelift aarch64/abi.rs gen_clobber_restore
pub fn genClobberRestore(
    call_conv: CallConv,
    frame_layout: *const FrameLayout,
) LargeInstVec(Inst) {
    _ = call_conv;
    var insts = LargeInstVec(Inst){};

    // Restore clobbered callee-saves (in reverse order)
    const clobbers = frame_layout.clobbered_callee_saves;
    var offset: i32 = @intCast(frame_layout.outgoing_args_size + frame_layout.fixed_frame_storage_size);

    // Calculate final offset
    offset += @intCast(clobbers.len * 8);

    var i: usize = clobbers.len;
    while (i > 0) {
        if (i >= 2) {
            offset -= 16;
            i -= 2;
            // Load pair
            insts.append(Inst{
                .load_pair = .{
                    .op = .ldp64,
                    .rt = clobbers[i],
                    .rt2 = clobbers[i + 1],
                    .mem = PairAMode{
                        .signed_offset = .{
                            .reg = stackReg(),
                            .simm7 = SImm7Scaled.maybeFromI64(offset, .i64) orelse unreachable,
                        },
                    },
                    .flags = MemFlags.trusted(),
                },
            }) catch break;
        } else {
            offset -= 8;
            i -= 1;
            // Load single
            insts.append(Inst{
                .load = .{
                    .op = .ldr64,
                    .rt = clobbers[i],
                    .mem = AMode{
                        .unsigned_offset = .{
                            .rn = stackReg(),
                            .uimm12 = @intCast(offset),
                        },
                    },
                    .flags = MemFlags.trusted(),
                },
            }) catch break;
        }
    }

    // Restore SP
    const total_adj = frame_layout.clobber_size +
        frame_layout.fixed_frame_storage_size +
        frame_layout.outgoing_args_size;

    if (total_adj > 0) {
        if (Imm12.maybeFromU64(total_adj)) |imm12| {
            insts.append(Inst{
                .alu_rr_imm12 = .{
                    .alu_op = .add,
                    .size = .size64,
                    .rd = writableStackReg(),
                    .rn = stackReg(),
                    .imm12 = imm12,
                },
            }) catch {};
        }
    }

    return insts;
}
```

### 4.6 Implement genEpilogueFrameRestore

```zig
/// Generate epilogue frame restore for AArch64.
/// Port of cranelift aarch64/abi.rs gen_epilogue_frame_restore
pub fn genEpilogueFrameRestore(
    call_conv: CallConv,
    frame_layout: *const FrameLayout,
) SmallInstVec(Inst) {
    _ = call_conv;
    var insts = SmallInstVec(Inst){};

    if (frame_layout.setup_area_size > 0) {
        // ldp fp, lr, [sp], #16
        insts.appendAssumeCapacity(Inst{
            .load_pair = .{
                .op = .ldp64,
                .rt = writableFpReg(),
                .rt2 = writableLinkReg(),
                .mem = PairAMode{
                    .sp_post_indexed = .{
                        .simm7 = SImm7Scaled.maybeFromI64(16, .i64) orelse unreachable,
                    },
                },
                .flags = MemFlags.trusted(),
            },
        });
    }

    return insts;
}
```

### 4.7 Implement genReturn

```zig
/// Generate return instruction for AArch64.
/// Port of cranelift aarch64/abi.rs gen_return
pub fn genReturn(
    call_conv: CallConv,
    frame_layout: *const FrameLayout,
) SmallInstVec(Inst) {
    _ = call_conv;
    _ = frame_layout;
    var insts = SmallInstVec(Inst){};

    // ret (return via link register)
    insts.appendAssumeCapacity(Inst{ .ret = {} });

    return insts;
}
```

---

## Phase 5: x64 ABI Implementation

**File:** `compiler/codegen/native/isa/x64/abi.zig`
**Reference:** `cranelift/codegen/src/isa/x64/abi.rs`

Similar structure to AArch64 with x64-specific instructions:
- `push rbp` / `mov rbp, rsp` for frame setup
- `sub rsp, N` for stack allocation
- `push` / `pop` for callee-saves
- `leave` or `mov rsp, rbp` / `pop rbp` for frame restore
- `ret` for return

---

## Phase 6: Wire Into Lowering Pipeline

**File:** `compiler/codegen/native/machinst/lower.zig`

### 6.1 Add Callee to Lower context

```zig
/// Add callee to Lower struct
callee: ?*Callee(B),
```

### 6.2 Initialize Callee during lowering setup

```zig
/// In Lower.init()
self.callee = try Callee(B).init(allocator, f, call_conv);
```

### 6.3 Call computeFrameLayout after regalloc

```zig
/// After register allocation
self.callee.computeFrameLayout(
    spillslots,
    clobbered_regs,
    function_calls,
);
```

### 6.4 Emit prologue at function start

```zig
/// At start of first block
const frame_layout = self.callee.frameLayout();
const prologue_setup = B.genPrologueFrameSetup(call_conv, frame_layout);
for (prologue_setup.slice()) |inst| {
    try self.emit(inst);
}
const clobber_save = B.genClobberSave(call_conv, frame_layout);
for (clobber_save.slice()) |inst| {
    try self.emit(inst);
}
```

### 6.5 Emit epilogue before returns

```zig
/// Before return instructions
const frame_layout = self.callee.frameLayout();
const clobber_restore = B.genClobberRestore(call_conv, frame_layout);
for (clobber_restore.slice()) |inst| {
    try self.emit(inst);
}
const epilogue_restore = B.genEpilogueFrameRestore(call_conv, frame_layout);
for (epilogue_restore.slice()) |inst| {
    try self.emit(inst);
}
```

---

## Phase 7: Fix Stack Slot Offsets

**File:** `compiler/codegen/native/isa/aarch64/lower.zig`, `x64/lower.zig`

### 7.1 Update lowerStackLoad to use proper offsets

```zig
fn lowerStackLoad(self: *const Self, ctx: *LowerCtx, ir_inst: ClifInst) ?InstOutput {
    const ty = ctx.outputTy(ir_inst, 0);
    const dst = ctx.allocTmp(ty) catch return null;
    const dst_reg = dst.onlyReg() orelse return null;

    // Get stack slot from instruction data
    const inst_data = ctx.data(ir_inst);
    const slot = inst_data.getStackSlot() orelse return null;
    const extra_offset = inst_data.getStackOffset() orelse 0;

    // Get the slot's byte offset from frame layout
    const slot_base_offset = ctx.callee.sizedStackslotOffset(slot);
    const sp_offset = ctx.callee.frameLayout().spToSizedStackSlots() + slot_base_offset + extra_offset;

    // Use SyntheticAmode (x64) or sp_offset AMode (aarch64)
    const mem = AMode{ .sp_offset = .{ .offset = @intCast(sp_offset) } };
    const flags = MemFlags.empty;

    ctx.emit(Inst.genLoad(dst_reg, mem, typeFromClif(ty), flags)) catch return null;

    var output = InstOutput{};
    output.append(ValueRegs(Reg).one(dst_reg.toReg())) catch return null;
    return output;
}
```

---

## Task Breakdown

| Task | Description | File(s) | Est. Lines |
|------|-------------|---------|------------|
| 5.1 | Add FrameLayout struct | machinst/abi.zig | 80 |
| 5.2 | Add FunctionCalls enum | machinst/abi.zig | 10 |
| 5.3 | Add Callee struct | machinst/abi.zig | 120 |
| 5.4 | Add ABIMachineSpec interface | machinst/abi.zig | 60 |
| 5.5 | Implement aarch64 computeFrameLayout | aarch64/abi.zig | 40 |
| 5.6 | Implement aarch64 genPrologueFrameSetup | aarch64/abi.zig | 40 |
| 5.7 | Implement aarch64 genClobberSave | aarch64/abi.zig | 60 |
| 5.8 | Implement aarch64 genClobberRestore | aarch64/abi.zig | 60 |
| 5.9 | Implement aarch64 genEpilogueFrameRestore | aarch64/abi.zig | 20 |
| 5.10 | Implement aarch64 genReturn | aarch64/abi.zig | 15 |
| 5.11 | Implement x64 equivalents | x64/abi.zig | 250 |
| 5.12 | Wire Callee into Lower | machinst/lower.zig | 50 |
| 5.13 | Update lowerStackLoad/Store | aarch64,x64/lower.zig | 40 |
| 5.14 | Add tests | abi.zig, lower.zig | 100 |

**Total:** ~950 lines

---

## Verification Checklist

- [ ] FrameLayout struct matches Cranelift's fields
- [ ] Callee computes stackslot offsets correctly
- [ ] computeFrameLayout produces correct sizes
- [ ] Prologue pushes FP/LR and sets up frame
- [ ] Clobber save stores all callee-saved regs
- [ ] Clobber restore loads all callee-saved regs
- [ ] Epilogue restores FP/LR
- [ ] Stack slot loads/stores use correct offsets
- [ ] `zig build test` passes
- [ ] Simple function compiles and runs correctly

---

## Dependencies

This task unblocks:
- Task #104: Fix stack slot offset handling (uses Callee.sizedStackslotOffset)
- Task #103: Call lowering (uses frame layout for outgoing args)
- Task #101: br_table (indirectly via frame infrastructure)
