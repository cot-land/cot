# Phase 7 - Phase C: Object File Generation

**Created**: 2026-02-03
**Status**: COMPLETE (2026-02-03)
**Based On**: Cranelift source code study (backend.rs, ObjectModule)

---

## Executive Summary

Phase C wires the MachBuffer output from VCode emission to object file generation (Mach-O/ELF):
- Task 7.7: ObjectModule - Bridge between MachBufferFinalized and object file writers

**Cranelift Files Studied**: `cranelift/object/src/backend.rs`

---

## Task 7.7: ObjectModule - Wire MachBuffer to Object Files

**Status**: [x] COMPLETE (2026-02-03)

### Cranelift Reference
- **File**: `cranelift/object/src/backend.rs`
- **Key Pattern**: ObjectModule wraps object crate's Object, provides `declare_function` and `define_function`

### Current State Analysis

**MachBufferFinalized (buffer.zig)** produces:
- `data: []const u8` - machine code bytes
- `relocs: []const FinalizedMachReloc` - relocations with ExternalName/CodeOffset targets
- `traps: []const MachTrap` - trap records
- `call_sites: []const MachCallSite` - call site records

**MachOWriter/ElfWriter** expect:
- `addCode(bytes)` - raw machine code
- `addSymbol(name, value, section, external)` - symbol entries
- `addRelocation(offset, target_name)` - relocations with string targets

### Gap Analysis

The main gap is **relocation target conversion**:
- MachBufferFinalized uses `FinalizedRelocTarget` (ExternalName or CodeOffset)
- Object writers use string symbol names

Need to:
1. Build symbol name table from function declarations
2. Convert ExternalName references to symbol names
3. Convert FinalizedMachReloc to object file relocations

### Cranelift Pattern (backend.rs)

```rust
pub struct ObjectModule {
    object: Object<'static>,
    functions: SecondaryMap<FuncId, Option<(SymbolId, bool)>>,
    data_objects: SecondaryMap<DataId, Option<SymbolId>>,
}

impl ObjectModule {
    pub fn declare_function(&mut self, name: &str, linkage: Linkage) -> FuncId {
        let symbol_id = self.object.add_symbol(Symbol {
            name: name.as_bytes().to_vec(),
            value: 0,
            kind: SymbolKind::Text,
            scope: linkage_to_scope(linkage),
            ..Default::default()
        });
        // Store mapping from FuncId to SymbolId
    }

    pub fn define_function_bytes(
        &mut self,
        func_id: FuncId,
        bytes: &[u8],
        relocs: &[MachReloc],
    ) {
        let (symbol_id, _) = self.functions[func_id].unwrap();

        // Add code to text section
        let offset = self.object.add_symbol_data(symbol_id, text_section, bytes, align);

        // Process relocations
        for reloc in relocs {
            let target_symbol = self.get_reloc_target_symbol(reloc.target);
            self.object.add_relocation(text_section, Relocation {
                offset: offset + reloc.offset as u64,
                symbol: target_symbol,
                kind: reloc_kind_to_object(reloc.kind),
                addend: reloc.addend,
            });
        }
    }
}
```

### Implementation Plan

#### 7.7.1 Create ObjectModule Interface
- [ ] Create `compiler/codegen/native/object_module.zig`
- [ ] Define FuncId, DataId types
- [ ] Define ObjectModule struct with:
  - Platform-specific object writer (MachOWriter or ElfWriter)
  - Function symbol map (FuncId → symbol name/index)
  - Data object map (DataId → symbol name/index)
  - External name table

#### 7.7.2 Implement declare_function
- [ ] Add function symbol to object file
- [ ] Store mapping from FuncId to symbol name
- [ ] Support different linkage (public/private)

#### 7.7.3 Implement define_function
- [ ] Take MachBufferFinalized from VCode emit
- [ ] Add code bytes to text section
- [ ] Convert and add relocations:
  - ExternalName.User → lookup in external name table
  - ExternalName.LibCall → library function name
  - FinalizedRelocTarget.Func → internal offset

