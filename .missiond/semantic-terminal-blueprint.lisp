;; semantic-terminal · Project Blueprint (M6 SSOT)
;;
;; This is the project-level *blueprint.lisp shard MissionD's
;; check-project-maturity.mjs requires for M3+. It is companion to:
;;   .missiond/intent.lisp           — declarative intent (pillar/function tree)
;;   .missiond/intent-manifest.lisp  — shard index, evidence map, checker plan
;;   .missiond/check.sh              — gate runner mirroring the manifest
;;   .missiond/evidence/             — read-only convergence narratives
;;
;; M6 contract (per missiond/scripts/check-project-maturity.mjs):
;;   - has_project_blueprint  : this file exists and ends with "blueprint.lisp"
;;   - has_lisp_shape         : :entry + :core + :egress + :surfaces present
;;   - has_ordered_steps      : (step sN ...) tokens
;;   - has_code_isomorphism   : :code-isomorphism current-code-mapping declared
;;   - has_runtime-projection : :runtime-projection slots populated
;;
;; SSOT scope: this blueprint MUST NOT mutate crates/**, packages/**,
;; Cargo.toml, Cargo.lock, package.json, or any prebuilt .node artifact.
;; Implementation surface stays under crates/ and packages/; this file
;; only declares how the working tree maps onto the pillar/function tree.

(project-blueprint semantic-terminal
  :schema           "missiond.project-blueprint.v1"
  :ssot-version     "M6.0"
  :maturity         M6
  :target           M10
  :code-isomorphism current-code-mapping
  :role             "PTY output → semantic events parser (Rust core + N-API)"
  :surface          (rust-crate node-addon npm-package)
  :runtime-edges    (claude-code gemini-cli codex)
  :registry-status  project-ssot-owned
  :intent-file      ".missiond/intent.lisp"
  :manifest-file    ".missiond/intent-manifest.lisp"
  :checker-file     ".missiond/check.sh"
  :evidence-dir     ".missiond/evidence/"

;; ─────────────────────────────────────────────────────────────────────
;; Code-isomorphism declaration
;; Each pillar/function below names a single live code anchor with a
;; closed line range. The blueprint is M6-honest: every :entry resolves
;; to a real symbol in the working tree, and every :core step is a
;; verb that a reader can locate inside the same file by inspection.
;; ─────────────────────────────────────────────────────────────────────

  (current-code-mapping
    :workspace-root   "Cargo.toml"
    :workspace-members ("crates/semantic-terminal" "crates/semantic-terminal-napi")
    :rust-edition     "2021"
    :rust-version     "0.1.0"
    :license          "MIT"
    :npm-loader       "packages/semantic-terminal/index.js"
    :npm-types        "packages/semantic-terminal/index.d.ts"
    :npm-triples      (aarch64-apple-darwin
                       x86_64-apple-darwin
                       x86_64-unknown-linux-gnu
                       x86_64-unknown-linux-musl
                       x86_64-pc-windows-msvc)
    :test-corpus-size 110
    :pillar-count     10
    :function-count   15)

;; ───────────────────────── Pillar 1 · State Detection ─────────────────────────
  (pillar state-detection
    :loc-rust 1279
    :owns     (state.rs gemini_state.rs)
    :depends  (provider-patterns fingerprint-registry)

    (function detect-claude-code-state
      :entry    "crates/semantic-terminal/src/state.rs::ClaudeCodeStateParser::parse"
      :anchor   "crates/semantic-terminal/src/state.rs:38..386"
      :core ((step s1 strip-ansi-and-normalize)
             (step s2 scan-tail-lines-for-spinner-or-prompt)
             (step s3 classify-phase :phases (idle thinking tool-running confirming error completed))
             (step s4 attach-state-meta :fields (cli-engine spinner-char tool-name elapsed-secs))
             (step s5 emit-StateDetectionResult))
      :egress   (StateDetectionResult State StateMeta PhaseHint)
      :surfaces (rust-trait::ClaudeCodeStateParser
                 napi-class::StateParser
                 napi-fn::detect_state)
      :runtime-projection
                ((engine claude-code)
                 (input  "Vec<String> tail lines (PTY scrollback)")
                 (output "Option<StateResult { state, hint, confidence, meta }>")))

    (function detect-gemini-state
      :entry    "crates/semantic-terminal/src/gemini_state.rs::GeminiCliStateParser::parse"
      :anchor   "crates/semantic-terminal/src/gemini_state.rs:1..277"
      :core ((step s1 strip-ansi-and-normalize)
             (step s2 match-gemini-prompt-and-spinner-set)
             (step s3 classify-phase :phases (idle thinking confirming error))
             (step s4 emit-StateDetectionResult :cli-engine Gemini))
      :egress   (StateDetectionResult)
      :surfaces (rust-trait::GeminiCliStateParser)
      :runtime-projection
                ((engine gemini)
                 (variant "distinct spinner & prompt glyph set vs claude-code"))))

;; ───────────────────────── Pillar 2 · Confirmation Parsing ─────────────────────
  (pillar confirmation-parsing
    :loc-rust 512
    :owns     (confirm.rs)
    :depends  (provider-patterns)

    (function parse-confirm-dialog
      :entry    "crates/semantic-terminal/src/confirm.rs::ClaudeCodeConfirmParser::parse"
      :anchor   "crates/semantic-terminal/src/confirm.rs:1..512"
      :core ((step s1 detect-confirm-frame :markers (box-drawing question-glyph option-numbering))
             (step s2 extract-prompt-text)
             (step s3 enumerate-options :keys (digit y n esc tab))
             (step s4 classify-confirm-type :types (tool-permission edit-permission yes-no continue))
             (step s5 attach-tool-context :when tool-permission :fields (tool-name tool-input))
             (step s6 emit-ConfirmResponse))
      :egress   (ConfirmResponse ConfirmInfo ConfirmType ConfirmOption ConfirmKey ConfirmAction ToolInfo)
      :surfaces (rust-trait::ClaudeCodeConfirmParser
                 napi-class::ConfirmParser)
      :runtime-projection
                ((trigger "PTY frame containing ? or ❯ + numbered options")
                 (output  "Option<ConfirmInfo { kind, prompt, options[], tool? }>"))))

;; ───────────────────────── Pillar 3 · Status Bar Parsing ──────────────────────
  (pillar status-bar-parsing
    :loc-rust 683
    :owns     (status.rs title.rs)
    :depends  (provider-patterns)

    (function parse-status-line
      :entry    "crates/semantic-terminal/src/status.rs::ClaudeCodeStatusParser::parse"
      :anchor   "crates/semantic-terminal/src/status.rs:1..406"
      :core ((step s1 locate-status-line :hints (spinner-prefix elapsed-suffix))
             (step s2 strip-ansi)
             (step s3 extract-fields :fields (spinner phase-verb elapsed-secs token-count interrupt-hint))
             (step s4 classify-phase :phases StatusPhase)
             (step s5 emit-ClaudeCodeStatus))
      :egress   (ClaudeCodeStatus StatusPhase)
      :surfaces (rust-trait::ClaudeCodeStatusParser
                 napi-class::StatusParser
                 constants::SPINNER_CHARS)
      :runtime-projection
                ((sample "* Thinking… (12s · 1.2k tokens · esc to interrupt)")))

    (function parse-terminal-title
      :entry    "crates/semantic-terminal/src/title.rs::ClaudeCodeTitleParser::parse"
      :anchor   "crates/semantic-terminal/src/title.rs:1..277"
      :core ((step s1 read-osc-title-bytes)
             (step s2 detect-spinner-glyph :sets (BRAILLE_SPINNERS OTHER_SPINNERS))
             (step s3 extract-cwd-and-task-text)
             (step s4 emit-TitleParseResult))
      :egress   (TitleParseResult ClaudeCodeTitle)
      :surfaces (rust-trait::ClaudeCodeTitleParser
                 napi-class::TitleParser
                 constants::ALL_SPINNERS)
      :runtime-projection
                ((osc-format "ESC ] 0 ; <title> BEL"))))

;; ───────────────────────── Pillar 4 · Tool Output Parsing ─────────────────────
  (pillar tool-output-parsing
    :loc-rust 558
    :owns     (tool.rs)
    :depends  (provider-patterns fingerprint-registry)

    (function parse-tool-output
      :entry    "crates/semantic-terminal/src/tool.rs::ClaudeCodeToolOutputParser::parse"
      :anchor   "crates/semantic-terminal/src/tool.rs:1..558"
      :core ((step s1 locate-tool-block :markers (tool-call-header bullet-arrow))
             (step s2 identify-tool-name :allow KNOWN_TOOLS)
             (step s3 extract-tool-args)
             (step s4 capture-tool-result-body :until (next-tool-or-prompt))
             (step s5 classify-tool-status :statuses ToolStatus)
             (step s6 emit-ToolOutputResult))
      :egress   (ToolOutputResult ClaudeCodeToolOutput ToolStatus)
      :surfaces (rust-trait::ClaudeCodeToolOutputParser
                 napi-class::ToolOutputParser
                 constants::KNOWN_TOOLS)
      :runtime-projection
                ((tools-covered (Bash Read Write Edit Grep Glob Task WebFetch WebSearch TodoWrite)))))

;; ───────────────────────── Pillar 5 · Fingerprint Registry ────────────────────
  (pillar fingerprint-registry
    :loc-rust 667
    :owns     (fingerprint.rs)
    :depends  (provider-patterns)

    (function build-fingerprint-registry
      :entry    "crates/semantic-terminal/src/fingerprint.rs::FingerprintRegistry::new"
      :anchor   "crates/semantic-terminal/src/fingerprint.rs:129..310"
      :core ((step s1 collect-fingerprints :sources (claude_code_fingerprints provider-yaml))
             (step s2 index-by-category :categories FingerprintCategory)
             (step s3 expose-lookup-api :methods (get_by_category get_by_id all)))
      :egress   (FingerprintRegistry Fingerprint FingerprintCategory FingerprintType FingerprintPattern)
      :surfaces (rust-fn::default_registry
                 rust-fn::registry_from
                 rust-fn::claude_code_fingerprints
                 rust-fn::claude_code_fingerprints_from
                 napi-class::Registry)
      :runtime-projection
                ((default-source "static claude_code_fingerprints table")
                 (extension-source "PatternConfig YAML providers")))

    (function detect-fingerprints
      :entry    "crates/semantic-terminal/src/fingerprint.rs::FingerprintRegistry::detect"
      :anchor   "crates/semantic-terminal/src/fingerprint.rs:185..230"
      :core ((step s1 iterate-fingerprints :short-circuit-on-required false)
             (step s2 match-pattern :kinds (Enum Regex Substring))
             (step s3 group-matches-by-category)
             (step s4 derive-hints :flags (has-spinner has-prompt has-tool-output has-confirm-dialog has-error))
             (step s5 emit-FingerprintResult))
      :egress   (FingerprintResult FingerprintMatch FingerprintHints)
      :surfaces (napi-fn::detect_fingerprints)
      :runtime-projection
                ((side-effect "stateless; pure function over ParserContext"))))

;; ───────────────────────── Pillar 6 · Provider Patterns ───────────────────────
  (pillar provider-patterns
    :loc-rust 801
    :owns     (patterns.rs)
    :depends  ()

    (function compile-default-patterns
      :entry    "crates/semantic-terminal/src/patterns.rs::default_compiled"
      :anchor   "crates/semantic-terminal/src/patterns.rs:520..600"
      :core ((step s1 load-builtin-pattern-table :per-engine (ClaudeCode Gemini Codex))
             (step s2 compile-regex-and-enum-sets)
             (step s3 cache-as-CompiledPatterns))
      :egress   (CompiledPatterns)
      :surfaces (rust-fn::default_compiled)
      :runtime-projection
                ((cache "Arc<CompiledPatterns> per CliEngine")))

    (function load-and-hot-reload-patterns
      :entry    "crates/semantic-terminal/src/patterns.rs::PatternConfig::load_default"
      :anchor   "crates/semantic-terminal/src/patterns.rs:355..511"
      :core ((step s1 resolve-yaml-search-paths)
             (step s2 parse-yaml-into-PatternConfig)
             (step s3 stat-watch-for-mtime-change)
             (step s4 swap-CompiledPatterns-atomically))
      :egress   (PatternConfig)
      :surfaces (rust-fn::global_patterns
                 rust-fn::maybe_reload_global_patterns
                 rust-static::GLOBAL_PATTERNS)
      :runtime-projection
                ((reload-trigger "fs mtime change on patterns.yaml")
                 (atomicity     "Arc<RwLock<PatternConfig>>"))))

;; ───────────────────────── Pillar 7 · N-API Binding ───────────────────────────
  (pillar napi-binding
    :loc-rust 572
    :owns     (crates/semantic-terminal-napi/src/lib.rs)
    :depends  (state-detection confirmation-parsing status-bar-parsing
               tool-output-parsing fingerprint-registry)

    (function expose-rust-parsers-to-node
      :entry    "crates/semantic-terminal-napi/src/lib.rs"
      :anchor   "crates/semantic-terminal-napi/src/lib.rs:128..529"
      :core ((step s1 wrap-rust-types-as-napi-structs
                 :structs (StateResult ConfirmInfo ConfirmOption ToolInfo
                           StatusInfo TitleInfo ToolOutput
                           FingerprintMatch FingerprintHints FingerprintResult))
             (step s2 expose-parser-classes
                 :classes (StateParser ConfirmParser StatusParser TitleParser
                           ToolOutputParser Registry))
             (step s3 expose-stateless-fns
                 :fns (detect_state detect_fingerprints))
             (step s4 build-cdylib :crate-type cdylib :features (napi4 serde-json)))
      :egress   ("semantic_terminal_napi.{darwin,linux,win32}.node")
      :surfaces (napi-rs-2 cdylib)
      :runtime-projection
                ((build-cmd "napi build --cargo-cwd crates/semantic-terminal-napi")
                 (loader    "packages/semantic-terminal/index.js auto-resolves platform package"))))

;; ───────────────────────── Pillar 8 · NPM Packaging ───────────────────────────
  (pillar npm-packaging
    :loc-js   80
    :owns     (packages/semantic-terminal/ packages/semantic-terminal-*/)
    :depends  (napi-binding)

    (function publish-platform-bundle
      :entry    "packages/semantic-terminal/package.json"
      :anchor   "packages/semantic-terminal/{index.js,index.mjs,index.d.ts,package.json}"
      :core ((step s1 declare-main-package
                 :name    "@anthropic/semantic-terminal"
                 :exports (index.js index.mjs index.d.ts))
             (step s2 declare-platform-subpackages
                 :triples (aarch64-apple-darwin x86_64-apple-darwin
                           x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
                           x86_64-pc-windows-msvc)
                 :as-optional optionalDependencies)
             (step s3 platform-loader-resolves-at-runtime
                 :file     "index.js"
                 :strategy "match process.{platform,arch} → require subpkg")
             (step s4 prebuilt-node-files
                 :location "packages/semantic-terminal-<triple>/<name>.node"))
      :egress   ("@anthropic/semantic-terminal@x" "@anthropic/semantic-terminal-<triple>@x")
      :surfaces (npm-registry)
      :runtime-projection
                ((install-flow "npm i @anthropic/semantic-terminal → npm picks one optional subpkg matching host")
                 (prebuilt-checked-in "packages/semantic-terminal-darwin-arm64 only; other triples published via CI"))))

