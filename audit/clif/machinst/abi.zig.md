# abi.zig - ABI Framework

**Source:** `cranelift/codegen/src/machinst/abi.rs` (2,617 lines)

## Architecture

The ABI module defines **interfaces** that each backend implements. The structure is:

```
abi.zig (common types + ABIMachineSpec interface)
    ├── arm64/abi.zig (ARM64 implementation)
    └── amd64/abi.zig (AMD64 implementation)
```

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `ArgPair` | `ArgPair` | ✅ Complete | Arg register bindings |
| `RetPair` | `RetPair` | ✅ Complete | Return register bindings |
| `ABIArgSlot` | `ABIArgSlot` | ✅ Complete | Reg or stack slot |
| `ABIArg` | `ABIArg` | ✅ Complete | Full argument description |
| `ArgsOrRets` | `ArgsOrRets` | ✅ Complete | Args vs rets enum |
| `StackAMode` | `StackAMode` | ✅ Complete | Stack addressing modes |
| `CallConv` | `CallConv` | ✅ Complete | Calling conventions |
| `ArgsAccumulator` | `ArgsAccumulator` | ✅ Complete | Arg collection helper |
| `CallInfo<T>` | `CallInfo(T)` | ✅ Complete | Call metadata |
| `Sig` | `Sig` | ✅ Complete | Signature reference |
| `SigData` | `SigData` | ✅ Complete | Signature data |
| `SigSet` | `SigSet` | ✅ Complete | Signature deduplication |
| `FrameLayout` | `FrameLayout` | ✅ Complete | Stack frame description |
| `Callee<M>` | `Callee(M)` | ✅ Partial | Function body ABI |

## Backend Implementation Pattern

The `ABIMachineSpec` trait defines the interface:

**Cranelift (Rust):**
```rust
pub trait ABIMachineSpec {
    type I: VCodeInst;
    type F: IsaFlags;

    const STACK_ARG_RET_SIZE_LIMIT: u32;

    fn word_bits() -> u32;
    fn word_bytes() -> u32;
    fn stack_align(call_conv: CallConv) -> u32;

    fn compute_arg_locs(
        call_conv: CallConv,
        params: &[AbiParam],
        args_or_rets: ArgsOrRets,
        args: ArgsAccumulator,
    ) -> CodegenResult<(u32, Option<usize>)>;

    fn gen_load_stack(mem: StackAMode, into: Writable<Reg>, ty: Type) -> Self::I;
    fn gen_store_stack(mem: StackAMode, from: Reg, ty: Type) -> Self::I;
    fn gen_move(to: Writable<Reg>, from: Reg, ty: Type) -> Self::I;
    fn gen_prologue_frame_setup(...) -> SmallInstVec<Self::I>;
    fn gen_epilogue_frame_restore(...) -> SmallInstVec<Self::I>;
    fn gen_clobber_save(...) -> SmallVec<[Self::I; 16]>;
    fn gen_clobber_restore(...) -> SmallVec<[Self::I; 16]>;
    // ... more methods
}
```

**Cot (comptime interface):**
```zig
pub fn isABIMachineSpec(comptime T: type) bool {
    return @hasDecl(T, "Inst") and
        @hasDecl(T, "wordBits") and
        @hasDecl(T, "wordBytes") and
        @hasDecl(T, "stackAlign") and
        @hasDecl(T, "computeArgLocs") and
        @hasDecl(T, "genLoadStack") and
        @hasDecl(T, "genStoreStack") and
        @hasDecl(T, "genMove") and
        @hasDecl(T, "getMachineEnv") and
        @hasDecl(T, "getSpillslotSize");
}
```

## Backend Files (To Be Created)

Each backend will implement ABIMachineSpec:

**arm64/abi.zig:**
```zig
pub const ARM64ABIMachineSpec = struct {
    pub const Inst = arm64.Inst;

    pub fn wordBits() u32 { return 64; }
    pub fn wordBytes() u32 { return 8; }

    pub fn stackAlign(call_conv: CallConv) u32 {
        return switch (call_conv) {
            .apple_aarch64 => 16,
            else => 16,
        };
    }

    pub fn computeArgLocs(...) !struct { u32, ?usize } {
        // ARM64-specific argument placement
    }

    pub fn genMove(to: Writable(Reg), from: Reg, ty: Type) Inst {
        // Generate ARM64 mov instruction
    }

    // ... implement all trait methods
};
```