#### 7.7.4 Implement Relocation Conversion
Map MachBuffer Reloc types to object file relocations:

**ARM64 (Mach-O)**:
| MachBuffer Reloc | Mach-O Relocation |
|------------------|-------------------|
| Arm64Call | ARM64_RELOC_BRANCH26 |
| Aarch64AdrPrelPgHi21 | ARM64_RELOC_PAGE21 |
| Aarch64AddAbsLo12Nc | ARM64_RELOC_PAGEOFF12 |
| Abs8 | ARM64_RELOC_UNSIGNED |

**AMD64 (ELF)**:
| MachBuffer Reloc | ELF Relocation |
|------------------|----------------|
| X86PCRel4 | R_X86_64_PC32 |
| X86CallPLTRel4 | R_X86_64_PLT32 |
| Abs8 | R_X86_64_64 |

#### 7.7.5 Wire into compile.zig
- [ ] Create ObjectModule at start of compilation
- [ ] Call declare_function for each function
- [ ] Call define_function after VCode emit
- [ ] Call finish() to write object file

#### 7.7.6 Add External Name Support
- [ ] UserExternalNameRef table (function names)
- [ ] LibCall handling (memcpy, etc.)
- [ ] KnownSymbol handling (GOT, TLS)

#### 7.7.7 Testing
- [ ] Simple function compiles to valid object file
- [ ] Relocations resolve correctly
- [ ] Multiple functions work
- [ ] External calls work

**Estimated LOC**: ~300 lines

---

## Implementation Details

### Relocation Target Resolution

```zig
fn resolveRelocTarget(
    self: *ObjectModule,
    target: FinalizedRelocTarget,
) []const u8 {
    return switch (target) {
        .ExternalName => |name| switch (name) {
            .User => |ref| self.external_names.get(ref.index),
            .LibCall => |lc| libCallName(lc),
            .KnownSymbol => |ks| knownSymbolName(ks),
            .TestCase => "_test",
        },
        .Func => |offset| {
            // Internal function reference - find symbol at offset
            return self.findSymbolAtOffset(offset);
        },
    };
}
```

### Platform Detection

```zig
pub const ObjectModule = struct {
    writer: union(enum) {
        macho: *MachOWriter,
        elf: *ElfWriter,
    },

    pub fn init(allocator: Allocator, target: Target) !ObjectModule {
        if (target.os == .macos) {
            return .{ .writer = .{ .macho = try MachOWriter.init(allocator) } };
        } else {
            return .{ .writer = .{ .elf = try ElfWriter.init(allocator) } };
        }
    }
};
```

---

## Progress Tracking

### Overall Progress
- [x] Task 7.7.1: Create ObjectModule interface - COMPLETE
- [x] Task 7.7.2: Implement declare_function - COMPLETE
- [x] Task 7.7.3: Implement define_function - COMPLETE
- [x] Task 7.7.4: Implement relocation conversion - COMPLETE
- [x] Task 7.7.5: Wire into driver.zig - COMPLETE
- [x] Task 7.7.6: Add external name support - COMPLETE
- [x] Task 7.7.7: Testing - COMPLETE (763 tests pass)

### Test Status
- [x] ObjectModule compiles
- [x] Simple function produces valid object file
- [x] Relocations work correctly
- [ ] Can link with system linker (end-to-end test pending)

---

## Files Created/Modified

| File | Status | Task |
|------|--------|------|
| `object_module.zig` | [x] Created | 7.7.1-7.7.4 |
| `driver.zig` | [x] Modified | 7.7.5 |
| `buffer.zig` | No changes needed | - |
| `macho.zig` | No changes needed | - |
| `elf.zig` | No changes needed | - |

---

## Notes

- MachOWriter already has comprehensive Mach-O support with DWARF debug info
- ElfWriter already has comprehensive ELF64 support
- Main work is creating the bridge layer (ObjectModule)
- Follow Cranelift's backend.rs pattern exactly
