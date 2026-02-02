//! Register definitions for machine code generation.
//!
//! Port of cranelift/codegen/src/machinst/reg.rs
//!
//! Provides register types and traits for representing both virtual and
//! physical registers during code generation and register allocation.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// The first 192 vregs (64 int, 64 float, 64 vec) are "pinned" to
/// physical registers. These must not be passed into the regalloc,
/// but they are used to represent physical registers in the same
/// Reg type post-regalloc.
pub const PINNED_VREGS: usize = 192;

/// Registers per class for pinned vregs
pub const REGS_PER_CLASS: usize = 64;

/// Spillslot bit in Reg encoding
const REG_SPILLSLOT_BIT: u32 = 0x8000_0000;
const REG_SPILLSLOT_MASK: u32 = ~REG_SPILLSLOT_BIT;

// ============================================================================
// RegClass
// ============================================================================

/// A register class. Each register in the ISA has one class, and the
/// classes are disjoint.
pub const RegClass = enum(u8) {
    /// Integer/general-purpose registers
    int = 0,
    /// Floating-point registers
    float = 1,
    /// Vector registers
    vector = 2,

    pub fn asU8(self: RegClass) u8 {
        return @intFromEnum(self);
    }

    pub fn fromU8(v: u8) RegClass {
        return @enumFromInt(v);
    }
};

// ============================================================================
// PReg (Physical Register)
// ============================================================================

/// A physical register - one of the actual hardware registers.
pub const PReg = struct {
    /// Encoded as: class (2 bits) | hw_enc (6 bits)
    bits: u8,

    const Self = @This();

    /// Create a new PReg from hardware encoding and class.
    pub fn init(hw_enc: u8, reg_class: RegClass) Self {
        return .{
            .bits = (reg_class.asU8() << 6) | (hw_enc & 0x3F),
        };
    }

    /// Create from a flat index (0-191 for pinned regs).
    pub fn fromIndex(idx: usize) Self {
        const class_idx = idx / REGS_PER_CLASS;
        const hw_enc = idx % REGS_PER_CLASS;
        return init(@intCast(hw_enc), RegClass.fromU8(@intCast(class_idx)));
    }

    /// Get the flat index (0-191).
    pub fn index(self: Self) usize {
        return @as(usize, self.class().asU8()) * REGS_PER_CLASS + @as(usize, self.hwEnc());
    }

    /// Get the hardware encoding (register number within class).
    pub fn hwEnc(self: Self) u8 {
        return self.bits & 0x3F;
    }

    /// Get the register class.
    pub fn class(self: Self) RegClass {
        return RegClass.fromU8(self.bits >> 6);
    }

    /// Format for display.
    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const class_char: u8 = switch (self.class()) {
            .int => 'r',
            .float => 'f',
            .vector => 'v',
        };
        try writer.print("p{c}{d}", .{ class_char, self.hwEnc() });
    }
};

// ============================================================================
// VReg (Virtual Register)
// ============================================================================

/// A virtual register - allocated by the register allocator.
pub const VReg = struct {
    /// Encoded as: class (2 bits) | vreg_index (30 bits)
    bits: u32,

    const Self = @This();

    /// Create a new VReg.
    pub fn init(idx: u32, reg_class: RegClass) Self {
        return .{
            .bits = (@as(u32, reg_class.asU8()) << 30) | (idx & 0x3FFF_FFFF),
        };
    }

    /// Get the vreg index.
    pub fn vreg(self: Self) usize {
        return @intCast(self.bits & 0x3FFF_FFFF);
    }

    /// Get the raw bits as u32 (for comparisons).
    pub fn toU32(self: Self) u32 {
        return self.bits;
    }

    /// Get the register class.
    pub fn class(self: Self) RegClass {
        return RegClass.fromU8(@intCast(self.bits >> 30));
    }

    /// Check if this is an invalid vreg.
    pub fn isInvalid(self: Self) bool {
        return self.bits == 0xFFFF_FFFF;
    }

    /// Create an invalid vreg.
    pub fn invalid() Self {
        return .{ .bits = 0xFFFF_FFFF };
    }

    /// Format for display.
    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.isInvalid()) {
            try writer.writeAll("<invalid>");
        } else {
            const class_char: u8 = switch (self.class()) {
                .int => 'i',
                .float => 'f',
                .vector => 'v',
            };
            try writer.print("v{d}{c}", .{ self.vreg(), class_char });
        }
    }
};