;; ───────────────────────── Pillar 9 · Test Fixtures ───────────────────────────
  (pillar test-fixtures
    :tests-rust 110
    :owns     ("inline #[cfg(test)] modules in each crates/semantic-terminal/src/*.rs"
               "packages/semantic-terminal/test.js")
    :depends  (state-detection confirmation-parsing status-bar-parsing
               tool-output-parsing fingerprint-registry provider-patterns)

    (function rust-unit-tests
      :entry    "cargo test -p semantic-terminal"
      :anchor   "crates/semantic-terminal/src/*.rs#[cfg(test)]"
      :core ((step s1 enumerate-inline-test-modules
                 :per-module ((state.rs        30)
                              (status.rs       18)
                              (tool.rs         16)
                              (confirm.rs      11)
                              (title.rs        10)
                              (patterns.rs      9)
                              (fingerprint.rs   8)
                              (gemini_state.rs  8))
                 :total 110)
             (step s2 cover-real-pty-snippets :format "raw string literals")
             (step s3 assert-state-confirm-status-tool-and-fingerprint-shape))
      :egress   ("110 unit tests all-pass invariant")
      :surfaces (cargo-test)
      :runtime-projection
                ((command "cargo test -p semantic-terminal")
                 (oracle  "test counts == manifest shard-index claims")))

    (function node-smoke-test
      :entry    "node packages/semantic-terminal/test.js"
      :anchor   "packages/semantic-terminal/test.js"
      :core ((step s1 require-built-addon)
             (step s2 invoke-detect_state-on-fixture-lines)
             (step s3 assert-result-shape))
      :egress   ("node test exit 0")
      :surfaces (node-runtime)
      :runtime-projection
                ((command "node packages/semantic-terminal/test.js"))))

