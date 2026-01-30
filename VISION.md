# Cot Language Vision

## What is Cot?

Cot is a compiled programming language for full-stack web development.

**The pitch:** Write like TypeScript, run like Rust, deploy anywhere, never think about memory.

---

## Language Position

```
                    Simple ←────────────────→ Complex
                       │                         │
     TypeScript ───────┼─────────────────────────┤  GC, slow
                       │                         │
            Go ────────┼─────────────────────────┤  GC, backend only
                       │                         │
           Cot ────────┼──────■                  │  ARC, Wasm-native
                       │                         │
         Swift ────────┼───────────■             │  ARC, no Wasm
                       │                         │
          Rust ────────┼─────────────────────────■  Borrow checker
```

### Comparison

| Language | Memory | Wasm Support | Full-stack | Learning Curve |
|----------|--------|--------------|------------|----------------|
| TypeScript | GC | Via tooling | Yes | Low |
| Go | GC | Poor | Backend only | Low |
| Rust | Borrow checker | Excellent | Yes | High |
| Swift | ARC | Experimental | No | Medium |
| **Cot** | **ARC** | **Native** | **Yes** | **Low-Medium** |

### The Gap Cot Fills

No existing language offers:
- Systems-language performance
- No manual memory management (ARC, not GC)
- Full-stack via Wasm (browser + server)
- Modern, approachable syntax

---

## Design Principles

### 1. Zig-Inspired Syntax, Simplified

```cot
// No semicolons
// Traits and impl blocks
// Type inference
// No allocator parameters

fn greet(name: string) string {
    return "Hello, " + name
}

struct User {
    name: string
    email: string
}

impl User {
    fn display(self) string {
        return self.name + " <" + self.email + ">"
    }
}
```

### 2. ARC Memory Management

Developers don't think about memory. The compiler handles it.

```cot
fn example() {
    let user = User { name: "Alice", email: "alice@example.com" }
    // Compiler inserts: retain(user)
    process(user)
    // Compiler inserts: release(user)
}
// No manual free, no GC pauses, no borrow checker fights
```

### 3. Wasm as Primary Target

```
Cot Source → Compiler → .wasm → Runs in browser
                              → Runs on server (via AOT or runtime)
```

Single language, single binary format, multiple deployment targets.

### 4. Full-Stack by Default

```cot
// shared/models.cot - runs on BOTH client and server
struct User {
    id: i64
    name: string
}

fn validate_email(email: string) bool {
    return email.contains("@")
}

// server/main.cot
@server
fn get_user(id: i64) User {
    return db.query("SELECT * FROM users WHERE id = ?", id)
}

// client/main.cot
@client
fn render_user(user: User) {
    dom.set_text("#name", user.name)
}
```

---

## Target Audience

Web developers who:
- Are frustrated with JavaScript's performance and type system
- Want to use a compiled language but find Rust too hard
- Want to write server + client in the same language
- Care about performance but don't want to manage memory manually

**Not for:**
- Operating system development
- Embedded systems with extreme memory constraints
- Developers who want fine-grained memory control

---

## Architecture

### Compilation Pipeline

```
Cot Source
    │
    ▼
┌─────────────────────────────────┐
│         Cot Compiler            │
│  (Written in Zig - permanent)   │
├─────────────────────────────────┤
│  Scanner → Parser → Checker     │
│  → Lowerer → IR → Wasm Codegen  │
└─────────────────────────────────┘
    │
    ▼
.wasm file
    │
    ├──────────────────┬──────────────────┐
    ▼                  ▼                  ▼
Browser            Wasm Runtime        AOT Compiler
(V8, SpiderMonkey)  (Development)     (Production)
                                          │
                                          ▼
                                    Native Binary
                                    (ELF, Mach-O)
```

### Why Zig for the Compiler?

Following the **Deno model**: Deno is written in Rust and runs JavaScript/TypeScript. It's not self-hosted, and that's fine.

Similarly, Cot's compiler is written in Zig. This is a **permanent** dependency, not a bootstrap.

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Compiler language | Zig | Simple, fast compilation, good Wasm support |
| Self-hosting | Future goal | Focus on language quality first |
| Zig dependency | Permanent (for now) | Like Deno's Rust dependency |

### Self-Hosting Strategy

Self-hosting is a **future goal**, not a prerequisite for shipping.

**Why defer self-hosting:**
- 5 previous attempts failed due to complexity
- Self-hosting proves "compiler complexity", not "web app capability"
- Better to prove the language with real applications first