// ============================================================================
// Reg (Unified Register)
// ============================================================================

/// A register named in an instruction. This register can be a virtual
/// register, a fixed physical register, or a named spillslot (after
/// regalloc).
pub const Reg = struct {
    bits: u32,

    const Self = @This();

    /// Create a Reg from a VReg.
    pub fn fromVReg(vreg: VReg) Self {
        return .{ .bits = vreg.bits };
    }

    /// Create an invalid Reg.
    pub fn invalid() Self {
        return .{ .bits = VReg.invalid().bits };
    }

    /// Create a Reg from a PReg (physical register).
    pub fn fromPReg(preg: PReg) Self {
        // Pinned vregs encode physical registers
        const vreg = VReg.init(@intCast(preg.index()), preg.class());
        return .{ .bits = vreg.bits };
    }

    /// Create a Reg from a SpillSlot.
    pub fn fromSpillSlot(slot: SpillSlot) Self {
        return .{ .bits = REG_SPILLSLOT_BIT | @as(u32, @intCast(slot.index)) };
    }

    /// Get the physical register, if this is one.
    pub fn toRealReg(self: Self) ?RealReg {
        if (self.isSpillSlot()) return null;
        const vreg = self.toVRegRaw();
        if (vreg.vreg() < PINNED_VREGS) {
            return RealReg{ .preg = PReg.fromIndex(vreg.vreg()) };
        }
        return null;
    }

    /// Get the virtual register, if this is one.
    pub fn toVirtualReg(self: Self) ?VirtualReg {
        if (self.isSpillSlot()) return null;
        const vreg = self.toVRegRaw();
        if (vreg.vreg() >= PINNED_VREGS) {
            return VirtualReg{ .vreg = vreg };
        }
        return null;
    }

    /// Get the spillslot, if this is one.
    pub fn toSpillSlot(self: Self) ?SpillSlot {
        if ((self.bits & REG_SPILLSLOT_BIT) != 0) {
            return SpillSlot{ .index = @intCast(self.bits & REG_SPILLSLOT_MASK) };
        }
        return null;
    }

    /// Get the raw VReg encoding.
    fn toVRegRaw(self: Self) VReg {
        return .{ .bits = self.bits };
    }

    /// Get the register class.
    pub fn class(self: Self) RegClass {
        std.debug.assert(!self.isSpillSlot());
        return self.toVRegRaw().class();
    }

    /// Is this a physical register?
    pub fn isReal(self: Self) bool {
        return self.toRealReg() != null;
    }

    /// Is this a virtual register?
    pub fn isVirtual(self: Self) bool {
        return self.toVirtualReg() != null;
    }

    /// Is this a spillslot?
    pub fn isSpillSlot(self: Self) bool {
        return (self.bits & REG_SPILLSLOT_BIT) != 0;
    }

    /// Get the hardware encoding. Only valid for physical registers.
    pub fn hwEnc(self: Self) u8 {
        const rreg = self.toRealReg() orelse @panic("hwEnc called on non-physical register");
        return rreg.preg.hwEnc();
    }

    /// Format for display.
    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.toVRegRaw().isInvalid()) {
            try writer.writeAll("<invalid>");
        } else if (self.toSpillSlot()) |slot| {
            try writer.print("slot{d}", .{slot.index});
        } else if (self.toRealReg()) |rreg| {
            try rreg.preg.format("", .{}, writer);
        } else if (self.toVirtualReg()) |vreg| {
            try vreg.vreg.format("", .{}, writer);
        } else {
            unreachable;
        }
    }
};

// ============================================================================
// RealReg (Physical Register wrapper)
// ============================================================================

/// A real (physical) register.
pub const RealReg = struct {
    preg: PReg,

    const Self = @This();

    /// Get the register class.
    pub fn class(self: Self) RegClass {
        return self.preg.class();
    }

    /// Get the hardware encoding.
    pub fn hwEnc(self: Self) u8 {
        return self.preg.hwEnc();
    }

    /// Convert to a Reg.
    pub fn toReg(self: Self) Reg {
        return Reg.fromPReg(self.preg);
    }
};

