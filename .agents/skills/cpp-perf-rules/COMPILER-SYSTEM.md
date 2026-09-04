# §15 Compiler (CC)

## CC-01 — Baseline flags

```bash
-O2                 # safe default. Usually little difference vs -O3
-O3                 # aggressive vectorization/unrolling. Code growth → possible I-cache pressure
-march=native       # only when deployment targets are the same architecture
-mtune=generic      # when deployment targets vary
-flto               # link-time optimization. Cross-TU inlining
-fno-omit-frame-pointer   # accurate profiling (~1% perf cost)
-g                  # symbols. Keep in release builds to enable profiling
```

**Caution:** `-O3` is not always faster. Code bloat sometimes makes it slower — measure against `-O2`.

## CC-02 — Apply PGO (best effort-to-effect ratio)

```bash
# Pass 1: instrumented build
g++ -O2 -fprofile-generate -o app.inst ...
./app.inst < representative_workload      # representative workload is mandatory

# Pass 2: profile-guided build
g++ -O2 -fprofile-use -fprofile-correction -o app ...
```

Branch hints, inlining decisions, and hot/cold code placement get optimized from real measurements.
**PGO with a non-representative workload backfires.**

## CC-03 — Release aliasing to permit vectorization

```c
void axpy(double * restrict y, const double * restrict x, double a, size_t n);
```

`restrict` is non-standard in C++ — use `__restrict__` (GCC/Clang). Misuse is UB, so real non-overlap must be guaranteed. Details in the ALIAS section.

## CC-04 — Verify vectorization actually happened

```bash
g++     -O3 -fopt-info-vec -fopt-info-vec-missed src.cpp
clang++ -O3 -Rpass=loop-vectorize -Rpass-missed=loop-vectorize src.cpp
```

**Common vectorization blockers:** pointer aliasing, function calls in the loop, conditional branches, non-sequential access (gather), loop-carried dependencies, possible signed-integer overflow, unknown trip count.

## CC-05 — Control inlining deliberately

```c
static inline           /* small hot functions in headers */
__attribute__((always_inline))   /* force. Abuse → I-cache pressure */
__attribute__((noinline))        /* push cold paths out */
__attribute__((hot)) / ((cold))  /* code-placement hints */
```

**Rule:** splitting cold paths (error handling) out with `noinline` raises hot-path I-cache efficiency. This beats `always_inline` abuse.

> **Unconditional-per-row-call check:** an out-of-line function called every iteration of a hot loop is a cost in itself (5–25 cycles + an optimization barrier). If the function body "does nothing in most cases," hoist the condition to the call site or specialize so it's called only when needed. Watch especially for resource-cleanup/init utilities called unconditionally even for fixed-width types.

## CC-06 — Never rely on signed integer overflow

It is UB, and the compiler may remove the overflow check itself. If wrapping is needed, use unsigned or `__builtin_add_overflow`.

```c
if (__builtin_mul_overflow(a, b, &result)) goto overflow;
```

Use signed integers or `size_t` consistently for loop indices. Sign mixing can insert a sign-extension instruction per iteration (CLOW-07).

> The old idiom of `volatile` + post-hoc checking for overflow forces memory round trips and is slow.
> `__builtin_*_overflow` does the same check via the flags register and keeps the value in a register.

## CC-07 — Inspect the assembly

For important hot functions, look at the generated assembly directly. Verify the expected instructions (cmov, vector instructions, multiply substitution) appeared.

```bash
g++ -O3 -S -masm=intel -o - src.cpp | less
objdump -d --no-show-raw-insn -M intel binary | less
perf annotate -s hot_function
```

---

# §16 I/O & System (SYS)

## SYS-01 — Batch system calls
One syscall costs 500–2,000 cycles. Buffer instead of repeating small reads/writes.

## SYS-02 — Tell the kernel your access pattern

```c
posix_fadvise(fd, off, len, POSIX_FADV_SEQUENTIAL);  /* sequential scan */
posix_fadvise(fd, off, len, POSIX_FADV_WILLNEED);    /* will read soon */
posix_fadvise(fd, off, len, POSIX_FADV_DONTNEED);    /* prevent cache pollution */
madvise(ptr, len, MADV_SEQUENTIAL | MADV_WILLNEED);
```

On large sequential scans, cleaning the page cache with `DONTNEED` protects other workloads' cache.

## SYS-03 — Propagate page-fault errors
Ignoring page fix/pin failure reads bad data. Always check return values.

## SYS-04 — Use shell builtins where fork overhead bites

When process resources are exhausted (e.g. a crash loop), external commands fail to execute. Build diagnosis/recovery paths from shell builtins only.

```bash
# work without fork (builtins)
echo, printf, read, cd, kill, exec, [[ ]], while, for
# need fork (fail under exhaustion)
ls, cat, ps, grep, awk, sed
```

## SYS-05 — Disable Nagle on small request–response sockets (TCP_NODELAY)

Nagle's algorithm **waits for an ACK** to coalesce small packets — in a request–response (RPC) pattern that wait is added straight onto round-trip latency. One socket option removes it:

```c
int yes = 1;
setsockopt (fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof (yes));
```

- DB relevance: **client↔broker↔CAS↔server are all request–response sockets.** In a many-small-queries workload, a missing NODELAY anywhere on the connection path can add tens of ms per query.
- Bulk streaming (result-set bulk transfer) may benefit from Nagle instead — decide per pattern.
- Review point: in code that opens a new socket, confirm whether the presence/absence of this option is **intent or omission**.
