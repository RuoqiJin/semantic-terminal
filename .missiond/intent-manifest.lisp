;; semantic-terminal · M6 SSOT Manifest
;; Companion index for intent.lisp — shard map, maturity, evidence,
;; checkers, package map, and unresolved gaps. Compact view; under 220 lines.

(manifest semantic-terminal
  :ssot-version "M6.0"
  :intent-file  ".missiond/intent.lisp"

;; ───────── Shard Index ─────────
  (shard-index
    (state-detection        :pillar 1  :loc-rust 1279  :files (state.rs gemini_state.rs))
    (confirmation-parsing   :pillar 2  :loc-rust 512   :files (confirm.rs))
    (status-bar-parsing     :pillar 3  :loc-rust 683   :files (status.rs title.rs))
    (tool-output-parsing    :pillar 4  :loc-rust 558   :files (tool.rs))
    (fingerprint-registry   :pillar 5  :loc-rust 667   :files (fingerprint.rs))
    (provider-patterns      :pillar 6  :loc-rust 801   :files (patterns.rs))
    (napi-binding           :pillar 7  :loc-rust 572   :files (crates/semantic-terminal-napi/src/lib.rs))
    (npm-packaging          :pillar 8  :loc-js   ~80   :files (packages/semantic-terminal/{index.js,index.mjs,index.d.ts,package.json}))
    (test-fixtures          :pillar 9  :tests-rust 110 :files ("inline #[cfg(test)] modules" packages/semantic-terminal/test.js))
    (source-hygiene         :pillar 10 :loc-meta-only  :files (.missiond/intent.lisp .missiond/intent-manifest.lisp)))

;; ───────── Maturity Matrix ─────────
;; Status legend: shipped · stable · evolving · experimental · planned
  (maturity-matrix
    (state-detection        :status shipped     :api-stable yes :coverage high)
    (confirmation-parsing   :status shipped     :api-stable yes :coverage high)
    (status-bar-parsing     :status shipped     :api-stable yes :coverage high)
    (tool-output-parsing    :status shipped     :api-stable yes :coverage high)
    (fingerprint-registry   :status stable      :api-stable yes :coverage medium)
    (provider-patterns      :status evolving    :api-stable yes :coverage medium
                            :note "YAML hot-reload exists; provider table grows with new CLIs")
    (napi-binding           :status shipped     :api-stable yes :coverage smoke-only)
    (npm-packaging          :status shipped     :api-stable yes :coverage manual
                            :note "darwin-arm64 prebuilt present; other triples published via CI")
    (test-fixtures          :status stable      :api-stable n/a :coverage 110-rust-tests)
    (source-hygiene         :status shipped     :api-stable yes :coverage policy-only))

;; ───────── Evidence Map (intent → code anchors) ─────────
  (evidence-map
    ((pillar state-detection function detect-claude-code-state)
     :anchors ("crates/semantic-terminal/src/state.rs:38..266"     ; ClaudeCodeStateParser + Default
              "crates/semantic-terminal/src/state.rs:266..386"     ; impl StateParser
              "crates/semantic-terminal/src/state.rs:386..1002"))  ; #[cfg(test)] (30 tests)
    ((pillar state-detection function detect-gemini-state)
     :anchors ("crates/semantic-terminal/src/gemini_state.rs:1..277"))
    ((pillar confirmation-parsing function parse-confirm-dialog)
     :anchors ("crates/semantic-terminal/src/confirm.rs:1..512"))
    ((pillar status-bar-parsing function parse-status-line)
     :anchors ("crates/semantic-terminal/src/status.rs:1..406"))
    ((pillar status-bar-parsing function parse-terminal-title)
     :anchors ("crates/semantic-terminal/src/title.rs:1..277"))
    ((pillar tool-output-parsing function parse-tool-output)
     :anchors ("crates/semantic-terminal/src/tool.rs:1..558"))
    ((pillar fingerprint-registry function build-fingerprint-registry)
     :anchors ("crates/semantic-terminal/src/fingerprint.rs:129..310"))
    ((pillar fingerprint-registry function detect-fingerprints)
     :anchors ("crates/semantic-terminal/src/fingerprint.rs:185..230"))
    ((pillar provider-patterns function compile-default-patterns)
     :anchors ("crates/semantic-terminal/src/patterns.rs:520..600"))
    ((pillar provider-patterns function load-and-hot-reload-patterns)
     :anchors ("crates/semantic-terminal/src/patterns.rs:355..511"))
    ((pillar napi-binding function expose-rust-parsers-to-node)
     :anchors ("crates/semantic-terminal-napi/src/lib.rs:128..529"
              "crates/semantic-terminal-napi/Cargo.toml"))
    ((pillar npm-packaging function publish-platform-bundle)
     :anchors ("packages/semantic-terminal/package.json"
              "packages/semantic-terminal/index.js"
              "packages/semantic-terminal-darwin-arm64/package.json"
              "packages/semantic-terminal-darwin-x64/package.json"
              "packages/semantic-terminal-linux-x64-gnu/package.json"
              "packages/semantic-terminal-linux-x64-musl/package.json"
              "packages/semantic-terminal-win32-x64-msvc/package.json"))
    ((pillar test-fixtures function rust-unit-tests)
     :anchors ("crates/semantic-terminal/src/state.rs#[cfg(test)]"
              "crates/semantic-terminal/src/status.rs#[cfg(test)]"
              "crates/semantic-terminal/src/tool.rs#[cfg(test)]"
              "crates/semantic-terminal/src/confirm.rs#[cfg(test)]"
              "crates/semantic-terminal/src/title.rs#[cfg(test)]"
              "crates/semantic-terminal/src/patterns.rs#[cfg(test)]"
              "crates/semantic-terminal/src/fingerprint.rs#[cfg(test)]"
              "crates/semantic-terminal/src/gemini_state.rs#[cfg(test)]"))
    ((pillar test-fixtures function node-smoke-test)
     :anchors ("packages/semantic-terminal/test.js")))

;; ───────── Checker Plan ─────────
  (checker-plan
    (gate ssot-write-scope
      :command "git status --short -- .missiond/"
      :pass-if "only intent.lisp / intent-manifest.lisp under .missiond/"
      :runs-on (pre-commit ci))
    (gate ssot-clean-diff
      :command "git diff --check -- .missiond/intent.lisp .missiond/intent-manifest.lisp"
      :pass-if "exit 0 (no whitespace errors)"
      :runs-on (pre-commit ci))
    (gate forbid-source-mutation
      :command "git diff --name-only HEAD -- crates packages Cargo.toml Cargo.lock"
      :pass-if "empty (no changes outside .missiond)"
      :runs-on (ci))
    (gate forbid-prebuilt-touch
      :command "git diff --name-only HEAD -- 'packages/**/*.node'"
      :pass-if "empty"
      :runs-on (ci))
    (gate rust-tests
      :command "cargo test -p semantic-terminal"
      :pass-if "110 passed; 0 failed"
      :runs-on (ci local))
    (gate node-smoke
      :command "node packages/semantic-terminal/test.js"
      :pass-if "exit 0"
      :runs-on (release-candidate)))

;; ───────── Package Map ─────────
  (package-map
    (rust-workspace
      :root        "Cargo.toml"
      :members     ("crates/semantic-terminal" "crates/semantic-terminal-napi")
      :version     "0.1.0"
      :edition     "2021"
      :license     "MIT"
      :keywords    (claude terminal parser semantic cli))
    (rust-crate-core
      :name        "semantic-terminal"
      :path        "crates/semantic-terminal"
      :public-api  (ClaudeCodeStateParser ClaudeCodeConfirmParser
                    ClaudeCodeStatusParser ClaudeCodeTitleParser
                    ClaudeCodeToolOutputParser GeminiCliStateParser
                    FingerprintRegistry PatternConfig CompiledPatterns
                    "types::*"))
    (rust-crate-napi
      :name        "semantic-terminal-napi"
      :path        "crates/semantic-terminal-napi"
      :crate-type  cdylib
      :napi-features (napi4 serde-json))
    (npm-main
      :name        "@anthropic/semantic-terminal"
      :path        "packages/semantic-terminal"
      :loader      "index.js"
      :types       "index.d.ts"
      :triples     (aarch64-apple-darwin x86_64-apple-darwin
                    x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
                    x86_64-pc-windows-msvc))
    (npm-platform-subpackages
      :pattern     "@anthropic/semantic-terminal-<triple>"
      :payload     "<name>.node"
      :paths       ("packages/semantic-terminal-darwin-arm64"
                    "packages/semantic-terminal-darwin-x64"
                    "packages/semantic-terminal-linux-x64-gnu"
                    "packages/semantic-terminal-linux-x64-musl"
                    "packages/semantic-terminal-win32-x64-msvc")))

;; ───────── Next Gaps (deferred work, not part of this commit) ─────────
  (next-gaps
    (gap codex-state-parser
      :pillar state-detection
      :note   "CliEngine::Codex declared in types.rs but no dedicated parser yet; today routed through Claude Code paths.")
    (gap fingerprint-yaml-loader
      :pillar fingerprint-registry
      :note   "Provider YAML can extend fingerprints via patterns; explicit YAML→FingerprintRegistry path not yet first-class.")
    (gap napi-typed-tests
      :pillar test-fixtures
      :note   "Node smoke test (test.js) is single-fixture; lacks parity matrix vs Rust unit tests.")
    (gap ci-publish-matrix
      :pillar npm-packaging
      :note   "Only darwin-arm64 prebuilt currently checked in under packages/; full triple matrix relies on CI release.")
    (gap pattern-yaml-doc
      :pillar provider-patterns
      :note   "Hot-reload pipeline exists but YAML schema has no in-repo human-readable spec.")
    (gap status-confirm-fixture-suite
      :pillar test-fixtures
      :note   "PTY snippets are inline raw strings; no shared fixtures/ directory for cross-engine regressions."))

;; ───────── SSOT Closure ─────────
  (closure
    :write-scope-allowlist (".missiond/intent.lisp" ".missiond/intent-manifest.lisp")
    :write-scope-denylist  ("crates/**" "packages/**" "Cargo.toml" "Cargo.lock"
                            "packages/**/*.node" "**/package-lock.json" "**/package.json")
    :commit-message        "feat(semantic-terminal): add M6 SSOT"))