// ============================================================================
// VirtualReg (Virtual Register wrapper)
// ============================================================================

/// A virtual register.
pub const VirtualReg = struct {
    vreg: VReg,

    const Self = @This();

    /// Get the register class.
    pub fn class(self: Self) RegClass {
        return self.vreg.class();
    }

    /// Get the vreg index.
    pub fn index(self: Self) usize {
        return self.vreg.vreg();
    }

    /// Convert to a Reg.
    pub fn toReg(self: Self) Reg {
        return Reg.fromVReg(self.vreg);
    }

    /// Get the underlying VReg.
    pub fn toVReg(self: Self) VReg {
        return self.vreg;
    }
};

// ============================================================================
// SpillSlot
// ============================================================================

/// A spill slot - stack location for spilled registers.
pub const SpillSlot = struct {
    index: usize,

    const Self = @This();

    /// Create a new spill slot.
    pub fn init(index: usize) Self {
        return .{ .index = index };
    }

    /// Convert to a Reg.
    pub fn toReg(self: Self) Reg {
        return Reg.fromSpillSlot(self);
    }
};

// ============================================================================
// Writable
// ============================================================================

/// A type wrapper that indicates a register type is writable.
pub fn Writable(comptime T: type) type {
    return struct {
        reg: T,

        const Self = @This();

        /// Create a writable register.
        pub fn fromReg(reg: T) Self {
            return .{ .reg = reg };
        }

        /// Get the underlying register (read-only).
        pub fn toReg(self: Self) T {
            return self.reg;
        }

        /// Get a mutable reference to the register.
        pub fn regMut(self: *Self) *T {
            return &self.reg;
        }

        /// Map the register to another type.
        pub fn map(self: Self, comptime U: type, f: fn (T) U) Writable(U) {
            return Writable(U){ .reg = f(self.reg) };
        }

        /// Create an invalid writable register.
        pub fn invalid() Self {
            return .{ .reg = T.invalid() };
        }
    };
}

// ============================================================================
// PRegSet
// ============================================================================

/// A set of physical registers.
pub const PRegSet = struct {
    /// Bitmap: 64 bits per class, 3 classes = 192 bits
    int_regs: u64,
    float_regs: u64,
    vector_regs: u64,

    const Self = @This();

    /// Create an empty set.
    pub fn empty() Self {
        return .{
            .int_regs = 0,
            .float_regs = 0,
            .vector_regs = 0,
        };
    }

    /// Add a register to the set.
    pub fn add(self: *Self, preg: PReg) void {
        const bit: u64 = @as(u64, 1) << @intCast(preg.hwEnc());
        switch (preg.class()) {
            .int => self.int_regs |= bit,
            .float => self.float_regs |= bit,
            .vector => self.vector_regs |= bit,
        }
    }

    /// Check if a register is in the set.
    pub fn contains(self: Self, preg: PReg) bool {
        const bit: u64 = @as(u64, 1) << @intCast(preg.hwEnc());
        return switch (preg.class()) {
            .int => (self.int_regs & bit) != 0,
            .float => (self.float_regs & bit) != 0,
            .vector => (self.vector_regs & bit) != 0,
        };
    }

    /// Union with another set.
    pub fn unionWith(self: *Self, other: Self) void {
        self.int_regs |= other.int_regs;
        self.float_regs |= other.float_regs;
        self.vector_regs |= other.vector_regs;
    }

    /// Remove a register from the set.
    pub fn remove(self: *Self, preg: PReg) void {
        const bit: u64 = @as(u64, 1) << @intCast(preg.hwEnc());
        switch (preg.class()) {
            .int => self.int_regs &= ~bit,
            .float => self.float_regs &= ~bit,
            .vector => self.vector_regs &= ~bit,
        }
    }

    /// Check if the set is empty.
    pub fn isEmpty(self: Self) bool {
        return self.int_regs == 0 and self.float_regs == 0 and self.vector_regs == 0;
    }
};