**amd64/abi.zig:**
```zig
pub const AMD64ABIMachineSpec = struct {
    pub const Inst = amd64.Inst;

    pub fn wordBits() u32 { return 64; }
    pub fn wordBytes() u32 { return 8; }

    pub fn stackAlign(call_conv: CallConv) u32 {
        return switch (call_conv) {
            .windows_fastcall => 16,
            .system_v => 16,
            else => 16,
        };
    }

    // ... implement all trait methods for x86-64
};
```

## Logic Comparison

### ABIArg Creation (abi.rs:232-260 → abi.zig:268-310)

**Cranelift:**
```rust
impl ABIArg {
    pub fn reg(reg: RealReg, ty: Type, ext: ArgumentExtension, purpose: ArgumentPurpose) -> ABIArg {
        ABIArg::Slots {
            slots: smallvec![ABIArgSlot::Reg { reg, ty, extension: ext }],
            purpose,
        }
    }

    pub fn stack(offset: i64, ty: Type, ext: ArgumentExtension, purpose: ArgumentPurpose) -> ABIArg {
        ABIArg::Slots {
            slots: smallvec![ABIArgSlot::Stack { offset, ty, extension: ext }],
            purpose,
        }
    }
}
```

**Cot:**
```zig
pub const ABIArg = union(enum) {
    pub fn fromReg(reg: RealReg, ty: Type, ext: ArgumentExtension, purpose: ArgumentPurpose) Self {
        var slots = ABIArgSlotVec{};
        slots.appendAssumeCapacity(ABIArgSlot.fromReg(reg, ty, ext));
        return .{ .slots = .{ .slots = slots, .purpose = purpose } };
    }

    pub fn fromStack(offset: i64, ty: Type, ext: ArgumentExtension, purpose: ArgumentPurpose) Self {
        var slots = ABIArgSlotVec{};
        slots.appendAssumeCapacity(ABIArgSlot.fromStack(offset, ty, ext));
        return .{ .slots = .{ .slots = slots, .purpose = purpose } };
    }
};
```

✅ **Match:** Same factory methods for creating arguments.

### FrameLayout (abi.rs:1033-1134 → abi.zig:640-730)

**Cranelift:**
```rust
pub struct FrameLayout {
    pub word_bytes: u32,
    pub incoming_args_size: u32,
    pub tail_args_size: u32,
    pub setup_area_size: u32,
    pub clobber_size: u32,
    pub fixed_frame_storage_size: u32,
    pub stackslots_size: u32,
    pub outgoing_args_size: u32,
    pub clobbered_callee_saves: Vec<Writable<RealReg>>,
    pub function_calls: FunctionCalls,
}

impl FrameLayout {
    pub fn active_size(&self) -> u32 {
        self.outgoing_args_size + self.fixed_frame_storage_size + self.clobber_size
    }

    pub fn spillslot_offset(&self, slot: SpillSlot) -> i64 {
        let spill_off = slot.index() as i64 * self.word_bytes as i64;
        self.stackslots_size as i64 + spill_off
    }
}
```

**Cot:**
```zig
pub const FrameLayout = struct {
    word_bytes: u32 = 8,
    incoming_args_size: u32 = 0,
    tail_args_size: u32 = 0,
    setup_area_size: u32 = 0,
    clobber_size: u32 = 0,
    fixed_frame_storage_size: u32 = 0,
    stackslots_size: u32 = 0,
    outgoing_args_size: u32 = 0,
    clobbered_callee_saves: std.ArrayListUnmanaged(Writable(RealReg)) = .{},
    function_calls: FunctionCalls = .None,

    pub fn activeSize(self: Self) u32 {
        return self.outgoing_args_size + self.fixed_frame_storage_size + self.clobber_size;
    }

    pub fn spillslotOffset(self: Self, slot: SpillSlot) i64 {
        const spill_off = @as(i64, slot.index) * @as(i64, self.word_bytes);
        return @as(i64, self.stackslots_size) + spill_off;
    }
};
```

✅ **Match:** Same frame layout structure and offset calculations.

## What's Missing

Machine-specific implementations - these go in backend files:
- `arm64/abi.zig` - ARM64 ABIMachineSpec
- `amd64/abi.zig` - AMD64 ABIMachineSpec

## Test Coverage

11 tests covering:
- ABIArg creation (register and stack)
- StackAMode variants
- Sig creation and data
- SigSet deduplication
- FrameLayout calculations