;; ───────────────────────── Pillar 10 · Source Hygiene ─────────────────────────
  (pillar source-hygiene
    :loc-meta-only t
    :owns     (".missiond/intent.lisp"
               ".missiond/intent-manifest.lisp"
               ".missiond/semantic-terminal-blueprint.lisp"
               ".missiond/check.sh"
               ".missiond/evidence/")
    :depends  ()

    (function ssot-write-discipline
      :entry    "any Claude Code task editing this project"
      :anchor   ".missiond/check.sh::gate_forbid_source_mutation"
      :core ((step s1 forbid-formatter-runs
                 :forbidden (cargo-fmt rustfmt))
             (step s2 forbid-package-mutation
                 :forbidden (npm-build napi-build napi-prepublish
                             package-json-edits package-lock-edits))
             (step s3 forbid-prebuilt-artifact-touch
                 :forbidden ("packages/**/*.node"))
             (step s4 allow-only-ssot-writes
                 :allowed (".missiond/intent.lisp"
                           ".missiond/intent-manifest.lisp"
                           ".missiond/semantic-terminal-blueprint.lisp"
                           ".missiond/check.sh"
                           ".missiond/evidence/**"))
             (step s5 verify-clean-diff
                 :command "git diff --check -- .missiond/"))
      :egress   ("clean .missiond-only commit")
      :surfaces (git-discipline)
      :runtime-projection
                ((rule "no cargo fmt / no rustfmt / no npm build / no .node touch")
                 (gate-runner ".missiond/check.sh"))))