// ============================================================================
// OperandKind
// ============================================================================

/// The kind of operand - use or def.
pub const OperandKind = enum {
    /// This operand is read (used).
    use,
    /// This operand is written (defined).
    def,
};

// ============================================================================
// OperandPos
// ============================================================================

/// The position of an operand within an instruction.
pub const OperandPos = enum {
    /// Early position - at the start of the instruction.
    early,
    /// Late position - at the end of the instruction.
    late,
};

// ============================================================================
// OperandConstraint
// ============================================================================

/// Constraint on an operand's allocation.
pub const OperandConstraint = union(enum) {
    /// Any register of the appropriate class.
    reg,
    /// Any location (register or stack).
    any,
    /// A specific fixed register.
    fixed_reg: PReg,
    /// Reuse a previous operand's allocation.
    reuse: usize,
};

// ============================================================================
// Operand
// ============================================================================

/// An operand to an instruction for register allocation.
pub const Operand = struct {
    vreg: VReg,
    constraint: OperandConstraint,
    kind: OperandKind,
    pos: OperandPos,

    const Self = @This();

    pub fn init(vreg: VReg, constraint: OperandConstraint, kind: OperandKind, pos: OperandPos) Self {
        return .{
            .vreg = vreg,
            .constraint = constraint,
            .kind = kind,
            .pos = pos,
        };
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert a PReg to its pinned VReg.
pub fn pregToPinnedVReg(preg: PReg) VReg {
    return VReg.init(@intCast(preg.index()), preg.class());
}

/// Convert a VReg to its pinned PReg, if any.
pub fn pinnedVRegToPReg(vreg: VReg) ?PReg {
    if (vreg.vreg() < PINNED_VREGS) {
        return PReg.fromIndex(vreg.vreg());
    }
    return null;
}

/// Get the first available vreg index for user code.
pub fn firstUserVRegIndex() usize {
    return PINNED_VREGS;
}

// ============================================================================
// Tests
// ============================================================================

test "preg creation and encoding" {
    const testing = std.testing;

    const r0 = PReg.init(0, .int);
    try testing.expectEqual(@as(u8, 0), r0.hwEnc());
    try testing.expectEqual(RegClass.int, r0.class());

    const f5 = PReg.init(5, .float);
    try testing.expectEqual(@as(u8, 5), f5.hwEnc());
    try testing.expectEqual(RegClass.float, f5.class());

    const v31 = PReg.init(31, .vector);
    try testing.expectEqual(@as(u8, 31), v31.hwEnc());
    try testing.expectEqual(RegClass.vector, v31.class());
}

test "preg from/to index" {
    const testing = std.testing;

    // int regs: 0-63
    const r0 = PReg.fromIndex(0);
    try testing.expectEqual(RegClass.int, r0.class());
    try testing.expectEqual(@as(u8, 0), r0.hwEnc());

    const r63 = PReg.fromIndex(63);
    try testing.expectEqual(RegClass.int, r63.class());
    try testing.expectEqual(@as(u8, 63), r63.hwEnc());

    // float regs: 64-127
    const f0 = PReg.fromIndex(64);
    try testing.expectEqual(RegClass.float, f0.class());
    try testing.expectEqual(@as(u8, 0), f0.hwEnc());

    // vector regs: 128-191
    const v0 = PReg.fromIndex(128);
    try testing.expectEqual(RegClass.vector, v0.class());
    try testing.expectEqual(@as(u8, 0), v0.hwEnc());
}

test "vreg creation" {
    const testing = std.testing;

    const v0 = VReg.init(192, .int);
    try testing.expectEqual(@as(usize, 192), v0.vreg());
    try testing.expectEqual(RegClass.int, v0.class());
    try testing.expect(!v0.isInvalid());

    const invalid = VReg.invalid();
    try testing.expect(invalid.isInvalid());
}

test "reg from preg is real" {
    const testing = std.testing;

    const preg = PReg.init(5, .int);
    const reg = Reg.fromPReg(preg);

    try testing.expect(reg.isReal());
    try testing.expect(!reg.isVirtual());
    try testing.expect(!reg.isSpillSlot());

    const rreg = reg.toRealReg().?;
    try testing.expectEqual(@as(u8, 5), rreg.hwEnc());
}

test "reg from vreg is virtual" {
    const testing = std.testing;

    const vreg = VReg.init(200, .int);
    const reg = Reg.fromVReg(vreg);

    try testing.expect(!reg.isReal());
    try testing.expect(reg.isVirtual());
    try testing.expect(!reg.isSpillSlot());

    const vr = reg.toVirtualReg().?;
    try testing.expectEqual(@as(usize, 200), vr.index());
}

test "reg from spillslot" {
    const testing = std.testing;

    const slot = SpillSlot.init(42);
    const reg = Reg.fromSpillSlot(slot);

    try testing.expect(!reg.isReal());
    try testing.expect(!reg.isVirtual());
    try testing.expect(reg.isSpillSlot());

    const s = reg.toSpillSlot().?;
    try testing.expectEqual(@as(usize, 42), s.index);
}

test "writable reg" {
    const testing = std.testing;

    const preg = PReg.init(0, .int);
    const reg = Reg.fromPReg(preg);
    var wreg = Writable(Reg).fromReg(reg);

    try testing.expect(wreg.toReg().isReal());

    // Can modify through regMut
    const new_preg = PReg.init(1, .int);
    wreg.regMut().* = Reg.fromPReg(new_preg);
    try testing.expectEqual(@as(u8, 1), wreg.toReg().toRealReg().?.hwEnc());
}

test "preg set operations" {
    const testing = std.testing;

    var set = PRegSet.empty();
    try testing.expect(set.isEmpty());

    const r0 = PReg.init(0, .int);
    const r5 = PReg.init(5, .int);
    const f0 = PReg.init(0, .float);

    set.add(r0);
    try testing.expect(set.contains(r0));
    try testing.expect(!set.contains(r5));
    try testing.expect(!set.contains(f0));

    set.add(f0);
    try testing.expect(set.contains(f0));

    set.remove(r0);
    try testing.expect(!set.contains(r0));
}

test "pinned vreg to preg conversion" {
    const testing = std.testing;

    // Pinned vreg (< 192) should convert to preg
    const pinned = VReg.init(5, .int);
    const preg = pinnedVRegToPReg(pinned);
    try testing.expect(preg != null);
    try testing.expectEqual(@as(u8, 5), preg.?.hwEnc());

    // Non-pinned vreg (>= 192) should not convert
    const user = VReg.init(200, .int);
    try testing.expect(pinnedVRegToPReg(user) == null);
}

// ============================================================================
// OperandCollector
// ============================================================================

/// An OperandCollector is a wrapper around a Vec of Operands
/// (flattened array for a whole sequence of instructions) that
/// gathers operands from a single instruction and provides the range
/// in the flattened array.
pub fn OperandCollector(comptime Renamer: type) type {
    return struct {
        operands: *std.ArrayListUnmanaged(Operand),
        allocator: std.mem.Allocator,
        clobbers: PRegSet,
        /// The subset of physical registers that are allocatable.
        allocatable: PRegSet,
        renamer: Renamer,

        const Self = @This();

        /// Start gathering operands into one flattened operand array.
        pub fn init(
            operands: *std.ArrayListUnmanaged(Operand),
            allocator: std.mem.Allocator,
            allocatable: PRegSet,
            renamer: Renamer,
        ) Self {
            return .{
                .operands = operands,
                .allocator = allocator,
                .clobbers = PRegSet.empty(),
                .allocatable = allocatable,
                .renamer = renamer,
            };
        }

        /// Finish the operand collection and return the tuple giving the
        /// range of indices in the flattened operand array, and the
        /// clobber set.
        pub fn finish(self: Self) struct { end: usize, clobbers: PRegSet } {
            return .{ .end = self.operands.items.len, .clobbers = self.clobbers };
        }

        // OperandVisitor implementation

        pub fn addOperand(
            self: *Self,
            reg: *Reg,
            constraint: OperandConstraint,
            kind: OperandKind,
            pos: OperandPos,
        ) void {
            std.debug.assert(!reg.isSpillSlot());
            // Apply renamer to the vreg
            const vreg_in = VReg{ .bits = reg.bits };
            const renamed = self.renamer.rename(vreg_in);
            reg.bits = renamed.bits;
            self.operands.append(self.allocator, Operand.init(
                VReg{ .bits = reg.bits },
                constraint,
                kind,
                pos,
            )) catch @panic("OOM in OperandCollector.addOperand");
        }

        pub fn debugAssertIsAllocatablePReg(self: Self, reg: PReg, expected: bool) void {
            std.debug.assert(self.allocatable.contains(reg) == expected);
        }

        pub fn regClobbers(self: *Self, regs: PRegSet) void {
            self.clobbers.unionWith(regs);
        }

        // OperandVisitorImpl default implementations

        /// Add a use of a fixed, nonallocatable physical register.
        pub fn regFixedNonallocatable(self: *Self, preg: PReg) void {
            self.debugAssertIsAllocatablePReg(preg, false);
            // Since this operand does not participate in register allocation,
            // there's nothing to do here.
        }

        /// Add a register use, at the start of the instruction (`Before` position).
        pub fn regUse(self: *Self, reg: *Reg) void {
            self.regMaybeFixed(reg, .use, .early);
        }

        /// Add a register use, at the end of the instruction (`After` position).
        pub fn regLateUse(self: *Self, reg: *Reg) void {
            self.regMaybeFixed(reg, .use, .late);
        }

        /// Add a register def, at the end of the instruction (`After`
        /// position). Use only when this def will be written after all
        /// uses are read.
        pub fn regDef(self: *Self, reg: *Writable(Reg)) void {
            self.regMaybeFixed(reg.regMut(), .def, .late);
        }

        /// Add a register "early def", which logically occurs at the
        /// beginning of the instruction, alongside all uses. Use this
        /// when the def may be written before all uses are read; the
        /// regalloc will ensure that it does not overwrite any uses.
        pub fn regEarlyDef(self: *Self, reg: *Writable(Reg)) void {
            self.regMaybeFixed(reg.regMut(), .def, .early);
        }

        /// Add a register "fixed use", which ties a vreg to a particular
        /// RealReg at the end of the instruction.
        pub fn regFixedLateUse(self: *Self, reg: *Reg, rreg: Reg) void {
            self.regFixed(reg, rreg, .use, .late);
        }

        /// Add a register "fixed use", which ties a vreg to a particular
        /// RealReg at this point.
        pub fn regFixedUse(self: *Self, reg: *Reg, rreg: Reg) void {
            self.regFixed(reg, rreg, .use, .early);
        }

        /// Add a register "fixed def", which ties a vreg to a particular
        /// RealReg at this point.
        pub fn regFixedDef(self: *Self, reg: *Writable(Reg), rreg: Reg) void {
            self.regFixed(reg.regMut(), rreg, .def, .late);
        }

        /// Add an operand tying a virtual register to a physical register.
        pub fn regFixed(self: *Self, reg: *Reg, rreg: Reg, kind: OperandKind, pos: OperandPos) void {
            std.debug.assert(reg.isVirtual());
            const real_reg = rreg.toRealReg() orelse @panic("fixed reg is not a RealReg");
            self.debugAssertIsAllocatablePReg(real_reg.preg, true);
            const constraint = OperandConstraint{ .fixed_reg = real_reg.preg };
            self.addOperand(reg, constraint, kind, pos);
        }

        /// Add an operand which might already be a physical register.
        pub fn regMaybeFixed(self: *Self, reg: *Reg, kind: OperandKind, pos: OperandPos) void {
            if (reg.toRealReg()) |rreg| {
                self.regFixedNonallocatable(rreg.preg);
            } else {
                std.debug.assert(reg.isVirtual());
                self.addOperand(reg, .reg, kind, pos);
            }
        }

        /// Add a register def that reuses an earlier use-operand's
        /// allocation. The index of that earlier operand (relative to the
        /// current instruction's start of operands) must be known.
        pub fn regReuseDef(self: *Self, reg: *Writable(Reg), idx: usize) void {
            const r = reg.regMut();
            if (r.toRealReg()) |rreg| {
                // In some cases we see real register arguments to a reg_reuse_def
                // constraint. We assume the creator knows what they're doing
                // here, though we do also require that the real register be a
                // fixed-nonallocatable register.
                self.regFixedNonallocatable(rreg.preg);
            } else {
                std.debug.assert(r.isVirtual());
                // The operand we're reusing must not be fixed-nonallocatable, as
                // that would imply that the register has been allocated to a
                // virtual register.
                const constraint = OperandConstraint{ .reuse = idx };
                self.addOperand(r, constraint, .def, .late);
            }
        }

        /// Add a def that can be allocated to either a register or a
        /// spillslot, at the end of the instruction (`After`
        /// position). Use only when this def will be written after all
        /// uses are read.
        pub fn anyDef(self: *Self, reg: *Writable(Reg)) void {
            self.addOperand(reg.regMut(), .any, .def, .late);
        }

        /// Add a use that can be allocated to either a register or a
        /// spillslot, at the end of the instruction (`After` position).
        pub fn anyLateUse(self: *Self, reg: *Reg) void {
            self.addOperand(reg, .any, .use, .late);
        }
    };
}

// ============================================================================
// OperandVisitor Interface
// ============================================================================

/// Interface for visiting/collecting operands from instructions.
/// This is the Zig equivalent of Cranelift's OperandVisitor trait.
pub const OperandVisitorVTable = struct {
    addOperandFn: *const fn (ctx: *anyopaque, reg: *Reg, constraint: OperandConstraint, kind: OperandKind, pos: OperandPos) void,
    debugAssertIsAllocatablePRegFn: ?*const fn (ctx: *anyopaque, reg: PReg, expected: bool) void,
    regClobbersFn: ?*const fn (ctx: *anyopaque, regs: PRegSet) void,
};

/// Generic operand visitor that wraps any type implementing the visitor interface.
pub const OperandVisitorGeneric = struct {
    ctx: *anyopaque,
    vtable: *const OperandVisitorVTable,

    const Self = @This();

    pub fn addOperand(self: Self, reg: *Reg, constraint: OperandConstraint, kind: OperandKind, pos: OperandPos) void {
        self.vtable.addOperandFn(self.ctx, reg, constraint, kind, pos);
    }

    pub fn debugAssertIsAllocatablePReg(self: Self, reg: PReg, expected: bool) void {
        if (self.vtable.debugAssertIsAllocatablePRegFn) |f| {
            f(self.ctx, reg, expected);
        }
    }

    pub fn regClobbers(self: Self, regs: PRegSet) void {
        if (self.vtable.regClobbersFn) |f| {
            f(self.ctx, regs);
        }
    }

    // OperandVisitorImpl default implementations

    pub fn regFixedNonallocatable(self: Self, preg: PReg) void {
        self.debugAssertIsAllocatablePReg(preg, false);
    }

    pub fn regUse(self: Self, reg: *Reg) void {
        self.regMaybeFixed(reg, .use, .early);
    }

    pub fn regLateUse(self: Self, reg: *Reg) void {
        self.regMaybeFixed(reg, .use, .late);
    }

    pub fn regDef(self: Self, reg: *Writable(Reg)) void {
        self.regMaybeFixed(reg.regMut(), .def, .late);
    }

    pub fn regEarlyDef(self: Self, reg: *Writable(Reg)) void {
        self.regMaybeFixed(reg.regMut(), .def, .early);
    }

    pub fn regFixedLateUse(self: Self, reg: *Reg, rreg: Reg) void {
        self.regFixed(reg, rreg, .use, .late);
    }

    pub fn regFixedUse(self: Self, reg: *Reg, rreg: Reg) void {
        self.regFixed(reg, rreg, .use, .early);
    }

    pub fn regFixedDef(self: Self, reg: *Writable(Reg), rreg: Reg) void {
        self.regFixed(reg.regMut(), rreg, .def, .late);
    }

    pub fn regFixed(self: Self, reg: *Reg, rreg: Reg, kind: OperandKind, pos: OperandPos) void {
        std.debug.assert(reg.isVirtual());
        const real_reg = rreg.toRealReg() orelse @panic("fixed reg is not a RealReg");
        self.debugAssertIsAllocatablePReg(real_reg.preg, true);
        const constraint = OperandConstraint{ .fixed_reg = real_reg.preg };
        self.addOperand(reg, constraint, kind, pos);
    }

    pub fn regMaybeFixed(self: Self, reg: *Reg, kind: OperandKind, pos: OperandPos) void {
        if (reg.toRealReg()) |rreg| {
            self.regFixedNonallocatable(rreg.preg);
        } else {
            std.debug.assert(reg.isVirtual());
            self.addOperand(reg, .reg, kind, pos);
        }
    }

    pub fn regReuseDef(self: Self, reg: *Writable(Reg), idx: usize) void {
        const r = reg.regMut();
        if (r.toRealReg()) |rreg| {
            self.regFixedNonallocatable(rreg.preg);
        } else {
            std.debug.assert(r.isVirtual());
            const constraint = OperandConstraint{ .reuse = idx };
            self.addOperand(r, constraint, .def, .late);
        }
    }

    pub fn anyDef(self: Self, reg: *Writable(Reg)) void {
        self.addOperand(reg.regMut(), .any, .def, .late);
    }

    pub fn anyLateUse(self: Self, reg: *Reg) void {
        self.addOperand(reg, .any, .use, .late);
    }
};

// ============================================================================
// Identity Renamer
// ============================================================================

/// Identity renamer that passes through vregs unchanged.
pub const IdentityRenamer = struct {
    pub fn rename(_: IdentityRenamer, vreg: VReg) VReg {
        return vreg;
    }
};

// ============================================================================
// PrettyPrint Interface
// ============================================================================

/// Pretty-print part of a disassembly, with knowledge of
/// operand/instruction size, and optionally with regalloc
/// results. This can be used, for example, to print either `rax` or
/// `eax` for the register by those names on x86-64, depending on a
/// 64- or 32-bit context.
pub const PrettyPrintVTable = struct {
    prettyPrintFn: *const fn (ctx: *const anyopaque, size_bytes: u8) []const u8,
};

/// Generic pretty printer interface.
pub const PrettyPrintGeneric = struct {
    ctx: *const anyopaque,
    vtable: *const PrettyPrintVTable,

    const Self = @This();

    pub fn prettyPrint(self: Self, size_bytes: u8) []const u8 {
        return self.vtable.prettyPrintFn(self.ctx, size_bytes);
    }

    pub fn prettyPrintDefault(self: Self) []const u8 {
        return self.prettyPrint(0);
    }
};

// ============================================================================
// OperandCollector Tests
// ============================================================================

test "operand collector basic" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var operands: std.ArrayListUnmanaged(Operand) = .{};
    defer operands.deinit(allocator);

    var collector = OperandCollector(IdentityRenamer).init(
        &operands,
        allocator,
        PRegSet.empty(),
        IdentityRenamer{},
    );

    // Create a virtual register
    var reg = Reg.fromVReg(VReg.init(200, .int));
    collector.addOperand(&reg, .reg, .use, .early);

    const result = collector.finish();
    try testing.expectEqual(@as(usize, 1), result.end);
    try testing.expect(result.clobbers.isEmpty());

    try testing.expectEqual(@as(usize, 1), operands.items.len);
    try testing.expectEqual(OperandKind.use, operands.items[0].kind);
    try testing.expectEqual(OperandPos.early, operands.items[0].pos);
}

test "operand collector with clobbers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var operands: std.ArrayListUnmanaged(Operand) = .{};
    defer operands.deinit(allocator);

    var collector = OperandCollector(IdentityRenamer).init(
        &operands,
        allocator,
        PRegSet.empty(),
        IdentityRenamer{},
    );

    var clobber_set = PRegSet.empty();
    clobber_set.add(PReg.init(0, .int));
    clobber_set.add(PReg.init(1, .int));
    collector.regClobbers(clobber_set);

    const result = collector.finish();
    try testing.expect(result.clobbers.contains(PReg.init(0, .int)));
    try testing.expect(result.clobbers.contains(PReg.init(1, .int)));
    try testing.expect(!result.clobbers.contains(PReg.init(2, .int)));
}
