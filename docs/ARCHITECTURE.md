# mojothesis architecture

A property-based testing library for Mojo, modelled on minithesis
(https://github.com/DRMacIver/minithesis), the reference core of Hypothesis.

## Goals

1. Automatic shrinking that works for every composition of generators
   (`map`, `flat_map`, `filter`, nested structs) without per-type shrinkers.
2. Generators, invariants and state-machine rules are reusable parts that compose.
3. Failures are kept as explicit values that run before the random cases.
4. Fit Mojo: static generics and traits are strong; stored closures and
   dynamic dispatch are weak; errors are `raises`; `abort` cannot be caught.

## Core idea: the choice sequence

Every random decision a generator makes is a call to `TestCase.choice(n)`,
which returns an integer in `[0, n]` and records it. A test run is fully
determined by its recorded choice sequence (`List[UInt64]`).

The shrinker never sees values. It edits the choice sequence (shorter, then
lexicographically smaller), replays the property with the edited sequence as
prefix, and keeps the edit if the property still fails. Because generators map
choices to values monotonically ("smaller choices give simpler values"), this
shrinks every composition for free.

## Components

| Component | Role |
|---|---|
| `TestCase` | Replays a prefix of choices, then draws random ones; enforces a max length; records status (`OVERRUN`, `INVALID`, `VALID`, `INTERESTING`). |
| `Strategy` trait | `fn draw(self, mut tc: TestCase) raises -> Self.Value`. Combinators are generic structs composed statically (no trait objects). |
| Runner | Generates cases, keeps the best failing choice sequence, runs the shrink passes, replays the result and prints the drawn values. |
| Shrink passes | Delete spans, zero spans, sort spans, binary-search each choice down, redistribute between pairs. |
| Database | Caches the last shrunk choice sequence per test; replayed first. A cache only: it becomes a different case when a generator changes. |
| Explicit examples | Fixed values run through the same property before random cases. The long-term store for found failures. |

A property is `fn(mut tc: TestCase) raises`. It fails when it raises an
`Error` (what `testing.assert_*` does).

`integers(lo, hi)` maps choice 0 to the in-range value nearest 0, then
zigzags outward (+1, -1, +2, ...), so integers shrink toward 0.

### Errors

Checks are unconditional (`assert` is compiled out without `-DASSERT=all`).
User misuse raises; internal impossible states `abort`.

| Error | When |
|---|---|
| `InvalidArgument` | Bad strategy arguments, e.g. `integers(5, 1)`. Strategy constructors therefore `raise`. |
| `Unsatisfiable` | No valid case: every case was rejected or overran. |
| `Flaky` | The minimal failing case does not fail on replay. |
| `Frozen` | The property used the `TestCase` after its run ended, e.g. it caught the internal `StopTest`. |

Tests run with `-DASSERT=all` so stdlib bounds checks are on.

## Stateful testing

Mojo properties cannot capture state and rules cannot be stored closures, so a
state machine is a user struct with static dispatch:

```mojo
trait StateMachine(Deinitable, Movable):
    comptime RULE_COUNT: Int
    def __init__(out self) raises                     # fresh model + system under test
    def rule_name(self, i: Int) -> String
    def precondition(self, i: Int) -> Bool            # rule i applicable now?
    def rule(mut self, i: Int, mut tc: TestCase) raises   # draws its own args via tc.any
    def check_invariants(self) raises
run_state_machine[M: StateMachine, max_steps: Int = 50](seed, max_examples)
```

`max_steps` is a compile-time parameter because the generated property is a
`thin` function and cannot capture runtime values. Steps share the
`continue_coin` encoding with `lists`. The failure error ends with
`steps: <rule names>` so tests can assert the shrunk trace. Invariants are
checked on the initial state and after every executed rule.

`_delete_spans` tries every span size 8..1: a rule step is usually 3 choices
(coin, index, argument). Known local minimum: a fix that needs a step deleted
and a value changed in the same edit (e.g. `add 128, double` vs `add 256`).

The runner builds an ordinary property: draw "another step?" (the `lists`
coin), draw a rule index, skip the step if its precondition is false
(so the case stays valid and the shrinker can zero the index), run the rule,
check invariants. A run is one choice sequence, so the existing shrinker
deletes steps and shrinks rule arguments with no extra code. On replay the
runner prints the step sequence (`rule_name` plus drawn arguments).

## Crash isolation

`abort`, failed asserts and out-of-bounds traps end the process (SIGTRAP), so
the runner cannot observe them in-process. Fork per case works but costs
~2.2 ms on macOS, so the target design is a supervisor (not built yet):

1. The parent forks one child per property. The child runs the normal loop
   in-process and writes each case's choice sequence to a pipe before running it.
2. If the child dies by a signal, the parent holds the crashing sequence and
   shrinks it with one fork per attempt.
3. Raised Errors are still caught and shrunk in-process.

The child resets SIGTRAP/SIGSEGV/SIGBUS/SIGILL/SIGABRT to `SIG_DFL`: the
runtime's symbolizing crash handler costs ~70 ms per crash. The child's
stdout/stderr go to a pipe; the runner shows the crash message for the final
shrunk case only. Plain `debug_assert` does not fire in the default build;
crashes it guards are only found with `-DASSERT=all`.

## Distribution

Source only: precompiled `.mojoc` files load only in the compiler that built
them. `main` pins stable Mojo (`>=1.2.0,<1.3.0`); the `nightly` pixi
environment runs the same tests as a non-blocking CI warning. Users depend on
the git repo; the `pixi-build-mojo` backend precompiles `mojothesis/` on their
machine. A `modular-community` recipe can follow for stable releases.

## Layout

- `mojothesis/core.mojo`: `TestCase`, status, random source.
- `mojothesis/strategies/`: the one home for shared generators.
- `mojothesis/runner.mojo`: generate, shrink, report.
- `tests/`: the library tested with itself.

## Spike results

### Core port (minithesis) — works

- `trait Strategy(Copyable, Deinitable)` with `comptime Value: Drawable`
  (`Drawable = Copyable & Deinitable & Writable`). Combinators are generic
  structs with function parameters: `Map[S, To, f]`, `Filter[S, pred]`,
  `Lists[S]`, `Pair[A, B]`. They nest freely.
- `Strategy` lives in `core.mojo`, not `strategies/`: `TestCase.any` and the
  trait reference each other.
- Properties are `thin` functions and cannot capture state; they build their
  strategies per run.
- No opaque return types: a function returning a composed strategy spells its
  type with `type_of(<expr>)`.
- List slices past the end abort the process (not catchable). Shrink passes
  must stay in bounds.
- Shrinks to the exact minimum on 20 seeds each: `sum > 1000` gives `[1001]`;
  map/filter/pair gives `(52, True)`.

### Compile time (500 LOC, macOS arm64, Mojo 1.3.0.dev2026112017)

| Step | cold s | warm s | incremental s |
|---|---|---|---|
| `mojo precompile mojothesis` | 1.10 | 0.98 | 0.97 |
| `mojo build` test binary | 2.85 | 1.30 | 1.24 |
| `mojo run` test (compile + run) | 1.20 | 1.25 | 1.19 |

Throughput: 175 LoC/s cold, 385 LoC/s warm (`mojo build`).
After the fixes (~600 LoC per test binary, `-DASSERT=all`, no pixi overhead):
114–138 LoC/s cold, 410–442 LoC/s warm. A ~1 s fixed
cost dominates at this size; track LoC vs time as the code grows.

Stable 1.2.0 vs nightly 1.3.0.dev2026112105 (stateful test binary, 844 LoC,
`mojo build -DASSERT=all`, incl. ~0.15 s pixi overhead): stable 7.2 s cold /
1.85 s warm (118 / 460 LoC/s); nightly 5.5 s / 1.55 s (153 / 540 LoC/s).

No incremental compilation: warm and incremental times are equal.
Times include about 0.15 s `pixi run` overhead.

### Fork spike (117 LOC, libc via `external_call`)

| Case | default (`ASSERT=safe`) | `-DASSERT=all` | `-DASSERT=none` |
|---|---|---|---|
| raises Error | exit 1 | exit 1 | exit 1 |
| `abort` | SIGTRAP | SIGTRAP | SIGTRAP |
| List index OOB | SIGTRAP | SIGTRAP | SIGSEGV or silent |
| `debug_assert(False)` | no effect | SIGTRAP | no effect |

Per case: in-process 0.03 µs; fork + pipe + wait 2.0–2.2 ms (C baseline 1.75 ms).
Compile: cold 3.4 s, warm (build cache hit) 1.0–1.1 s.
`-DASSERT=all` must be one argument; `-D ASSERT=all` is ignored silently.
Not tested: fork with live runtime threads, Linux.