;; ─────────────────────────────────────────────────────────────────────
;; Maturity declaration
;; This blueprint stamps M6 honestly. M7+ deltas (runtime-projection
;; for an event bus, worker-operational receipt, final-convergence) are
;; declared as gaps; their evidence still lives under
;; .missiond/evidence/ for forward reference but is not claimed here.
;; ─────────────────────────────────────────────────────────────────────

  (maturity-declaration
    :current   M6
    :target    M10
    :gap       (event-bus worker-operational final-convergence)
    :rationale "M6 floor: project-level blueprint + code-isomorphism +
                ordered steps + runtime-projection for in-process parsers.
                M7+ event-bus / worker-operational / final-convergence
                evidence is documented under .missiond/evidence/ but the
                central V3 :current literal stays at M2 until reducer-side
                bump.")

  (evidence-pointers
    :m6-narrative   ".missiond/evidence/m6-convergence-report.md"
    :m10-narrative  ".missiond/evidence/m10-final-convergence-report.lisp"
    :note "M10 evidence shard is retained read-only as forward-looking
           material; this blueprint only claims M6 against the central
           V3 registry, which still records semantic-terminal as M2.")

  (closure
    :write-scope-allowlist (".missiond/intent.lisp"
                            ".missiond/intent-manifest.lisp"
                            ".missiond/semantic-terminal-blueprint.lisp"
                            ".missiond/check.sh"
                            ".missiond/evidence/**")
    :write-scope-denylist  ("crates/**" "packages/**" "Cargo.toml" "Cargo.lock"
                            "packages/**/*.node" "**/package-lock.json" "**/package.json")
    :acceptance "node /Users/jinchen/Projects/missiond/scripts/check-project-maturity.mjs --evidence-only --json --min-level M6 --project semantic-terminal"))
