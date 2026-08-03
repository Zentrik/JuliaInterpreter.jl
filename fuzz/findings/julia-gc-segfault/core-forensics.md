# Core-dump forensics (crash 8, official juliaup 1.12.6 binary)

Core: 827 MB, from `stock run 2` (evalcode axis, crashed ~3.5 min in;
core kept in the session scratchpad, too large to commit). The juliaup
binary ships DWARF, so gdb resolves everything.

## Faulting frame

```
#5  gc_mark_obj8 (nptr=22, obj8_end=0x7f5a04f8e259 <jl_system_image_data+156116569>,
                  obj8_begin=<optimized out>, obj8_parent=<optimized out>, ...)
    at src/gc-stock.c:1704
      slot    = 0x7f59cd8c1ca0
      new_obj = 0x706a665a00be8430     <- non-canonical: GP fault (si_code 128)
```

## The memory (annotated)

```
0x7f59cd8c1c88: 0x0000000000000023                       <- header: smalltag | GC bits
0x7f59cd8c1c90: 0x00007f59cc852b90  0x00007f5a00c76750   <- valid heap/sysimage ptrs
0x7f59cd8c1ca0: 0x706a665a00be8430  0x00007f5a65626f72   <- CORRUPT pair
0x7f59cd8c1cb0: 0x00007f59d87f14e8  0x00007f5a0c0a1050   <- valid again
```

Byte view of the corrupt pair (little-endian memory order):

```
ca0: 30 84 be 00 5a | 66 6a 70    low 5 bytes of a stale pointer, then "fjp"
ca8: 72 6f 62 65 | 5a 7f 00 00    "robe", then high bytes of a stale pointer
                    ^^^^^^^^^^^ bytes ca5..cab spell "fjprobe"
```

- `"fjprobe"` is the harness's write-probe payload
  (`fuzz/src/evalcodefuzz.jl:42`) — a 7-char String materialized
  thousands of times per run.
- A sibling object 64 bytes earlier carries a separate fragment
  `"be\0"` at the same offset.
- Only one `"fjprobe"` instance exists in the surrounding 64 KB, and the
  `"` quote bytes `repr` emits around the payload are absent.
- First field of the object chains to a typename-shaped record whose
  symbol reads `"#5#6"` (an anonymous-closure-related name); a healthy
  sibling's corresponding field chains to `"Type"`.

## Interpretation — final (after the -O1 core)

Two readings were entertained in sequence: (1) a wild 7-byte `memcpy`
over a live object; (2) — adopted to fit #62524 — a freshly allocated
object reaching a safepoint with uninitialized fields exposing
recycled-cell residue. **Reading (1) is correct.** The -O1 core
(crash 11) settled it: its victim is a fully-initialized, live
`Tuple{...}` DataType (typename `"Tuple"`) whose `instance` field was
legitimately NULL and `layout` valid, with an 8-byte `"fjprobe\0"`
written at the unaligned boundary between them — and
`jl_new_uninitialized_datatype` NULLs all pointer fields with no
safepoint gap, so partially-initialized DataTypes cannot exist. Both
cores show the same thing: **bulk string-payload writes through a wild
or stale destination pointer, landing at unaligned offsets inside live
type objects** in recycled DataType pool pages. Reproducing at `-O1`
places the buggy compiled writer in the sysimage (always built -O2) or
the C runtime — Base's buffered string/IO write paths are the standing
suspects. See ANALYSIS.md "CORRECTION" section.
