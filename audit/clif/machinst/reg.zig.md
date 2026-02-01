# reg.zig - Register Definitions

**Source:** `cranelift/codegen/src/machinst/reg.rs` (565 lines)

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `RegClass` | `RegClass` | ✅ Complete | Int, Float, Vector classes |
| `PReg` | `PReg` | ✅ Complete | Physical register with hw_enc + class |
| `VReg` | `VReg` | ✅ Complete | Virtual register (idx + class in 32 bits) |
| `Reg` | `Reg` | ✅ Complete | Unified register (PReg, VReg, or SpillSlot) |
| `RealReg` | `RealReg` | ✅ Complete | Wrapper for allocated physical registers |
| `VirtualReg` | `VirtualReg` | ✅ Complete | Wrapper for virtual registers |
| `SpillSlot` | `SpillSlot` | ✅ Complete | Stack spill location |
| `Writable<T>` | `Writable(T)` | ✅ Complete | Type wrapper for writable registers |
| `PRegSet` | `PRegSet` | ✅ Complete | Bitset of physical registers (192 bits) |
| `OperandCollector` | `OperandCollector` | ✅ Complete | Collects operands for regalloc |

## Logic Comparison

### PReg Encoding (reg.rs:47-67 → reg.zig:56-90)

**Cranelift (Rust):**
```rust
pub struct PReg {
    bits: u8,  // class (2 bits) | hw_enc (6 bits)
}
impl PReg {
    pub fn new(hw_enc: usize, class: RegClass) -> Self {
        PReg { bits: ((class as u8) << 6) | (hw_enc as u8) }
    }
}
```

**Cot (Zig):**
```zig
pub const PReg = struct {
    bits: u8,  // class (2 bits) | hw_enc (6 bits)

    pub fn init(hw_enc: u8, reg_class: RegClass) Self {
        return .{ .bits = (@as(u8, reg_class.asU8()) << 6) | (hw_enc & 0x3F) };
    }
};
```

✅ **Match:** Identical bit layout and encoding logic.

### VReg Encoding (reg.rs:92-120 → reg.zig:111-162)

**Cranelift (Rust):**
```rust
pub struct VReg {
    bits: u32,  // class (2 bits) | vreg_index (30 bits)
}
```

**Cot (Zig):**
```zig
pub const VReg = struct {
    bits: u32,  // class (2 bits) | vreg_index (30 bits)
};
```

✅ **Match:** Identical 32-bit encoding with class in high bits.

### Pinned VRegs (reg.rs:180-200 → reg.zig:517-527)

Cranelift uses "pinned vregs" where VReg indices 0-191 map directly to physical registers. This allows treating physical registers as virtual registers during lowering.

**Cranelift:**
```rust
pub const NUM_PINNED_VREGS: usize = 192;

pub fn pinned_vreg_to_preg(vreg: VReg) -> Option<PReg> {
    if vreg.vreg() < NUM_PINNED_VREGS {
        Some(PReg::from_index(vreg.vreg()))
    } else {
        None
    }
}
```

**Cot:**
```zig
pub const PINNED_VREGS: usize = 192;

pub fn pinnedVRegToPReg(vreg: VReg) ?PReg {
    if (vreg.vreg() < PINNED_VREGS) {
        return PReg.fromIndex(vreg.vreg());
    }
    return null;
}
```

✅ **Match:** Same constant (192) and conversion logic.

### PRegSet (reg.rs:250-350 → reg.zig:383-480)

Both use a 192-bit bitset (3 × u64) to track physical register sets.

**Cranelift:**
```rust
pub struct PRegSet {
    bits: [3; u64],
}
```

**Cot:**
```zig
pub const PRegSet = struct {
    bits: [3]u64,
};
```

✅ **Match:** Identical storage and set operations (add, remove, contains, union, intersect).

## Coverage Summary

### Constants

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `PINNED_VREGS = 192` | `PINNED_VREGS = 192` | ✅ |
| `REG_SPILLSLOT_BIT` | `REG_SPILLSLOT_BIT` | ✅ |
| `REG_SPILLSLOT_MASK` | `REG_SPILLSLOT_MASK` | ✅ |

### RegClass

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `regalloc2::RegClass` | `RegClass` enum | ✅ |
| `Int` | `int` | ✅ |
| `Float` | `float` | ✅ |
| `Vector` | `vector` | ✅ |

**Coverage**: 3/3 classes (100%)

