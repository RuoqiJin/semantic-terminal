# semantic-terminal · M6 Convergence Evidence Report

> Part 1 — devtools shard. Companion to `.missiond/intent.lisp`,
> `.missiond/intent-manifest.lisp`, and `.missiond/check.sh`.
> Read-only artifact: this file documents the M6 convergence claim and
> exists outside the implementation tree (`crates/`, `packages/`).

## 1. Why the pillar+function map is M6-equivalent

The semantic-terminal SSOT does not invent a new maturity ladder. It tracks
the same M6 contract used elsewhere in the XiaojinPro fleet: a single
`.missiond/intent.lisp` SSOT plus a manifest, a checker runner that mirrors
the manifest's `(checker-plan ...)`, and an evidence trail that proves each
declared function maps to live code.

Concretely, the three M6 invariants hold here:

- **Single source of truth.** `.missiond/intent.lisp` carries
  `:ssot-version "M6.0"` (line 17) and is the only declarative document of
  intent. Implementation lives strictly under `crates/**` and `packages/**`;
  the SSOT files declare write-scope discipline that forbids mutating
  those trees from SSOT-class tasks (intent.lisp Pillar 10 ·
  `source-hygiene`).
- **Manifest-as-index.** `.missiond/intent-manifest.lisp` is the compact
  companion: shard index, maturity matrix, evidence map, checker plan,
  package map, and known gaps — exactly the M6 manifest layout.
- **Executable gates.** `.missiond/check.sh` materializes the manifest's
  six declared gates (`ssot-write-scope`, `ssot-clean-diff`,
  `forbid-source-mutation`, `forbid-prebuilt-touch`, `rust-tests`,
  `node-smoke`). The runner is read-only by construction — it never
  stages, commits, formats, installs, or mutates files (header comment in
  `check.sh:3-4`).

The pillar+function decomposition is the M6-equivalent shape: ten pillars,
each carrying typed `:owns` / `:depends` edges and one or more
`(function …)` blocks with `:entry`, `:core`, `:egress`, `:surfaces`, and
`:runtime-projection` slots. Every function block names its Rust entry
point literally, so the manifest's `(evidence-map …)` can pin each one
to a file-and-line anchor without ambiguity.

## 2. Intent SSOT version & scope

| Field           | Value                                          |
|-----------------|------------------------------------------------|
| `:ssot-version` | `"M6.0"` (intent.lisp:17)                      |
| `:role`         | `"PTY output → semantic events parser (Rust core + N-API)"` |
| `:surface`      | `(rust-crate node-addon npm-package)`          |
| `:runtime-edges`| `(claude-code gemini-cli codex)`               |

The intent file is 280 lines, compact by M6 convention. Pillar bodies are
self-contained — no cross-pillar inheritance, no implicit conventions
hidden in code.

## 3. Pillar / file / LOC evidence

The manifest's `(shard-index …)` claims are reproducible from the working
tree (verified `wc -l` against `crates/semantic-terminal/src/*.rs` and
`crates/semantic-terminal-napi/src/lib.rs`):

| # | Pillar                 | Files                                  | LOC (manifest)         | LOC (measured)        |
|---|------------------------|----------------------------------------|------------------------|-----------------------|
| 1 | state-detection        | state.rs, gemini_state.rs              | 1279                   | 1002 + 277 = 1279     |
| 2 | confirmation-parsing   | confirm.rs                             | 512                    | 512                   |
| 3 | status-bar-parsing     | status.rs, title.rs                    | 683                    | 406 + 277 = 683       |
| 4 | tool-output-parsing    | tool.rs                                | 558                    | 558                   |
| 5 | fingerprint-registry   | fingerprint.rs                         | 667                    | 667                   |
| 6 | provider-patterns      | patterns.rs                            | 801                    | 801                   |
| 7 | napi-binding           | crates/semantic-terminal-napi/src/lib.rs | 572                  | 572                   |
| 8 | npm-packaging          | packages/semantic-terminal/{index.js, index.mjs, index.d.ts, package.json} | ~80 JS | matches loader bundle |
| 9 | test-fixtures          | inline `#[cfg(test)]` modules + packages/semantic-terminal/test.js | 110 tests | 30+18+16+11+10+9+8+8 = 110 |
| 10| source-hygiene         | .missiond/intent.lisp, .missiond/intent-manifest.lisp | meta-only | n/a                  |

Every Rust LOC number in the manifest matches the on-disk file size to the
line. The 110-test invariant is reproducible by counting `#[test]` and
`#[tokio::test]` markers across the eight test-bearing modules.

