# Road to a publishable mojo-pbt

## What "publishable" means

1. A user installs it with one line, and it compiles on the Mojo they already have.
2. The public API is small, stable and documented. Imports come from `mojo_pbt`.
3. A failure report is complete without stdout: the error holds the shrunk values.
4. The features a user expects from a PBT library exist (see milestone 2).
5. CI proves it on every supported platform. It has a license.

## Decisions (open)

### D1 Toolchain target

Facts (research 2026-11-21, sources in the session report):
- All 17 tests pass unchanged on stable Mojo 1.2.0 and nightly 1.3.0.dev2026112017.
- Precompiled packages (.mojoc/.mojopkg) load only in the exact compiler that
  built them (https://mojolang.org/docs/cli/precompile/). Source is the only
  format that works across versions.
- No library builds stable and nightly from one tree. Each pins one compiler
  range on `main` (decimo: `mojo >=1.2.0,<1.3.0`; EmberJson: nightly
  `>=1.2.0.dev...`) and keeps old compilers on release branches
  (EmberJson `X.Y.Z-release`, lightbug_http `26.1`).

Recommendation: `main` pins stable `mojo >=1.2.0,<1.3.0` (channel `max`).
One extra CI job runs the tests on the newest nightly as an early warning; it
may fail without blocking. Per Mojo release: tag or branch, then bump the range.

### D2 Distribution channel

Facts: `modular-community` (https://github.com/modular/modular-community) is
active: rattler-build recipes, a maintainer labels "OK to test", CI builds
linux-64/osx-arm64/linux-aarch64, publishes to
https://repo.prefix.dev/modular-community. Recipes pin `mojo-compiler` and run
`mojo precompile`. Git source dependencies work with the `pixi-build-mojo`
backend (EmberJson does this).

Decided: git first. Needs a `[package]` table in `pixi.toml` with
`backend = { name = "pixi-build-mojo", version = ">=0.2.6,<0.3" }` and
`preview = ["pixi-build"]`. Later: a modular-community recipe for stable only.

## Decisions (made)

- D3 License: Apache-2.0 with LLVM exception, like the Mojo stdlib. `LICENSE` added.
- D4 Hosting: GitHub `nightscape/mojothesis` (jj remote `origin`; repo not created yet).
  Open: rename the package `mojo_pbt` to `mojothesis`?

## Milestone 1: usable (API and reports)

- [ ] Exports in `mojo_pbt/__init__.mojo`; review public names
      (`map_`, `filter_`, `run_test`, `TestCase.any`).
- [ ] Error message contains the shrunk drawn values and the seed.
- [ ] Explicit examples: fixed choice sequences or values run before random cases.
- [ ] Settings: seed and `max_examples` from env vars, so CI can vary them.
- [ ] Works inside `TestSuite` (one property = one test function), shown in README.
- [ ] README (install, quickstart, stateful example), LICENSE, CHANGELOG.
- [ ] `linux-64` in `pixi.toml` platforms; GitHub Actions: linux + macOS, stable + nightly.

## Milestone 2: useful (strategies)

- [ ] `just`, `sampled_from`, `one_of`, tuples beyond pairs, `flat_map`.
- [ ] `floats` (with shrink to simple values), `strings`, `bytes`.
- [ ] A user-defined composite strategy example (struct with `draw`).

## Milestone 3: release 0.1.0

- [ ] Tag, push, announce source install.
- [ ] Later: recipe for `modular-community`.

## After 0.1 (not needed to publish)

- [ ] Crash isolation supervisor (fork), see docs/ARCHITECTURE.md.
- [ ] Example database (cache of last failure per test).
- [ ] Shrink pass that deletes a step and changes a value together.
- [ ] Same-size Rust/Scala build for the compile-time comparison.
