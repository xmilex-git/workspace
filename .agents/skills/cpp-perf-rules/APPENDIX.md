# Appendix A: Frequently Used Macros & Utilities

```c
/* branch hints */
#define LIKELY(x)   __builtin_expect(!!(x), 1)
#define UNLIKELY(x) __builtin_expect(!!(x), 0)

/* cache line */
#define CACHE_LINE 64
#define CACHE_ALIGNED __attribute__((aligned(CACHE_LINE)))

/* array length (compile error if used on a pointer) */
#define ARRAY_LEN(a) (sizeof(a) / sizeof((a)[0]))

/* power-of-two alignment */
#define ALIGN_UP(x, a)   (((x) + ((a) - 1)) & ~((a) - 1))
#define IS_POW2(x)       ((x) && !((x) & ((x) - 1)))

/* safe unaligned loads */
static inline uint32_t load_u32(const void *p) { uint32_t v; memcpy(&v,p,4); return v; }
static inline uint64_t load_u64(const void *p) { uint64_t v; memcpy(&v,p,8); return v; }

/* integer hash (splitmix64 family) */
static inline uint64_t mix64(uint64_t x) {
    x += 0x9E3779B97F4A7C15ULL;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ULL;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBULL;
    return x ^ (x >> 31);
}

/* relative-error floating-point equality */
static inline bool fp_eq_rel(double a, double b, double eps) {
    double d = fabs(a - b);
    double m = fmax(fabs(a), fabs(b));
    return d <= eps * fmax(m, 1.0);
}

/* prevent dead-code elimination in benchmarks */
#define DO_NOT_OPTIMIZE(x) __asm__ volatile("" : : "r,m"(x) : "memory")

/* yield the core while spin-waiting (PAR-12) */
static inline void cpu_relax(void) {
#if defined(__x86_64__) || defined(__i386__)
    __builtin_ia32_pause();
#elif defined(__aarch64__)
    __asm__ __volatile__("yield" ::: "memory");
#else
    __asm__ __volatile__("" ::: "memory");
#endif
}

/* cache-line-isolated global declaration (GLOB-02) */
#define HOT_GLOBAL(type, name) CACHE_ALIGNED type name

/* sharded counter (GLOB-09) */
#define STAT_SHARDS 64
typedef struct { uint64_t v; char _pad[CACHE_LINE - sizeof(uint64_t)]; } stat_shard_t;
_Static_assert(sizeof(stat_shard_t) == CACHE_LINE, "shard must be one cache line");

/* compile-time struct size verification (MEM-02, CLOW-15) */
#define ASSERT_SIZE(T, n)   _Static_assert(sizeof(T) == (n), #T " size changed")
#define ASSERT_FITS_LINE(T) _Static_assert(sizeof(T) <= CACHE_LINE, #T " exceeds cache line")
#define ASSERT_OFFSET(T, f, n) _Static_assert(offsetof(T, f) == (n), #T "." #f " moved")

/* compiler barrier — no instruction, only blocks reordering (COH-10) */
#define COMPILER_BARRIER() __asm__ __volatile__("" ::: "memory")

/* safe type reinterpretation (ALIAS-01) — memcpy optimizes to a single load */
#define BIT_CAST(dst_type, src) \
    __builtin_choose_expr(sizeof(dst_type) == sizeof(src), \
        ({ dst_type _d; memcpy(&_d, &(src), sizeof _d); _d; }), (void)0)

/* overlap check — for restrict path branching (ALIAS-03) */
#define NO_OVERLAP(a, b, n) ((const char*)(a) + (n) <= (const char*)(b) || \
                             (const char*)(b) + (n) <= (const char*)(a))

/* zero-safe bit ops (CLOW-13) */
static inline int clz64_safe(uint64_t x) { return x ? __builtin_clzll(x) : 64; }
static inline int ctz64_safe(uint64_t x) { return x ? __builtin_ctzll(x) : 64; }

/* HyperLogLog rank — strip top p bits, then leading zeros + 1 */
static inline int hll_rank(uint64_t w, int p) {
    uint64_t rest = w << p;
    return rest ? __builtin_clzll(rest) + 1 : (64 - p + 1);
}
```