## 4. Seven implementation pillars + packaging / test / hygiene

The implementation surface decomposes into **seven pillars that produce
runnable parsers** plus **three meta pillars** that govern how the produced
artifacts are shipped and how the SSOT is preserved:

**Implementation pillars (1–7)**:

1. `state-detection` — `ClaudeCodeStateParser`, `GeminiCliStateParser`
2. `confirmation-parsing` — `ClaudeCodeConfirmParser`
3. `status-bar-parsing` — `ClaudeCodeStatusParser`, `ClaudeCodeTitleParser`
4. `tool-output-parsing` — `ClaudeCodeToolOutputParser`
5. `fingerprint-registry` — `FingerprintRegistry`, `default_registry`
6. `provider-patterns` — `default_compiled`, `PatternConfig`,
   `global_patterns`, `maybe_reload_global_patterns`
7. `napi-binding` — `crates/semantic-terminal-napi/src/lib.rs`
   (`StateParser`, `ConfirmParser`, `StatusParser`, `TitleParser`,
   `ToolOutputParser`, `Registry`, `detect_state`, `detect_fingerprints`)

**Meta pillars (8–10)**:

8. `npm-packaging` — distribution surface (see §5)
9. `test-fixtures` — `cargo test -p semantic-terminal` (110 tests) plus
   `node packages/semantic-terminal/test.js` smoke
10. `source-hygiene` — write-scope discipline for SSOT-class tasks

This 7+3 split keeps the runtime contract (what parsers are exposed)
distinct from the shipping contract (how the parsers reach a Node
consumer) and the discipline contract (what an SSOT task may touch).

## 5. `npm-packaging` is a pillar, not a frontend

semantic-terminal has no UI surface. The `npm-packaging` pillar is not a
"frontend" — it is the **distribution surface for the Rust core** and is
load-bearing in two specific ways:

- **Cross-platform fan-out.** The main package
  `@anthropic/semantic-terminal` declares five platform subpackages as
  `optionalDependencies`
  (`packages/semantic-terminal-{darwin-arm64,darwin-x64,linux-x64-gnu,linux-x64-musl,win32-x64-msvc}`).
  npm picks the matching subpackage at install time. Without this pillar,
  the Rust core has no consumer outside `cargo`.
- **Loader resolution.** `packages/semantic-terminal/index.js` resolves
  the right `<name>.node` artifact at runtime by matching
  `process.platform`/`process.arch`. The loader is the
  `napi-binding` ↔ Node bridge — not a UI layer.

That is why the pillar is owned at
`packages/semantic-terminal/ packages/semantic-terminal-*/` (intent.lisp
Pillar 8 `:owns`) and why the manifest's `(package-map …)` block treats
the npm side as a peer of the Rust workspace, not a downstream consumer.

## 6. Checker depth

The runner enforces six gates. Each gate appears in
`.missiond/intent-manifest.lisp` `(checker-plan …)` and is described by
`gate_describe()` in `check.sh:47-80`:

| Gate                   | Command                                                                  | Pass criterion                                  |
|------------------------|--------------------------------------------------------------------------|-------------------------------------------------|
| ssot-write-scope       | `git ls-files --cached --others --exclude-standard -- .missiond/`        | every basename ∈ `{intent.lisp, intent-manifest.lisp, check.sh}` |
| ssot-clean-diff        | `git diff --check -- .missiond/intent.lisp .missiond/intent-manifest.lisp` | exit 0 (no whitespace errors)                 |
| forbid-source-mutation | `git diff --name-only HEAD -- crates packages Cargo.toml Cargo.lock`     | empty                                           |
| forbid-prebuilt-touch  | `git diff --name-only HEAD -- packages \| grep '\.node$'`                | empty                                           |
| rust-tests             | `cargo test -p semantic-terminal`                                        | 110 passed; 0 failed                            |
| node-smoke             | `node packages/semantic-terminal/test.js`                                | exit 0                                          |

Three depth properties:

- **Static gates first.** The first four gates touch only `git` metadata
  and run in milliseconds, so a misconfigured commit is rejected before
  the runner spawns `cargo` or `node`.
- **Selective skips.** `--skip-rust` and `--skip-node` are first-class
  flags so a pure-SSOT commit (the common case) can verify the four
  static gates without paying for a full `cargo test` run.
- **Dry-run mirrors live run.** `bash .missiond/check.sh --dry-run`
  prints every gate's command and pass criterion verbatim, which makes
  the runner self-documenting and trivially auditable.

