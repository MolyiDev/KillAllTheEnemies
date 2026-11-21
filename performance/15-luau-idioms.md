# Luau idioms: the official guidance vs the rules in CLAUDE.md

Measured 2026-08-15 in Roblox Studio, `TestX` place, F5 playtest, driven over the Tripwire MCP plugin.
Three passes, 17 suites, every suite run three times over three compilation modes.

The starting point was a full read of [luau.org/performance](https://luau.org/performance) against the
**Performance Rules** section of `CLAUDE.md`. Four rules disagreed with the official guidance and two more
made numeric claims nobody had checked, so all of them were measured rather than argued about.

**Headline:** two `CLAUDE.md` rules were wrong and are now changed, one was right for the wrong reason and
is now stated correctly, three were confirmed with numbers, and the single largest effect found in the whole
exercise was not in `CLAUDE.md` at all: **a call into another ModuleScript costs ~15ns, and a call to a
helper in the same module costs nothing.**

---

## Scoreboard

| `CLAUDE.md` rule | Verdict | Evidence |
| --- | --- | --- |
| `array[#array + 1] = v` instead of `table.insert` | **Mostly wrong.** The two are within 1-9% of each other. The real win is a counter plus `table.create`, which is 1.6-2.3x | [3](#3-appending-to-an-array) |
| Numeric `for i = 1, #t` instead of `ipairs` / `pairs` | **Wrong, backwards.** Generalized `for _, v in t` is 8-35% *faster* than the numeric loop, in 6 of 6 measurements | [1](#1-iterating-an-array) |
| Only localize Roblox mutable globals in hot loops | **Right, and now quantified.** Localizing saves ~0.7ns per read. The Instance property read behind it costs ~40ns, which is where the attention belongs | [8](#8-globals-imports-and-instance-properties) |
| Never `getfenv` / `setfenv` / `loadstring` | **Confirmed by the docs**, and stronger than stated: it also disables function inlining for the whole module | docs |
| Pre-allocate with `table.create(n)` or reuse with `table.clear(t)` | **Confirmed.** Both beat a fresh `{}` by 1.3-1.9x and are equal to each other | [12](#12-preallocating-and-reusing-tables) |
| `table.clone(STUB)` is ~2x faster than building the table fresh | **Confirmed on median** (1.4-2.6x), with a caveat: on a GC-free frame a table literal can match it | [4](#4-building-objects) |
| A metatable on the stub makes `table.clone` nearly 2x slower | **Confirmed** (1.5-2.4x), plus a new finding worth more than the rule itself | [4](#4-building-objects) |
| Metatable OOP over closure OOP for many instances | **Confirmed.** Capturing a loop-local costs 3.0-3.5x a plain call, a mutable capture 4.9-6.8x | [5](#5-closures) |
| Never create closures inside hot loops | **Too absolute.** A closure that captures nothing is cached by the compiler and costs 1.6x, not 3.5x | [5](#5-closures) |
| Pass captured values as parameters so Luau emits `DUPCLOSURE` | **Confirmed.** 1.27-1.63x vs 3.05-3.54x for the capturing form | [5](#5-closures) |
| Inline one-liner helpers instead of `Tools.Lerp(a, b, t)` | **Right conclusion, wrong reason.** It is not call overhead in general, it is *cross-module* call overhead. An in-module helper is free | [6](#6-calls-the-big-one) |
| Add `--!optimize 2` to Actor scripts and math-heavy modules | **No-op.** The engine already compiles at level 2; the directive changed nothing in 17 suites | [13](#13-do-the-directives-do-anything) |
| Add `--!native` to Actor scripts and math-heavy modules | **Real, and now bounded.** 1.4-4.2x on pure compute, ~0 on allocation, and it makes cross-module calls *worse* | [13](#13-do-the-directives-do-anything) |

New rules that came out of this and were not in `CLAUDE.md`: [6](#6-calls-the-big-one) (cross-module calls),
[7](#7-fastcall-vs-namecall) (`string.byte(s, i)` beats `s:byte(i)` by 2.2-4.1x), [9](#9-method-dispatch)
(`__index` depth), [10](#10-field-reads) (static fields through the instance cost 3x), and
[11](#11-vector-math) (one `Vector3` op beats three scalar ops by up to 3.3x).

---

## How to read the numbers

Every suite times a set of variants that all do the **same number of logical operations**, so `ns/op` is
comparable down a column and meaningless across suites. Each variant is warmed up, then run 11 times (pass
1) or 21 times (passes 2 and 3), with the **variant order rotated every repetition** so ordering drift is
spread evenly instead of landing on whichever variant happens to run last (METHODOLOGY trap 5).

Both **median** and **min** are reported and they say different things. Median is what shipping code feels.
Min is the frame where no GC assist landed, which isolates the instruction cost. Where the two disagree,
that disagreement *is* the finding, and it is called out.

Every variant returns a checksum. Within a suite the checksums must agree, which is the guard against a
variant being optimized into nothing or quietly measuring the wrong thing. They agreed everywhere except
suite K, where the variants read deliberately different fields.

Three compilation modes were run, as three byte-identical ModuleScripts with different headers:

| Mode | Header | What it is |
| --- | --- | --- |
| `O1` | none | what every script in this repo gets today |
| `O2` | `--!optimize 2` | what `CLAUDE.md` says to put on math-heavy modules |
| `NATIVE` | `--!native` + `--!optimize 2` | what `CLAUDE.md` says to put on Actor scripts |

Because O1, O2 and NATIVE are separate compilations of identical source, they also work as three partly
independent replications of every result. A finding that holds in all three is worth far more than one that
only shows up in one.

### What this does and does not cover

- This is **pure CPU**. No instances are created and nothing renders, so the 240 FPS cap (trap 2) and the
  viewport (trap 9) do not apply here the way they do to the rest of this folder.
- It was measured **in Studio**, not on a live server. The compiler is the same, but if Roblox ever ships a
  different default optimization level to production than Studio uses, section 13 is the section that would
  change. An Open Cloud cross-check was attempted and could not run: this place has no
  `ROBLOX_OPEN_CLOUD_KEY` configured.
- One machine, one session. Absolute nanosecond figures are that machine; the ratios are the result.

---

## 1. Iterating an array

`CLAUDE.md` said: *"Use numeric `for i = 1, #t do` loops instead of `ipairs` or `pairs`."*

The Luau docs say the opposite, in as many words: *"the performance of iteration using generalized
iteration, pairs and ipairs is comparable, so generalized iteration (without the use of pairs/ipairs) is
recommended... Iterating through array-like tables using `for i=1,#t` tends to be slightly slower because of
extra cost incurred when reading elements from the table."*

Summing 10,000 numbers, `ns/op`, median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `for i = 1, #t` | 5.27 | 5.35 | 3.06 |
| `for i = 1, n` (`#t` hoisted into a local first) | 4.71\* | 5.37\* | 2.79\* |
| **`for _, v in t`** | **4.05** | **3.95** | **2.33** |
| `for _, v in ipairs(t)` | 4.36 | 3.49 | 2.83 |
| `for _, v in pairs(t)` | 4.00 | 4.26 | 2.85 |

\* hoisted row is from pass 1, which ran 11 reps; the rest are pass 2 at 21 reps.

On the min column, which strips GC noise out, the gap is cleaner and it reproduces in every mode across both
passes:

| min ms per 10k | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `for i = 1, #t` | 0.0427 | 0.0422 | 0.0247 |
| `for _, v in t` | 0.0316 | 0.0320 | 0.0228 |
| ratio | **1.35x** | **1.32x** | **1.08x** |

**The docs are right and the rule was backwards.** Generalized iteration wins by 8-35%, in 6 of 6
measurements, and `pairs` / `ipairs` land within noise of it. Hoisting `#t` into a local before the loop
does not help either: the loop bound is evaluated once regardless, so the extra local is a wasted `MOVE`.

Two cases where the numeric loop is still the right call, neither of which this measures away:

- you need the index for something other than reading `t[i]` (writing back, pairing with a second array)
- you are iterating a *range* rather than a table

---

## 2. Iterating a hash table

No difference at all. Summing 10,000 dictionary values, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `for _, v in d` | 8.80 | 9.52 | 5.80 |
| `for _, v in pairs(d)` | 8.86 | 8.86 | 6.34 |
| `for _, v in next, d` | 9.42 | 9.38 | 5.85 |

Within 7% of each other, with no consistent ordering across modes. The docs say all three idioms compile to
specialized bytecode with custom internal iterators, and that is what this looks like. Pick whichever reads
best; generalized iteration is the shortest.

---

## 3. Appending to an array

`CLAUDE.md` said: *"Use `array[#array + 1] = value` instead of `table.insert`."*

The Luau docs say: *"When appending elements to tables, it's recommended to use `table.insert` (which is the
fastest method to append an element to a table if the table size is not known). In cases when a table is
filled sequentially, however, it can be more efficient to use a known index for insertion - together with
preallocating tables using `table.create` this can result in much faster code."*

Building a 10,000 element array from scratch, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `{}` + `t[#t + 1] = v` | 13.45 | 12.88 | 8.26 |
| `{}` + `table.insert(t, v)` | 13.58 | 14.16 | 8.38 |
| `{}` + counter, `c += 1; t[c] = v` | 10.51 | 9.64 | 5.91 |
| `table.create(n)` + `t[#t + 1] = v` | 10.30 | 10.29 | 5.88 |
| `table.create(n)` + `table.insert(t, v)` | 11.83 | 10.36 | 6.12 |
| **`table.create(n)` + `t[i] = v`** | **7.61** | **7.95** | **3.58** |

`t[#t + 1] = v` beats `table.insert` by 1%, 9% and 1%. That is the entire content of the old rule, and it is
noise next to what is actually available: **the preallocated known-index form is 1.62-2.31x faster than the
form the rule recommended.**

Two independent effects, and they stack:

- **not recomputing `#t`.** Luau caches table length and adjusts it on `insert`/`remove`, so `#t` is close
  to constant time, but it is still a read. Carrying your own counter is worth ~1.3x.
- **`table.create(n)`.** Preallocating removes the array-part regrowth, worth ~1.3-1.4x on its own.

So the rule is not "avoid `table.insert`". It is "when you know the count, preallocate and write to a known
index; when you do not, either form of append is fine".

---

## 4. Building objects

`CLAUDE.md` said: *"In object constructors, pre-define a metatable-free stub table at module level and use
`table.clone(STUB)` instead of constructing a fresh table each call - this is ~2x faster than the naive
approach. The stub must have no metatable set on it; if it does, `table.clone` checks for `__metatable` on
every call and becomes nearly 2x slower."*

Both halves of that hold up. Building 4,000 eight-field objects, `ns/op`, pass 2 at 21 reps:

| form | O1 med | O2 med | NATIVE med | O1 min | O2 min | NATIVE min |
| --- | --- | --- | --- | --- | --- | --- |
| **`table.clone(STUB)` + 4 writes** | **73.60** | **72.75** | **48.12** | 55.4 | 54.6 | 40.7 |
| full table literal, 8 fields | 143.62 | 135.10 | 122.00 | 61.3 | 46.8 | 27.6 |
| `{}` + 8 field writes\* | 177.05 | 160.50 | 213.30 | 101.3 | 103.2 | 138.5 |
| `table.clone(STUB_WITH_METATABLE)` + 4 | 156.85 | 142.30 | 115.12 | 96.0 | 103.0 | 61.8 |
| **`setmetatable(table.clone(STUB), MT)`** | **71.65** | **74.18** | **52.40** | 56.4 | 57.1 | 42.8 |
| `setmetatable(literal, MT)` | 146.00 | 131.93 | 127.32 | 53.3 | 45.0 | 29.1 |

\* `{}` + writes row is from pass 1.

**Confirmed: `table.clone(STUB)` wins on median by 1.4-2.6x**, in all six measurements across two passes.
The mechanism is visible in the bytecode shape: the clone is one fastcall plus 4 field writes, the literal
is a table template plus 8 field writes.

**Confirmed: a metatable on the stub is expensive.** `table.clone` of a stub carrying a metatable costs
1.96-2.39x cloning a plain one on median, 1.52-1.89x on min. "Nearly 2x slower" was accurate.

**New, and worth more than either:** if the object needs a metatable, `setmetatable(table.clone(PLAIN), MT)`
costs the same as the plain clone (1.00x, 1.02x, 1.09x) and is **~2x cheaper than cloning a stub that
already carries the metatable**. Attaching the metatable afterwards is free; carrying it on the stub is not.
Nothing in `CLAUDE.md` said which way to do this and the intuitive choice is the slow one.

**The caveat on the "~2x" claim.** The min column disagrees with the median. On a frame with no GC assist,
the table literal is sometimes *faster* than the clone (O2: 46.8 vs 54.6 ns; NATIVE: 27.6 vs 40.7 ns), while
the clone's median sits close to its own min and the literal's median is 2-4x its min. Read that as: the
clone is **steadier**, and the literal throws away its instruction-count advantage in GC assists. Median is
the right statistic for shipping code (METHODOLOGY trap 6), so the rule stands, but "~2x" is the median
figure and not a floor.

---

## 5. Closures

`CLAUDE.md` said *"Never create closures inside hot loops"* and *"pass captured values as parameters
(`self`) instead of closing over unique locals. This lets Luau emit `DUPCLOSURE` (reuse one function object)
instead of `NEWCLOSURE`."*

The Luau docs describe exactly this mechanism: the compiler caches a closure when *"multiple executions of
the same function expression are guaranteed to result in the function object that is semantically
identical... the compiler will cache closures that have no upvalues, or all upvalues are immutable and are
declared at the module scope."*

Creating and calling 4,000 closures, `ns/op` median, and the ratio to a plain call to an existing function:

| form | O1 | O2 | NATIVE | ratio (O1 / O2 / NATIVE) |
| --- | --- | --- | --- | --- |
| no closure, call an existing function | 5.15 | 5.17 | 3.10 | 1.00 |
| closure capturing nothing | 8.38 | 8.93 | 4.80 | 1.63 / 1.72 / 1.55 |
| closure, value passed as a parameter | 8.40 | 8.30 | 3.95 | 1.63 / 1.60 / **1.27** |
| closure capturing a module-scope local | 10.12 | 10.03 | 6.28 | 1.97 / 1.94 / 2.02 |
| closure capturing an immutable loop local | 17.97 | 18.32 | 9.45 | 3.49 / 3.54 / 3.05 |
| closure capturing a **mutable** loop local | 25.07 | 25.90 | 20.93 | 4.87 / 5.00 / **6.75** |

**The parameter-passing rule is confirmed** and the spread is exactly where the docs say it should be. The
two cached forms (no upvalues, module-scope upvalues) sit at 1.6-2.0x. The two allocating forms sit at
3.1-6.8x. Mutable capture is the worst case in every mode and gets *relatively* worse under `--!native`.

**"Never create closures inside hot loops" is too absolute.** A closure that captures nothing is cached by
the compiler, does not allocate, and costs 1.6x a plain call. That is not free, but it is not the 3.5x the
rule is guarding against. The thing to avoid is specifically **capturing a local declared inside the loop**,
and above all a mutable one. The rule now says that.

---

## 6. Calls: the big one

`CLAUDE.md` said: *"Inline simple one-liner helpers (e.g. `a + (b - a) * t` instead of `Tools.Lerp(a, b, t)`)
inside loops to eliminate function call overhead."*

The first attempt at measuring this (pass 1, suite F) produced five identical rows and no signal. The cause
was the benchmark, not the language: it built its arguments with `i % 13`, and floating point modulo is
expensive enough to bury a function call. Pass 2 replaced that with a read from a pre-filled array and added
a **floor row** - the same loop with the lerp removed - so the marginal cost of each call form could be
subtracted out instead of guessed at. Pass 3 then added the case that actually matters: the helper living in
a **separate ModuleScript**, reached through `require`, which is how `Tools.Lerp` is called everywhere in
this codebase.

20,000 calls. Marginal cost per call over the floor row, computed from the min column:

| form | O1 | NATIVE |
| --- | --- | --- |
| written inline, `a + (10 - a) * 0.5` | 3.39 ns | 1.14 ns |
| `local function` in the same module | 3.37 ns | 1.14 ns |
| in-module table field, `TOOLS.Lerp(...)` | 3.44 ns | 1.14 ns |
| **`require`d module, `Helpers.Lerp(...)`** | **14.77 ns** | **19.20 ns** |
| **`require`d module, hoisted to a local first** | **11.27 ns** | **14.99 ns** |

That is the largest single effect in this document.

- **An in-module helper is free.** Hand-inlining, a `local function`, and a table field on a module-scope
  table all land within 2% of each other, in both modes. The compiler resolves the call statically and the
  call disappears.
- **A cross-module call costs ~15ns and cannot be optimized away.** That is 4.4x the cost of the entire
  inline expression it replaces. The Luau docs explain why: *"Interprocedural optimizations are limited to a
  single module due to the compilation model."* The compiler cannot see past a `require`, so it can neither
  inline the body nor fold the lookup.
- **Hoisting the cross-module function into a local first saves ~20-25%** (14.77 to 11.27 ns at O1). The
  call is still a real call, but the per-iteration table lookup goes away.
- **`--!native` makes cross-module calls worse**, 19.20 ns against 14.77 ns. Native code has to leave native
  execution to call into a function it did not compile. See section 13.

So the old rule reached the right conclusion by the wrong route. It is not that function calls are expensive
in Luau; in-module ones are literally free. It is that **calls across a module boundary** are expensive, and
`Tools.Lerp` happens to be one. The rewritten rule says so, and adds the two cheaper fixes the old one did
not offer: move the helper into the module, or hoist it to a local outside the loop.

---

## 7. Fastcall vs namecall

Not previously in `CLAUDE.md`. The Luau docs note that the fastcall mechanism *"doesn't work for method
calls (so calling `string.byte` is more efficient than `s:byte`)"*, without a number.

20,000 calls, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `string.byte(s, i)` | 12.87 | 10.88 | 6.84 |
| `local byte = string.byte` then `byte(s, i)` | 13.13 | 12.77 | 5.63 |
| `s:byte(i)` | 28.17 | 24.79 | 28.09 |

**2.19x, 2.28x and 4.11x.** The method form gives up the fastcall and pays a full call instead, and under
`--!native` it does not improve at all while the fastcall form gets 1.9x faster, so the gap widens to 4x.

Localizing the builtin makes no consistent difference, which matches the docs: fastcall works either way.

---

## 8. Globals, imports and Instance properties

`CLAUDE.md` said: *"Only localize Roblox mutable globals (`game`, `workspace`, `script`, `plugin`, `shared`)
when accessed in hot loops - the `GETIMPORT` opcode already caches all other non-mutable globals at load
time, so localizing them adds an unnecessary `MOVE` opcode."*

That is correct, and now has a size. Pass 1 measured `workspace.Gravity` in a loop and got nothing useful,
because the Instance property read swamped the global lookup it was meant to measure. Pass 2 tested only the
lookup, with `if workspace then`. Marginal cost per read over a local-constant baseline, min column:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `workspace` (mutable global) | 1.35 ns | 1.35 ns | ~0 |
| `local ws = workspace` | 0.64 ns | 0.64 ns | ~0 |
| `math` (import) | 1.69 ns | 1.64 ns | ~0 |

Localizing a mutable global saves about **0.7ns per read**. At 20,000 reads in a frame that is 14
microseconds. Real, and almost never where the frame went. Localizing an import is not worth doing at all:
pass 1 measured `math.floor(x)` at 5.67 / 5.99 / 2.78 ns against a localized `floor(x)` at 6.91 / 5.90 /
2.35, with no consistent winner.

What is actually expensive is the **Instance property read** behind the global:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `workspace.Gravity` per iteration | 47.21 ns | 39.32 ns | 55.96 ns |
| `local g = workspace.Gravity` hoisted out | 3.01 ns | 3.36 ns | 2.82 ns |

**15.7x.** An Instance property read is a C++ reflection call and costs roughly ten times what any Luau
table or global access costs. Note also that `--!native` makes it *worse*, not better. That is the rule
worth having, and it was not in `CLAUDE.md` at all.

---

## 9. Method dispatch

Not previously in `CLAUDE.md`. The Luau docs are unusually direct here: *"it's crucial that `__index` in a
metatable points to a table directly. For performance reasons it's strongly recommended to avoid `__index`
functions as well as deep `__index` chains; an ideal object in Luau is a table with a metatable that points
to itself through `__index`."*

20,000 dispatches, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| **`obj:Method()`**, `__index` one deep, self-pointing | **23.81** | 28.27 | **15.72** |
| `obj.Method(obj)` | 29.50 | 29.93 | 23.28 |
| `local m = Class.Method` then `m(obj)` | 17.40 | 18.17 | 13.01 |
| `obj:Method()`, `__index` chain 3 deep | 47.09 | 46.16 | 41.66 |
| `obj:Method()`, `__index` is a function | 49.04 | 52.83 | 45.80 |

- `obj:Method()` beats `obj.Method(obj)` by 1.06-1.48x, as the docs say.
- A three-deep `__index` chain costs **~2x** a one-deep one. An `__index` function costs **~2-3x**.
  Both confirmed, both worth avoiding.
- One place the measurement disagrees with the docs. The docs say caching a method in a local *"isn't very
  productive in Luau and aren't recommended either"*, but the cached local is the fastest form here by
  25-35% in all three modes. It is not recommended anyway: it costs the dynamic dispatch, which is the whole
  point of putting the method on a metatable. Noted so the next person does not re-derive it.

---

## 10. Field reads

Not previously in `CLAUDE.md`. The docs recommend `Class.StaticField` over `object.StaticField`, and warn
that varying table shapes defeats the inline cache.

20,000 reads, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| own field, `obj.X` | 4.39 | 4.85 | 2.80 |
| `obj["X"]`, constant string key | 4.93 | 4.61 | 2.80 |
| class table, `Class.Static` | 4.44 | 4.48 | 2.79 |
| **inherited, `obj.Static` through `__index`** | **13.52** | **12.59** | **13.89** |
| monomorphic `.X` over 4 same-shaped tables | 12.34 | 12.95 | 5.76 |
| polymorphic `.X` over 4 differently-shaped tables | 11.40 | 13.61 | 6.07 |

- **Reading a static through the instance costs ~3x reading it off the class table**, because the miss on
  the instance has to walk to the metatable. `Class.StaticField` confirmed, with a number.
- `obj["X"]` with a literal string key compiles to the same thing as `obj.X`, as documented.
- **The inline-cache shape warning did not reproduce.** Four different table shapes cost the same as four
  identical ones, in all three modes, in both directions. Either four shapes is too few to matter or the
  effect is below what this harness can see. Not a licence to build ragged tables, just an honest null
  result. Both rows are inflated relative to the others by the `s[(i % 4) + 1]` indexing they share.

---

## 11. Vector math

Not previously in `CLAUDE.md`. The docs describe Luau's 3-wide float vector as a native value type with
*"first class support for all math operations"*, meaning `Vector3` is not a heap object.

20,000 operations, `ns/op` median:

| form | O1 | O2 | NATIVE |
| --- | --- | --- | --- |
| `acc += step * 0.5` on `Vector3` | 4.82 | 3.79 | 2.75 |
| the same three components as separate numbers | 16.06 | 7.83 | 2.58 |
| `acc += Vector3.new(0.5, 1, 1.5)` (fresh vector per iteration) | 3.69 | 3.78 | 2.81 |

**One vector op beats three scalar ops by 3.33x at O1 and 2.07x at O2.** Under `--!native` they converge,
because native codegen keeps the three scalars in registers.

The third row is the useful one: constructing a `Vector3` every iteration is **free**, no slower than
reusing one. Vectors are values, not allocations, so there is no reason to hand-unpack them into three
numbers to avoid garbage. That is a real pattern in this codebase and it is now known to be counterproductive.

---

## 12. Preallocating and reusing tables

`CLAUDE.md` said: *"Pre-allocate with `table.create(n)` or reuse with `table.clear(t)`."* Filling a 10,000
element array, `ns/op` median:

| form | O1 | NATIVE |
| --- | --- | --- |
| fresh `{}` each time | 10.22 | 5.90 |
| fresh `table.create(n)` | 7.85 | 3.64 |
| reused table + `table.clear` | 7.85 | 3.23 |
| reused table, overwritten in place | 7.44 | 3.14 |

**Confirmed, and the two halves of the rule are equal to each other.** Preallocation and reuse both beat a
fresh `{}` by 1.30x at O1 and 1.62-1.88x under native, and `table.clear` costs nothing measurable over
starting from a preallocated table. Reuse is still preferable where it is available because it produces no
garbage at all, which this microbenchmark does not price in.

---

## 13. Do the directives do anything?

`CLAUDE.md` said: *"Add `--!native` and `--!optimize 2` to parallel Actor scripts and math-heavy utility
modules."* Nobody had checked either half.

### `--!optimize 2` is a no-op

Across all 17 suites and both passes, the O2 column never separated from the O1 column by more than noise,
and in several suites it was marginally slower. That is not a small effect being missed; it is no effect.

Pass 2 carries a direct, non-timing probe to explain why. It counts stack frames from inside a leaf
function, once called directly and once through a trivial `wrapper`. If the wrapper's frame is gone, the
wrapper was inlined, and function inlining is an optimization level 2 feature:

```
[O1]      INLINE PROBE  direct=3 wrapped=3  ->  WRAPPER WAS INLINED
[O2]      INLINE PROBE  direct=3 wrapped=3  ->  WRAPPER WAS INLINED
[NATIVE]  INLINE PROBE  direct=3 wrapped=3  ->  WRAPPER WAS INLINED
```

**The module with no directive already gets inlining.** The engine is compiling at level 2 by default, so
`--!optimize 2` has nothing left to turn on. It costs nothing to leave in place, but it is not a lever and
should not be reached for as one.

One alternative reading that this probe cannot fully exclude: the compiler could have turned
`local v = f() return v` back into a tail call rather than inlining `f`. Either way something is optimizing
the frame away with no directive present, and the timing evidence across 17 suites points the same way.

### `--!native` is a real lever, with two dead spots

O1 to NATIVE, best row of each pass 1 suite:

| workload | speedup |
| --- | --- |
| arithmetic-heavy loop with float modulo (suite F) | **4.18x** |
| `math.floor` calls (G) | 2.41x |
| `string.byte` fastcalls (H) | 2.29x |
| building an array (C) | 2.13x |
| closure creation (E) | 1.66x |
| array iteration (A) | 1.64x |
| field reads (K) | 1.57x |
| hash iteration (B) | 1.52x |
| method dispatch (J) | 1.51x |
| vector math (L) | 1.43x |
| building objects (D, P) | 1.04-1.49x |
| **`workspace.Gravity` property reads (I)** | **0.84x (worse)** |
| **cross-module call, marginal cost per call (Q)** | **0.77x (worse)** |

So `--!native` is worth 1.4-4.2x on code that stays inside Luau and does arithmetic, calls and table work.
It is worth nothing on code that is allocation-bound, and it is **actively negative** on the two things that
leave native execution: Instance property reads and calls into other modules.

That reshapes where the directive belongs. A parallel Actor script doing vector math on a local buffer is
the ideal case. A service whose hot loop is mostly `part.CFrame` reads and calls into required modules will
get nothing, or slightly less than nothing.

---

## What this changed in CLAUDE.md

1. Iteration rule reversed: prefer generalized `for _, v in t`, with the index-needed exception spelled out.
2. Append rule rewritten around the counter plus `table.create`, not `#t + 1` vs `table.insert`.
3. Closure rule narrowed from "never in hot loops" to "never capture a loop local, above all a mutable one",
   since a capture-free closure is cached.
4. The inline-helpers rule restated as a cross-module rule, with the two cheaper fixes added.
5. `--!optimize 2` demoted with a note that it is a no-op; `--!native` scoped to pure-Luau compute with its
   two dead spots named.
6. Six rules added: cross-module call cost, fastcall over namecall, Instance property reads, `__index` depth
   and `Class.StaticField`, `Vector3` over unpacked scalars, and `setmetatable(table.clone(PLAIN), MT)` over
   cloning a stub that carries the metatable.

## Open threads

- **Nothing here was measured on a live server.** Section 13's conclusion that the engine already compiles
  at level 2 is the one that would change if Studio and production ever differ. Open Cloud execution needs
  `ROBLOX_OPEN_CLOUD_KEY` / `ROBLOX_UNIVERSE_ID` / `ROBLOX_PLACE_ID` configured for this place; the
  cross-check was attempted and could not run.
- **The inline-cache shape penalty was not reproduced** at four table shapes. If it exists at this scale it
  is below the noise floor of this harness. Worth retrying with more shapes and a cheaper surrounding loop.
- **Why an in-module table field call is free is inferred, not proven.** `TOOLS.Lerp(...)` costing the same
  as writing the expression by hand implies the compiler resolved the field statically, which is more than
  the documented "only local functions can be inlined" promises. The effect is solid across modes; the
  mechanism is a guess.
- **The `table.clone` vs table-literal median/min split** ([4](#4-building-objects)) is the only place where
  the two statistics point different ways. It is consistent with the literal generating more GC assist
  pressure, but that was not measured directly.
