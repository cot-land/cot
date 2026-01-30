//! SSA Operation definitions - what computation each Value performs.

const std = @import("std");

/// Register mask - each bit represents a register.
pub const RegMask = u64;

/// SSA operation type.
pub const Op = enum(u16) {
    // === Invalid/Placeholder ===
    invalid,

    // === Memory State ===
    init_mem,

    // === Constants ===
    const_bool, const_int, const_float, const_nil, const_string, const_ptr,
    const_8, const_16, const_32, const_64,

    // === Integer Arithmetic (Generic) ===
    add, sub, mul, div, udiv, mod, umod, neg,

    // === Integer Arithmetic (Sized) ===
    add8, sub8, mul8, add16, sub16, mul16, add32, sub32, mul32, add64, sub64, mul64,
    hmul32, hmul32u, hmul64, hmul64u,
    divmod32, divmod64, divmodu32, divmodu64,

    // === Bitwise (Generic) ===
    and_, or_, xor, shl, shr, sar, not,

    // === Bitwise (Sized) ===
    and8, and16, and32, and64, or8, or16, or32, or64, xor8, xor16, xor32, xor64,
    shl8, shl16, shl32, shl64, shr8, shr16, shr32, shr64, sar8, sar16, sar32, sar64,
    com8, com16, com32, com64,
    ctz32, ctz64, clz32, clz64, popcnt32, popcnt64,

    // === Comparisons ===
    eq, ne, lt, le, gt, ge, ult, ule, ugt, uge,
    eq8, eq16, eq32, eq64, ne8, ne16, ne32, ne64,
    lt32, lt64, le32, le64, gt32, gt64, ge32, ge64,

    // === Type Conversions ===
    sign_ext8to16, sign_ext8to32, sign_ext8to64, sign_ext16to32, sign_ext16to64, sign_ext32to64,
    zero_ext8to16, zero_ext8to32, zero_ext8to64, zero_ext16to32, zero_ext16to64, zero_ext32to64,
    trunc16to8, trunc32to8, trunc32to16, trunc64to8, trunc64to16, trunc64to32,
    convert,
    cvt32to32f, cvt32to64f, cvt64to32f, cvt64to64f,
    cvt32fto32, cvt32fto64, cvt64fto32, cvt64fto64,
    cvt32fto64f, cvt64fto32f,

    // === Float Operations ===
    add32f, sub32f, mul32f, div32f, neg32f, sqrt32f,
    add64f, sub64f, mul64f, div64f, neg64f, sqrt64f,

    // === Memory Operations ===
    load, store,
    load8, load16, load32, load64, store8, store16, store32, store64,
    load8s, load16s, load32s,
    addr, local_addr, global_addr, off_ptr, add_ptr, sub_ptr,
    store_wb, move, zero,
    var_def, var_live, var_kill,

    // === Control Flow ===
    phi, copy, fwd_ref, arg,
    select0, select1, make_tuple, select_n, cond_select,
    string_len, string_ptr, string_make, slice_len, slice_ptr, slice_make, string_concat,

    // === Function Calls ===
    call, tail_call, static_call, closure_call, inter_call,

    // === Safety Checks ===
    nil_check, is_non_nil, is_nil, bounds_check, slice_bounds,

    // === Atomics ===
    atomic_load32, atomic_load64, atomic_store32, atomic_store64,
    atomic_add32, atomic_add64, atomic_cas32, atomic_cas64, atomic_exchange32, atomic_exchange64,

    // === Register Allocation ===
    store_reg, load_reg,

    // === ARM64-Specific ===
    arm64_add, arm64_adds, arm64_sub, arm64_subs, arm64_mul, arm64_sdiv, arm64_udiv,
    arm64_madd, arm64_msub, arm64_smulh, arm64_umulh,
    arm64_and, arm64_orr, arm64_eor, arm64_bic, arm64_orn, arm64_eon, arm64_mvn,
    arm64_lsl, arm64_lsr, arm64_asr, arm64_ror, arm64_lslimm, arm64_lsrimm, arm64_asrimm,
    arm64_cmp, arm64_cmn, arm64_tst,
    arm64_movd, arm64_movw, arm64_movz, arm64_movn, arm64_movk,
    arm64_ldr, arm64_ldrw, arm64_ldrh, arm64_ldrb, arm64_ldrsw, arm64_ldrsh, arm64_ldrsb, arm64_ldp,
    arm64_str, arm64_strw, arm64_strh, arm64_strb, arm64_stp,
    arm64_adrp, arm64_add_imm, arm64_sub_imm,
    arm64_bl, arm64_blr, arm64_br, arm64_ret, arm64_b, arm64_bcond,
    arm64_csel, arm64_csinc, arm64_csinv, arm64_csneg, arm64_cset,
    arm64_clz, arm64_rbit, arm64_rev,
    arm64_sxtb, arm64_sxth, arm64_sxtw, arm64_uxtb, arm64_uxth,
    arm64_fadd, arm64_fsub, arm64_fmul, arm64_fdiv, arm64_fneg, arm64_fsqrt,
    arm64_fmov, arm64_fcvtzs, arm64_scvtf, arm64_fcmp,

    // === AMD64-Specific ===
    amd64_addq, amd64_addl, amd64_subq, amd64_subl, amd64_imulq, amd64_imull,
    amd64_idivq, amd64_idivl, amd64_divq, amd64_divl,
    amd64_andq, amd64_andl, amd64_orq, amd64_orl, amd64_xorq, amd64_xorl,
    amd64_shlq, amd64_shll, amd64_shrq, amd64_shrl, amd64_sarq, amd64_sarl,
    amd64_notq, amd64_notl, amd64_negq, amd64_negl,
    amd64_cmpq, amd64_cmpl, amd64_testq, amd64_testl,
    amd64_movq, amd64_movl, amd64_movb, amd64_movw,
    amd64_movabs, amd64_movzx, amd64_movsx,
    amd64_leaq, amd64_leal,
    amd64_loadq, amd64_loadl, amd64_loadw, amd64_loadb,
    amd64_storeq, amd64_storel, amd64_storew, amd64_storeb,
    amd64_call, amd64_ret, amd64_jmp, amd64_jcc,
    amd64_setcc, amd64_cmov,
    amd64_pushq, amd64_popq,
    amd64_addsd, amd64_subsd, amd64_mulsd, amd64_divsd,
    amd64_movsd, amd64_cvtsi2sd, amd64_cvttsd2si,

    pub fn info(self: Op) OpInfo { return op_info_table[@intFromEnum(self)]; }
    pub fn isCall(self: Op) bool { return self.info().call; }
    pub fn name(self: Op) []const u8 { return self.info().name; }
    pub fn isGeneric(self: Op) bool { return self.info().generic; }
    pub fn isCommutative(self: Op) bool { return self.info().commutative; }
    pub fn hasSideEffects(self: Op) bool { return self.info().has_side_effects; }
    pub fn isRematerializable(self: Op) bool { return self.info().rematerializable; }
    pub fn readsMemory(self: Op) bool { return self.info().reads_memory; }
    pub fn writesMemory(self: Op) bool { return self.info().writes_memory; }
};

