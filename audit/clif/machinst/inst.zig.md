# inst.zig - Machine Instruction Framework

**Source:** `cranelift/codegen/src/machinst/mod.rs` (629 lines)

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `Type` | `Type` | ✅ Complete | IR types (I8-I128, F32-F128, vectors) |
| `MachLabel` | `MachLabel` | ✅ Complete | Branch target labels |
| `BlockIndex` | `BlockIndex` | ✅ Complete | Basic block indices |
| `StackSlot` | `StackSlot` | ✅ Complete | Stack slot references |
| `Reloc` | `Reloc` | ✅ Complete | Relocation types |
| `RelSourceLoc` | `RelSourceLoc` | ✅ Complete | Relative source locations |
| `MachTerminator` | `MachTerminator` | ✅ Complete | Block terminator classification |
| `CallType` | `CallType` | ✅ Complete | Call instruction types |
| `FunctionCalls` | `FunctionCalls` | ✅ Complete | Function call pattern tracking |
| `FunctionAlignment` | `FunctionAlignment` | ✅ Complete | Code alignment requirements |
| `MachInst` trait | Comptime interface | ✅ Complete | Machine instruction interface |
| `MachInstEmit` trait | Comptime interface | ✅ Complete | Instruction emission interface |

## Logic Comparison

### Type Encoding (mod.rs:112-150 → inst.zig:112-165)

**Cranelift:**
```rust
pub enum Type {
    INVALID = 0,
    I8 = 0x70,
    I16 = 0x71,
    I32 = 0x72,
    I64 = 0x73,
    // ...
}
```

**Cot:**
```zig
pub const Type = enum(u8) {
    INVALID = 0,
    I8 = 0x70,
    I16 = 0x71,
    I32 = 0x72,
    I64 = 0x73,
    // ...
};
```

✅ **Match:** Identical type codes matching Cranelift's IR type system.

### MachTerminator (mod.rs:180-200 → inst.zig:342-360)

**Cranelift:**
```rust
pub enum MachTerminator {
    None,
    Ret,
    RetCall,
    Branch,
}
```

**Cot:**
```zig
pub const MachTerminator = enum {
    none,
    ret,
    ret_call,
    branch,
};
```

✅ **Match:** Same variants for classifying block terminators.

### FunctionCalls Tracking (mod.rs:291-327 → inst.zig:382-410)

Both track whether a function contains calls (for prologue/epilogue optimization):

**Cranelift:**
```rust
pub enum FunctionCalls {
    None,
    TailOnly,
    Regular,
}
impl FunctionCalls {
    pub fn update(&mut self, call_type: CallType) {
        *self = match (*self, call_type) {
            (_, CallType::Regular) => FunctionCalls::Regular,
            (FunctionCalls::None, CallType::TailCall) => FunctionCalls::TailOnly,
            (current, _) => current,
        };
    }
}
```

**Cot:**
```zig
pub const FunctionCalls = enum {
    None,
    TailOnly,
    Regular,

    pub fn update(self: *Self, call_type: CallType) void {
        self.* = switch (call_type) {
            .Regular => .Regular,
            .TailCall => if (self.* == .None) .TailOnly else self.*,
            .None => self.*,
        };
    }
};
```

✅ **Match:** Same state machine for tracking call patterns.

## Trait Translation

Rust traits become Zig comptime interfaces. The pattern is:

**Cranelift (Rust trait):**
```rust
pub trait MachInst: Clone + Debug + Sized {
    type ABIMachineSpec: ABIMachineSpec<I = Self>;
    fn get_operands(&mut self, collector: &mut impl OperandVisitor);
    fn is_move(&self) -> Option<(Writable<Reg>, Reg)>;
    fn is_term(&self) -> MachTerminator;
    // ...
}
```

**Cot (comptime interface check):**
```zig
pub fn isMachInst(comptime T: type) bool {
    return @hasDecl(T, "getOperands") and
           @hasDecl(T, "isMove") and
           @hasDecl(T, "isTerm") and
           @hasDecl(T, "isLowLevelBranch") and
           @hasDecl(T, "isTrap");
}
```

✅ **Match:** Equivalent functionality through duck typing.

## Test Coverage

8 tests covering:
- Type encoding/decoding
- MachLabel creation
- CallType variants
- FunctionCalls state machine
- MachTerminator classification