## 7. Current-code mapping

Every function block in `intent.lisp` is anchored to a code location in
`(evidence-map …)` of the manifest. Spot-check (taken from
intent-manifest.lisp:38-83):

- `detect-claude-code-state` →
  `crates/semantic-terminal/src/state.rs:38..266` (`ClaudeCodeStateParser`),
  `state.rs:266..386` (`impl StateParser`), `state.rs:386..1002`
  (`#[cfg(test)]`, 30 tests).
- `detect-gemini-state` → `crates/semantic-terminal/src/gemini_state.rs:1..277`.
- `parse-confirm-dialog` → `crates/semantic-terminal/src/confirm.rs:1..512`.
- `parse-status-line` → `crates/semantic-terminal/src/status.rs:1..406`.
- `parse-terminal-title` → `crates/semantic-terminal/src/title.rs:1..277`.
- `parse-tool-output` → `crates/semantic-terminal/src/tool.rs:1..558`.
- `build-fingerprint-registry` → `crates/semantic-terminal/src/fingerprint.rs:129..310`.
- `detect-fingerprints` → `crates/semantic-terminal/src/fingerprint.rs:185..230`.
- `compile-default-patterns` → `crates/semantic-terminal/src/patterns.rs:520..600`.
- `load-and-hot-reload-patterns` → `crates/semantic-terminal/src/patterns.rs:355..511`.
- `expose-rust-parsers-to-node` →
  `crates/semantic-terminal-napi/src/lib.rs:128..529`.
- `publish-platform-bundle` → six anchors across
  `packages/semantic-terminal/` and the five platform subpackage
  `package.json` files.

Every `:entry` string in `intent.lisp` is a literal Rust path (e.g.
`ClaudeCodeStateParser::parse(ParserContext)`,
`FingerprintRegistry::detect(ParserContext)`,
`PatternConfig::load_default / maybe_reload`), so a reader can `grep` the
crate and land on the function in one hop.

## 8. Dirty-baseline preservation

This evidence shard is written under a strict don't-touch contract for
the implementation tree:

- **Write scope.** Only this one file
  (`.missiond/evidence/m6-convergence-report.md`) is written.
- **Read-only inputs.** `crates/**`, `packages/**`, `Cargo.toml`,
  `Cargo.lock`, `packages/**/*.node`, `**/package.json`,
  `**/package-lock.json` are read for verification but never edited or
  staged. The manifest's `closure :write-scope-denylist` lists exactly
  those paths.
- **`.claude/` preserved.** The local `.claude/` directory (only present
  as an untracked entry per `git status`) is left untouched and
  unstaged.
- **Whitespace-clean.** `git diff --check` on this file exits 0; no
  trailing whitespace, no mixed tab/space, no incomplete lines.
- **Single-file commit.** Only `.missiond/evidence/m6-convergence-report.md`
  is staged. Commit message:
  `docs(semantic-terminal): add M6 convergence evidence report`.

The pre-existing M6 SSOT gates remain authoritative. This shard adds an
auditable narrative layer on top of the manifest; it does not relax,
shadow, or redefine any gate.

## 9. Cross-references

- `.missiond/intent.lisp` — declarative SSOT (10 pillars, M6.0).
- `.missiond/intent-manifest.lisp` — shard index, evidence map, checker
  plan, package map, gaps, closure.
- `.missiond/check.sh` — six-gate runner mirroring `(checker-plan …)`.
- Recent history: `5d0808b feat(semantic-terminal): add M6 SSOT`,
  `d8e8e19 feat(semantic-terminal): add M6 SSOT checker runner`.

## 10. Known gaps (deferred, tracked in manifest)

For completeness, the manifest's `(next-gaps …)` block is not changed by
this shard:

- `codex-state-parser` — `CliEngine::Codex` declared in `types.rs` but
  routed through Claude Code paths today.
- `fingerprint-yaml-loader` — explicit YAML → `FingerprintRegistry`
  path is not yet first-class.
- `napi-typed-tests` — Node smoke is single-fixture, lacks a parity
  matrix vs the Rust unit tests.
- `ci-publish-matrix` — only `darwin-arm64` prebuilt is checked in;
  the other four triples rely on CI release.
- `pattern-yaml-doc` — hot-reload pipeline exists but YAML schema has
  no in-repo human-readable spec.
- `status-confirm-fixture-suite` — PTY snippets are inline raw
  strings; no shared `fixtures/` directory.

These are tracked, not in scope for the M6 convergence claim.