---

# Appendix B: Multithread Scalability Diagnosis Procedure

Narrow down the cause of "more cores don't make it faster", in order.

```bash
# 0) First plot the throughput curve by thread count
for t in 1 2 4 8 16 32; do THREADS=$t ./bench; done
#   - linear rise then plateau     → resource saturation (memory bandwidth, I/O)
#   - decline past a point         → contention (false sharing, locks, atomics)
#   - no improvement from the start → serial-section dominance (Amdahl) or everyone waiting on one lock

# 1) Check cache-line contention (false sharing / atomic counters)
perf c2c record -- ./bench
perf c2c report --stdio
#   Top HITM (fetched from another core's cache) symbols are the culprits.
#   Global variable names → GLOB-02, struct arrays → MEM-03, refcounts → CPP-01

# 2) Check lock waiting
perf record -e sched:sched_switch -g -- ./bench     # where context switches are triggered
perf lock record ./bench && perf lock report        # kernel locks (where supported)
#   futex-related symbols at the top → mutex contention

# 3) Check the allocator
perf report | grep -iE 'malloc|free|arena|tcache'
#   near the top → PAR-11

# 4) Check NUMA
numastat -p $(pidof bench)          # per-node memory placement
perf stat -e node-load-misses,node-store-misses ./bench
#   high remote-access ratio → PAR-09

# 5) Check memory-bandwidth saturation
perf stat -e uncore_imc/data_reads/,uncore_imc/data_writes/ ./bench
#   at the bandwidth limit → not a contention problem but algorithm/data-volume (return to priority steps 1–2)
```

## Symptom → cause mapping

| Symptom | Check first | Rules |
|---|---|---|
| More threads make it slower | false sharing | MEM-03, GLOB-02 |
| Read-only yet doesn't scale | atomic reference counting | CPP-01 |
| Read-only yet doesn't scale (2) | rwlock reader counter | PAR-10 |
| Low IPC, high backend stalls | memory stalls | MEM-01, MEM-04, PAR-09 |
| `malloc` tops the profile | allocator contention | ALLOC-01, PAR-11 |
| 100% CPU but no progress | spin loops | PAR-12 |
| Degrades only as sockets grow | NUMA remote access | PAR-09 |
| Fast only with 1 thread | serial-section dominance | rethink the algorithm |
| Improvement vanishes only in parallel | parallel-only loop missed | PAR-14 |

---

# Appendix C: External Sources & Tools (optional reference)

The body is written to be sufficient on its own; consult these only for deeper dives.

| Source | Link | Notes |
|---|---|---|
| **Optimizing software in C++** (Agner Fog) | `agner.org/optimize/optimizing_cpp.pdf` | free; the de-facto standard document |
| **Instruction tables** (Agner Fog) | `agner.org/optimize/instruction_tables.pdf` | instruction latency/throughput |
| **Microarchitecture** (Agner Fog) | `agner.org/optimize/microarchitecture.pdf` | pipelines & branch-predictor internals |
| **What Every Programmer Should Know About Memory** (Drepper) | `lwn.net/Articles/250967/` | the classic on cache hierarchies |
| **Intel Optimization Reference Manual** | Intel developer site | official docs |
| **Modern Microprocessors: A 90-Minute Guide** | `lighterra.com/papers/modernmicroprocessors/` | condensed CPU internals |
| *Performance Analysis and Tuning on Modern CPUs* (Bakhvalov) | free PDF | practical perf/VTune |
| *Data-Oriented Design* (Richard Fabian) | free online | background for MEM-04 |
| Blogs | `easyperf.net`, `godbolt.org`, `quick-bench.com` | assembly & microbenchmarks |

**Tools:** `perf` (stat/record/annotate/c2c/lock), Intel VTune (Top-Down), Valgrind (cachegrind/callgrind),
`pahole` (struct layout), `numastat`/`numactl` (NUMA), Compiler Explorer (assembly).

> Installed in this container: `~/tools` has perf 4.18 + FlameGraph, heaptrack 1.2, bpftrace,
> VTune **2025.0** (the 2026 version doesn't support Cascade Lake). Usage: `dev/profiling-guide.md`.
