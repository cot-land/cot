# blockorder.zig - Block Ordering and Critical Edge Splitting

**Source:** `cranelift/codegen/src/machinst/blockorder.rs` (486 lines)
**Also includes:** Parts of `flowgraph.rs`, `dominator_tree.rs`, `entity/secondary.rs`

## Types Ported

| Cranelift Type | Zig Type | Status | Notes |
|----------------|----------|--------|-------|
| `LoweredBlock` | `LoweredBlock` | ✅ Complete | Original block or critical edge |
| `BlockLoweringOrder` | `BlockLoweringOrder` | ✅ Complete | Full block ordering algorithm |
| `SecondaryMap<K,V>` | `SecondaryMap(K,V)` | ✅ Complete | Entity map with default values |
| `ControlFlowGraph` | `ControlFlowGraph` | ✅ Complete | Predecessors/successors graph |
| `DominatorTree` | `DominatorTree` | ✅ Partial | Post-order and RPO (core for blockorder) |
| `visit_block_succs` | `visitBlockSuccs` | ✅ Complete | Successor visitor function |

## Logic Comparison

### LoweredBlock (blockorder.rs:95-143 → blockorder.zig:653-720)

**Cranelift:**
```rust
pub enum LoweredBlock {
    Orig { block: Block },
    CriticalEdge { pred: Block, succ: Block, succ_idx: u32 },
}

impl LoweredBlock {
    pub fn orig_block(&self) -> Option<Block> {
        match self {
            &LoweredBlock::Orig { block } => Some(block),
            &LoweredBlock::CriticalEdge { .. } => None,
        }
    }
}
```

**Cot:**
```zig
pub const LoweredBlock = union(enum) {
    orig: struct { block: Block },
    critical_edge: struct { pred: Block, succ: Block, succ_idx: u32 },

    pub fn origBlock(self: Self) ?Block {
        return switch (self) {
            .orig => |o| o.block,
            .critical_edge => null,
        };
    }
};
```

✅ **Match:** Same enum variants and accessor methods.

### BlockLoweringOrder Algorithm (blockorder.rs:147-310 → blockorder.zig:770-960)

The algorithm has three steps, all faithfully ported:

**Step 1:** Compute in-edge and out-edge counts for every block.

**Cranelift:**
```rust
for block in f.layout.blocks() {
    visit_block_succs(f, block, |_, succ, from_table| {
        block_out_count[block] += 1;
        block_in_count[succ] += 1;
        block_succs.push(LoweredBlock::Orig { block: succ });
    });
}
```

**Cot:**
```zig
var block_iter = func.layout.blocks();
while (block_iter.next()) |block| {
    try visitBlockSuccs(func, block, &edge_visitor);
    // edge_visitor increments counts and appends to block_succs
}
```

**Step 2:** Walk domtree RPO, identifying critical edges.

**Cranelift:**
```rust
for &block in domtree.cfg_rpo() {
    lowered_order.push(LoweredBlock::Orig { block });
    if block_out_count[block] > 1 {
        for (succ_ix, lb) in block_succs[range].iter_mut().enumerate() {
            if block_in_count[succ] > 1 {
                *lb = LoweredBlock::CriticalEdge { pred: block, succ, succ_idx };
                lowered_order.push(*lb);
            }
        }
    }
}
```

**Cot:**
```zig
var rpo_iter = domtree.cfgRpo();
while (rpo_iter.next()) |block| {
    try self.lowered_order.append(allocator, .{ .orig = .{ .block = block } });
    if (block_out_count.get(block) > 1) {
        // Identify and insert critical edges
    }
}
```

**Step 3:** Build successor tables for all lowered blocks.

✅ **Match:** All three steps implemented with same logic.

### visit_block_succs (inst_predicates.rs:162-212 → blockorder.zig:483-540)

**Cranelift:**
```rust
pub fn visit_block_succs<F: FnMut(Inst, Block, bool)>(
    f: &Function, block: Block, mut visit: F
) {
    match &f.dfg.insts[inst] {
        ir::InstructionData::Jump { destination, .. } => {
            visit(inst, destination.block(), false);
        }
        ir::InstructionData::Brif { blocks: [then, else_], .. } => {
            visit(inst, then.block(), false);
            visit(inst, else_.block(), false);
        }
        ir::InstructionData::BranchTable { table, .. } => {
            visit(inst, table.default_block(), false);
            for dest in table.as_slice() {
                visit(inst, dest.block(), true);  // from_table = true
            }
        }
        // ...
    }
}
```

**Cot:**
```zig
pub fn visitBlockSuccs(func: *const Function, block: Block, context: anytype) !void {
    switch (opcode) {
        .jump => {
            if (inst_data.getBlockDest()) |dest| {
                try context.call(last_inst, dest, false);
            }
        },
        .brif => {
            if (inst_data.getBrifDests()) |dests| {
                try context.call(last_inst, dests.then_dest, false);
                try context.call(last_inst, dests.else_dest, false);
            }
        },
        .br_table => {
            if (inst_data.getBrTableData()) |table_data| {
                try context.call(last_inst, table_data.default, false);
                for (table_data.targets) |target| {
                    try context.call(last_inst, target, true);
                }
            }
        },
        // ...
    }
}
```

✅ **Match:** Same branching logic, same from_table flag semantics.

## Included Dependencies

blockorder.zig includes these types that are separate modules in Cranelift:

| Type | Purpose | Cranelift Source |
|------|---------|-----------------|
| `SecondaryMap(K,V)` | Entity map with defaults | entity/secondary.rs |
| `ControlFlowGraph` | Pred/succ computation | flowgraph.rs |
| `DominatorTree` | RPO computation | dominator_tree.rs |
| `Block`, `Inst`, `Opcode` | CLIF IR entities | ir/entities.rs |
| `Function`, `Layout` | CLIF function structure | ir/function.rs, ir/layout.rs |

These are defined as stubs to keep machinst self-contained; in production they would be imported from compiler/ir/clif/.

## Test Coverage

11 tests covering:
- SecondaryMap operations (get/set/resize with defaults)
- LoweredBlock equality, hashing, and accessors
- BlockIndex validity checking
- ControlFlowGraph and DominatorTree initialization
- DominatorTree RPO iteration
- BlockLoweringOrder on linear CFG (no critical edges)
- BlockLoweringOrder on diamond CFG (proper edge handling)