**The plan:**
1. Ship Cot with Zig compiler
2. Build real applications in Cot
3. Stabilize the language
4. Attempt self-hosting when the language is mature

**When to attempt self-hosting:**
- Language syntax is frozen
- Standard library is complete
- Multiple real applications built successfully
- Compiler architecture is stable

Self-hosting becomes the "final exam" that proves language maturity, not the first test.

### Dogfooding Strategy

Since self-hosting is deferred, we need another way to prove the language works for real applications. The strategy: **build the Cot ecosystem in Cot**.

**cot.land - Package Manager**

Like deno.land, this is the official package registry and manager:
- Server-side Cot application
- API endpoints (package publish, search, download)
- Database integration (user accounts, package metadata)
- Authentication and authorization
- Proves: server-side Cot, HTTP, database, JSON handling

**cot.dev - Documentation & Playground**

The official Cot website:
- Documentation site (static generation)
- Interactive playground (Cot running in browser via Wasm)
- Marketing and community pages
- Proves: client-side Cot, DOM manipulation, Wasm in browser

**Why this approach:**
- Web framework is the target use case (proves what we're selling)
- More practical than compiler (serves the community)
- Exercises both client and server code paths
- Provides immediate value to users

**Self-hosting remains a long-term goal** for proving full language maturity. Once cot.land and cot.dev are running in production, and the language syntax is frozen, self-hosting becomes achievable and meaningful.

---

## Execution Roadmap

### Phase 1: Wasm Backend (Current)

**Goal:** Cot 0.3 emits valid Wasm

See **[WASM_BACKEND.md](WASM_BACKEND.md)** for detailed implementation plan.

```
src/codegen/wasm.zig
├── Wasm binary format (sections, types, code)
├── IR → Wasm stack machine translation
├── Function calls and control flow
└── Test: compile real programs, run in wasmtime
```

### Phase 2: Runtime & Memory

**Goal:** ARC memory management works in Wasm

```
├── Linear memory allocator
├── ARC retain/release runtime
├── String and array support
└── Test: programs with heap allocation
```

### Phase 3: Standard Library

**Goal:** Useful standard library for web development

```
std/
├── core (strings, arrays, math)
├── fs (file system - server only)
├── net (HTTP, WebSocket)
├── json (serialization)
└── dom (browser API - client only)
```

### Phase 4: AOT Native Compiler

**Goal:** Wasm → Native for production performance

```
├── Wasm parser
├── Wasm → SSA conversion
├── Register allocation (reuse existing)
├── Native codegen (reuse existing ARM64/AMD64)
└── Output ELF/Mach-O
```

### Phase 5: Ecosystem

**Goal:** Make Cot usable for real projects

```
├── Package manager
├── Build system
├── LSP (editor support)
├── Documentation generator
└── Example applications
```

### Phase 6: Self-Hosting (Future)

**Goal:** Prove language maturity

```
├── Compiler written in Cot
├── Compiles to Wasm
├── AOT compiles to native
├── Compiler compiles itself
└── Zig dependency becomes optional
```

---

## What Success Looks Like

### Short Term (6 months)
- Cot compiles to Wasm
- Hello world runs in browser and server
- Basic standard library exists

### Medium Term (1 year)
- Real web application built in Cot
- Package manager works
- Editor support (LSP)
- Small community forming

### Long Term (2+ years)
- Self-hosting achieved
- Production applications in the wild
- Ecosystem of libraries
- Zig dependency optional

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary target | Wasm | Universal, simpler than native |
| Memory management | ARC | No GC pauses, no borrow checker |
| Compiler language | Zig | Simple, fast, good Wasm support |
| Self-hosting | Deferred | Ship first, prove later |
| Syntax base | Zig-like | Familiar, readable, minimal |
| Niche | Full-stack web | Clear use case, underserved market |

---

## Reference Material

- `DESIGN.md` in bootstrap-0.2: Full technical architecture
- `README.md`: Current project status
- `CLAUDE.md`: Instructions for AI sessions
- `REFACTOR_PLAN.md`: Detailed progress tracking

---

## Summary

Cot is a pragmatic language for web developers who want:
- Performance without complexity
- One language for browser and server
- Modern syntax without legacy baggage
- Memory safety without mental overhead

The compiler stays in Zig until the language proves itself. Self-hosting is the graduation ceremony, not the entrance exam.
