// RUN: %cot emit-cir %s | %FileCheck %s

// Feature #020: Break and continue — TypeScript syntax

function find_ten(): number {
    let i: number = 0;
    while (i < 100) {
        if (i === 10) {
            break;
        }
        i += 1;
    }
    return i;
}

function skip_five(): number {
    let total: number = 0;
    let i: number = 0;
    while (i < 10) {
        i += 1;
        if (i === 5) {
            continue;
        }
        total += i;
    }
    return total;
}

// CHECK-LABEL: func.func @find_ten
// CHECK: cir.br
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.cmp eq
// CHECK: cir.condbr
// break → branch to exit block
// CHECK: cir.br

// CHECK-LABEL: func.func @skip_five
// CHECK: cir.br
// CHECK: cir.cmp slt
// CHECK: cir.condbr
// CHECK: cir.cmp eq
// CHECK: cir.condbr
// continue → branch to header block
// CHECK: cir.br
