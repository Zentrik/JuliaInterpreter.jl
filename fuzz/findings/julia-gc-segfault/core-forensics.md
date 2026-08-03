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

## Interpretation (in light of JuliaLang/julia#62524)

Initially read as a wild 7-byte `memcpy` over a live object. The correct
reading, per #62524's mechanism, is the reverse: this is a **freshly
allocated object that reached a GC safepoint with some fields never
stored** (rooted-before-init boxed value under `-O2` DSE). The
"corrupt" bytes are simply the **previous contents of the recycled pool
cell** showing through the uninitialized fields — remnants of one of the
thousands of tiny `"fjprobe"` Strings (7 chars + NUL fits an osize-16
cell) and of older pointers, layered by successive cell reuse. The
valid-looking fields around them are the fields that *were* initialized
before the GC hit.

This single dump therefore physically exhibits the #62524 failure mode
on the official binary: uninitialized reference slots containing
recycled-cell garbage, scanned by the marker as if they were pointers.