pub const OpInfo = struct {
    name: []const u8 = "",
    reg: RegInfo = .{},
    aux_type: AuxType = .none,
    arg_len: i8 = 0,
    generic: bool = true,
    rematerializable: bool = false,
    commutative: bool = false,
    result_in_arg0: bool = false,
    clobber_flags: bool = false,
    call: bool = false,
    has_side_effects: bool = false,
    reads_memory: bool = false,
    writes_memory: bool = false,
    nil_check: bool = false,
    fault_on_nil_arg0: bool = false,
    uses_flags: bool = false,
};

pub const RegInfo = struct {
    inputs: []const InputInfo = &.{},
    outputs: []const OutputInfo = &.{},
    clobbers: RegMask = 0,
};

pub const InputInfo = struct {
    idx: u8,
    regs: RegMask = 0,
};

pub const OutputInfo = struct {
    idx: u8,
    regs: RegMask = 0,
};

pub const AuxType = enum {
    none, bool_, int8, int16, int32, int64, float32, float64,
    string, symbol, symbol_off, symbol_val_off, call, type_ref, cond, arch,
};

// Register masks
const GP_REGS: RegMask = 0x7FFFFFFF;
const CALLER_SAVED: RegMask = 0x0007FFFF;

const op_info_table = blk: {
    var table: [@typeInfo(Op).@"enum".fields.len]OpInfo = undefined;
    for (&table) |*e| e.* = .{};

    // Invalid
    table[@intFromEnum(Op.invalid)] = .{ .name = "Invalid" };

    // Memory
    table[@intFromEnum(Op.init_mem)] = .{ .name = "InitMem", .rematerializable = true };

    // Constants (all rematerializable)
    table[@intFromEnum(Op.const_bool)] = .{ .name = "ConstBool", .aux_type = .int64, .rematerializable = true };
    table[@intFromEnum(Op.const_int)] = .{ .name = "ConstInt", .aux_type = .int64, .rematerializable = true };
    table[@intFromEnum(Op.const_float)] = .{ .name = "ConstFloat", .aux_type = .float64, .rematerializable = true };
    table[@intFromEnum(Op.const_nil)] = .{ .name = "ConstNil", .rematerializable = true };
    table[@intFromEnum(Op.const_string)] = .{ .name = "ConstString", .aux_type = .string, .rematerializable = true };
    table[@intFromEnum(Op.const_ptr)] = .{ .name = "ConstPtr", .aux_type = .int64, .rematerializable = true };
    for ([_]Op{ .const_8, .const_16, .const_32, .const_64 }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .aux_type = .int64, .rematerializable = true };
    }

    // Arithmetic (2 args, generic)
    for ([_]Op{ .add, .mul }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2, .commutative = true };
    }
    for ([_]Op{ .sub, .div, .udiv, .mod, .umod }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2 };
    }
    table[@intFromEnum(Op.neg)] = .{ .name = "Neg", .arg_len = 1 };

    // Sized arithmetic
    for ([_]Op{ .add8, .add16, .add32, .add64, .mul8, .mul16, .mul32, .mul64 }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2, .commutative = true };
    }
    for ([_]Op{ .sub8, .sub16, .sub32, .sub64 }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2 };
    }

    // Bitwise
    for ([_]Op{ .and_, .or_, .xor }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2, .commutative = true };
    }
    for ([_]Op{ .shl, .shr, .sar }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2 };
    }
    table[@intFromEnum(Op.not)] = .{ .name = "Not", .arg_len = 1 };

    // Comparisons (all produce bool, 2 args)
    for ([_]Op{ .eq, .ne }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2, .commutative = true };
    }
    for ([_]Op{ .lt, .le, .gt, .ge, .ult, .ule, .ugt, .uge }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2 };
    }

    // Conversions
    table[@intFromEnum(Op.convert)] = .{ .name = "Convert", .arg_len = 1, .aux_type = .type_ref };

    // Memory ops
    table[@intFromEnum(Op.load)] = .{ .name = "Load", .arg_len = 2, .reads_memory = true };
    table[@intFromEnum(Op.store)] = .{ .name = "Store", .arg_len = 3, .writes_memory = true, .has_side_effects = true };
    for ([_]Op{ .load8, .load16, .load32, .load64 }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 2, .reads_memory = true };
    }
    for ([_]Op{ .store8, .store16, .store32, .store64 }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = 3, .writes_memory = true, .has_side_effects = true };
    }

    // Address computation
    table[@intFromEnum(Op.addr)] = .{ .name = "Addr", .aux_type = .symbol };
    table[@intFromEnum(Op.local_addr)] = .{ .name = "LocalAddr", .aux_type = .int64 };
    table[@intFromEnum(Op.global_addr)] = .{ .name = "GlobalAddr", .aux_type = .symbol };
    table[@intFromEnum(Op.off_ptr)] = .{ .name = "OffPtr", .arg_len = 1, .aux_type = .int64 };
    table[@intFromEnum(Op.add_ptr)] = .{ .name = "AddPtr", .arg_len = 2 };
    table[@intFromEnum(Op.sub_ptr)] = .{ .name = "SubPtr", .arg_len = 2 };

    // Control flow
    table[@intFromEnum(Op.phi)] = .{ .name = "Phi", .arg_len = -1 };
    table[@intFromEnum(Op.copy)] = .{ .name = "Copy", .arg_len = 1 };
    table[@intFromEnum(Op.fwd_ref)] = .{ .name = "FwdRef", .aux_type = .int64 };
    table[@intFromEnum(Op.arg)] = .{ .name = "Arg", .aux_type = .int64, .rematerializable = true };
    table[@intFromEnum(Op.cond_select)] = .{ .name = "CondSelect", .arg_len = 3 };

    // Tuple ops
    table[@intFromEnum(Op.select0)] = .{ .name = "Select0", .arg_len = 1 };
    table[@intFromEnum(Op.select1)] = .{ .name = "Select1", .arg_len = 1 };
    table[@intFromEnum(Op.select_n)] = .{ .name = "SelectN", .arg_len = 1, .aux_type = .int64 };
    table[@intFromEnum(Op.make_tuple)] = .{ .name = "MakeTuple", .arg_len = -1 };

    // String/slice
    table[@intFromEnum(Op.string_len)] = .{ .name = "StringLen", .arg_len = 1 };
    table[@intFromEnum(Op.string_ptr)] = .{ .name = "StringPtr", .arg_len = 1 };
    table[@intFromEnum(Op.string_make)] = .{ .name = "StringMake", .arg_len = 2 };
    table[@intFromEnum(Op.slice_len)] = .{ .name = "SliceLen", .arg_len = 1 };
    table[@intFromEnum(Op.slice_ptr)] = .{ .name = "SlicePtr", .arg_len = 1 };
    table[@intFromEnum(Op.slice_make)] = .{ .name = "SliceMake", .arg_len = 2 };
    table[@intFromEnum(Op.string_concat)] = .{ .name = "StringConcat", .arg_len = 2, .has_side_effects = true, .call = true };

    // Calls
    for ([_]Op{ .call, .tail_call, .static_call, .closure_call, .inter_call }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .arg_len = -1, .call = true, .has_side_effects = true, .aux_type = .call };
    }

    // Safety checks
    table[@intFromEnum(Op.nil_check)] = .{ .name = "NilCheck", .arg_len = 2, .nil_check = true, .has_side_effects = true };
    table[@intFromEnum(Op.is_non_nil)] = .{ .name = "IsNonNil", .arg_len = 1 };
    table[@intFromEnum(Op.is_nil)] = .{ .name = "IsNil", .arg_len = 1 };
    table[@intFromEnum(Op.bounds_check)] = .{ .name = "BoundsCheck", .arg_len = 3, .has_side_effects = true };

    // Register allocation
    table[@intFromEnum(Op.store_reg)] = .{ .name = "StoreReg", .arg_len = 1 };
    table[@intFromEnum(Op.load_reg)] = .{ .name = "LoadReg", .arg_len = 0 };

    // Move
    table[@intFromEnum(Op.move)] = .{ .name = "Move", .arg_len = 3, .aux_type = .int64, .writes_memory = true, .has_side_effects = true };

    // ARM64 ops (machine-specific, not generic)
    for ([_]Op{ .arm64_add, .arm64_adds, .arm64_sub, .arm64_subs, .arm64_mul, .arm64_sdiv, .arm64_udiv, .arm64_madd, .arm64_msub }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2 };
    }
    for ([_]Op{ .arm64_and, .arm64_orr, .arm64_eor, .arm64_bic, .arm64_lsl, .arm64_lsr, .arm64_asr }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2 };
    }
    table[@intFromEnum(Op.arm64_cmp)] = .{ .name = "ARM64Cmp", .generic = false, .arg_len = 2, .clobber_flags = true };
    table[@intFromEnum(Op.arm64_movd)] = .{ .name = "ARM64MovD", .generic = false, .arg_len = 1 };
    table[@intFromEnum(Op.arm64_movz)] = .{ .name = "ARM64MovZ", .generic = false, .aux_type = .int64 };
    for ([_]Op{ .arm64_ldr, .arm64_ldrw, .arm64_ldrh, .arm64_ldrb }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 1, .aux_type = .int64, .reads_memory = true };
    }
    for ([_]Op{ .arm64_str, .arm64_strw, .arm64_strh, .arm64_strb }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2, .aux_type = .int64, .writes_memory = true, .has_side_effects = true };
    }
    table[@intFromEnum(Op.arm64_bl)] = .{ .name = "ARM64BL", .generic = false, .call = true, .has_side_effects = true };
    table[@intFromEnum(Op.arm64_blr)] = .{ .name = "ARM64BLR", .generic = false, .arg_len = 1, .call = true, .has_side_effects = true };
    table[@intFromEnum(Op.arm64_ret)] = .{ .name = "ARM64Ret", .generic = false, .has_side_effects = true };
    table[@intFromEnum(Op.arm64_csel)] = .{ .name = "ARM64CSel", .generic = false, .arg_len = 2, .uses_flags = true };
    table[@intFromEnum(Op.arm64_add_imm)] = .{ .name = "ARM64AddImm", .generic = false, .arg_len = 1, .aux_type = .int64 };
    table[@intFromEnum(Op.arm64_adrp)] = .{ .name = "ARM64ADRP", .generic = false, .aux_type = .symbol };

    // AMD64 ops (machine-specific)
    for ([_]Op{ .amd64_addq, .amd64_addl, .amd64_subq, .amd64_subl, .amd64_imulq, .amd64_imull }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2 };
    }
    for ([_]Op{ .amd64_andq, .amd64_andl, .amd64_orq, .amd64_orl, .amd64_xorq, .amd64_xorl }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2 };
    }
    table[@intFromEnum(Op.amd64_cmpq)] = .{ .name = "AMD64CmpQ", .generic = false, .arg_len = 2, .clobber_flags = true };
    table[@intFromEnum(Op.amd64_movq)] = .{ .name = "AMD64MovQ", .generic = false, .arg_len = 1 };
    table[@intFromEnum(Op.amd64_movabs)] = .{ .name = "AMD64MovAbs", .generic = false, .aux_type = .int64 };
    for ([_]Op{ .amd64_loadq, .amd64_loadl, .amd64_loadw, .amd64_loadb }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 1, .aux_type = .int64, .reads_memory = true };
    }
    for ([_]Op{ .amd64_storeq, .amd64_storel, .amd64_storew, .amd64_storeb }) |op| {
        table[@intFromEnum(op)] = .{ .name = @tagName(op), .generic = false, .arg_len = 2, .aux_type = .int64, .writes_memory = true, .has_side_effects = true };
    }
    table[@intFromEnum(Op.amd64_call)] = .{ .name = "AMD64Call", .generic = false, .call = true, .has_side_effects = true };
    table[@intFromEnum(Op.amd64_ret)] = .{ .name = "AMD64Ret", .generic = false, .has_side_effects = true };
    table[@intFromEnum(Op.amd64_leaq)] = .{ .name = "AMD64LeaQ", .generic = false, .arg_len = 1, .aux_type = .int64 };

    break :blk table;
};

// ============================================================================
// Tests
// ============================================================================

test "Op info lookup" {
    const add_info = Op.add.info();
    try std.testing.expectEqualStrings("add", add_info.name);
    try std.testing.expect(add_info.commutative);
    try std.testing.expectEqual(@as(i8, 2), add_info.arg_len);
}

test "constant ops are rematerializable" {
    try std.testing.expect(Op.const_int.isRematerializable());
    try std.testing.expect(Op.const_bool.isRematerializable());
    try std.testing.expect(Op.const_float.isRematerializable());
}

test "call ops have call flag" {
    try std.testing.expect(Op.call.isCall());
    try std.testing.expect(Op.static_call.isCall());
    try std.testing.expect(!Op.add.isCall());
}

test "memory ops" {
    try std.testing.expect(Op.load.readsMemory());
    try std.testing.expect(Op.store.writesMemory());
    try std.testing.expect(Op.store.hasSideEffects());
}

test "generic vs machine ops" {
    try std.testing.expect(Op.add.isGeneric());
    try std.testing.expect(!Op.arm64_add.isGeneric());
    try std.testing.expect(!Op.amd64_addq.isGeneric());
}