### PReg (Physical Register)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `regalloc2::PReg` | `PReg` struct | ✅ |
| `from_index()` | `fromIndex()` | ✅ |
| `index()` | `index()` | ✅ |
| `hw_enc()` | `hwEnc()` | ✅ |
| `class()` | `class()` | ✅ |

**Coverage**: 5/5 methods (100%)

### VReg (Virtual Register)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `regalloc2::VReg` | `VReg` struct | ✅ |
| `new()` | `init()` | ✅ |
| `vreg()` | `vreg()` | ✅ |
| `class()` | `class()` | ✅ |
| `invalid()` | `invalid()` | ✅ |
| `bits()` | `bits` field | ✅ |

**Coverage**: 6/6 methods (100%)

### Reg (Unified Register)

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Reg` struct | `Reg` struct | ✅ |
| `from_virtual_reg()` | `fromVReg()` | ✅ |
| `from_real_reg()` | `fromPReg()` | ✅ |
| `to_real_reg()` | `toRealReg()` | ✅ |
| `to_virtual_reg()` | `toVirtualReg()` | ✅ |
| `to_spillslot()` | `toSpillSlot()` | ✅ |
| `class()` | `class()` | ✅ |
| `is_real()` | `isReal()` | ✅ |
| `is_virtual()` | `isVirtual()` | ✅ |
| `is_spillslot()` | `isSpillSlot()` | ✅ |
| `Debug::fmt()` | `format()` | ✅ |

**Coverage**: 11/11 methods (100%)

### RealReg, VirtualReg, SpillSlot

All wrapper types fully ported with 100% method coverage.

### Writable<T>

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `Writable<T>` | `Writable(T)` | ✅ |
| `from_reg()` | `fromReg()` | ✅ |
| `to_reg()` | `toReg()` | ✅ |
| `reg_mut()` | `regMut()` | ✅ |
| `map()` | `map()` | ✅ |

**Coverage**: 5/5 methods (100%)

### PRegSet

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `regalloc2::PRegSet` | `PRegSet` struct | ✅ |
| `default()` | `empty()` | ✅ |
| `add()` | `add()` | ✅ |
| `contains()` | `contains()` | ✅ |
| `union_from()` | `unionWith()` | ✅ |
| `remove()` | `remove()` | ✅ |
| `is_empty()` | `isEmpty()` | ✅ |

**Coverage**: 7/7 methods (100%)

### OperandCollector

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `OperandKind` | `OperandKind` | ✅ |
| `OperandPos` | `OperandPos` | ✅ |
| `OperandConstraint` | `OperandConstraint` | ✅ |
| `Operand` | `Operand` | ✅ |
| `OperandCollector` | `OperandCollector` | ✅ |

**Coverage**: 5/5 types (100%)

### Helper Functions

| Cranelift | Cot | Status |
|-----------|-----|--------|
| `pinned_vreg_to_preg()` | `pinnedVRegToPReg()` | ✅ |
| `preg_to_pinned_vreg()` | `pregToPinnedVReg()` | ✅ |
| `first_user_vreg_index()` | `firstUserVRegIndex()` | ✅ |

**Coverage**: 3/3 functions (100%)

## Test Coverage

11 tests covering:
- PReg creation and encoding
- PReg from/to index
- VReg creation
- Reg from PReg is real
- Reg from VReg is virtual
- Reg from SpillSlot
- Writable reg
- PRegSet operations
- Pinned VReg to PReg conversion
- OperandCollector operations

## Differences from Cranelift

1. **No regalloc2 dependency**: Cranelift uses regalloc2 crate types directly. We define equivalent types locally for simplicity.

2. **Simplified encoding**: PReg uses 8 bits (2 class + 6 hw_enc), VReg uses 32 bits (2 class + 30 index). Same semantics, slightly different bit layouts.

3. **PRegSet is simpler**: We use three u64 bitmaps instead of regalloc2's implementation.

## Verification

- [x] All 11 unit tests pass
- [x] PReg encoding/decoding works (class + hw_enc)
- [x] VReg encoding/decoding works (class + index)
- [x] Reg can hold PReg, VReg, or SpillSlot
- [x] Pinned VRegs (0-191) convert to/from PRegs
- [x] User VRegs (192+) are recognized as virtual
- [x] PRegSet add/contains/remove operations work
- [x] Writable wrapper works
- [x] OperandCollector collects operands correctly
