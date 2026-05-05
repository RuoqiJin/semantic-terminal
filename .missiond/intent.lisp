;; semantic-terminal · M10 SSOT (compact intent)
;;
;; Mission: Multi-CLI semantic terminal output parser. Consumes raw PTY
;; lines from Claude Code / Gemini CLI / Codex-style agents and emits
;; structured signals (state, confirmation, status bar, tool output,
;; title, fingerprints). Rust workspace (`crates/semantic-terminal` core
;; + `crates/semantic-terminal-napi` Node bindings) shipped as platform
;; .node prebuilts under `packages/semantic-terminal-*`.
;;
;; SSOT scope: declarative intent + manifest + M10 evidence shard.
;; Implementation lives under crates/** and packages/**; this file
;; MUST NOT mutate them.
;;
;; M10 final-convergence is documented in
;;   .missiond/evidence/m10-final-convergence-report.lisp
;; which closes the four loops the V3 registry tracks for this project:
;;   event-bus loop          — pty-event-stream + pattern-yaml-event-ingest
;;   commit-backfill loop    — 110 inline PTY-snippet replay corpus
;;   worker-operational      — swarm worker write-scope receipt
;;   final-convergence gate  — v3-runtime-ssot binding signature

(project semantic-terminal
  :role           "PTY output → semantic events parser (Rust core + N-API)"
  :surface        (rust-crate node-addon npm-package)
  :runtime-edges  (claude-code gemini-cli codex)
  :ssot-version   "M10.0"
  :maturity       M10

;; ───────────────────────── Pillar 1 · State Detection ─────────────────────────
  (pillar state-detection
    :owns         (state.rs gemini_state.rs)
    :depends      (patterns fingerprint-registry)

    (function detect-claude-code-state
      :entry      "ClaudeCodeStateParser::parse(ParserContext)"
      :core ((step s1 strip-ansi-and-normalize)
             (step s2 scan-tail-lines-for-spinner-or-prompt)
             (step s3 classify-phase :phases (idle thinking tool-running confirming error completed))
             (step s4 attach-state-meta :fields (cli-engine spinner-char tool-name elapsed-secs))
             (step s5 emit StateDetectionResult))
      :egress     (StateDetectionResult State StateMeta PhaseHint)
      :surfaces   (rust-trait ClaudeCodeStateParser
                   napi-class StateParser
                   napi-fn detect_state)
      :runtime-projection
                  ((engine claude-code)
                   (input  "Vec<String> tail lines (PTY scrollback)")
                   (output "Option<StateResult { state, hint, confidence, meta }>")))

    (function detect-gemini-state
      :entry      "GeminiCliStateParser::parse(ParserContext)"
      :core ((step s1 strip-ansi-and-normalize)
             (step s2 match-gemini-prompt-and-spinner-set)
             (step s3 classify-phase :phases (idle thinking confirming error))
             (step s4 emit StateDetectionResult :cli-engine Gemini))
      :egress     (StateDetectionResult)
      :surfaces   (rust-trait GeminiCliStateParser)
      :runtime-projection
                  ((engine gemini)
                   (variant "distinct spinner & prompt glyph set vs claude-code"))))

;; ───────────────────────── Pillar 2 · Confirmation Parsing ─────────────────────
  (pillar confirmation-parsing
    :owns         (confirm.rs)
    :depends      (patterns)

    (function parse-confirm-dialog
      :entry      "ClaudeCodeConfirmParser::parse(ParserContext)"
      :core ((step s1 detect-confirm-frame :markers (box-drawing question-glyph option-numbering))
             (step s2 extract-prompt-text)
             (step s3 enumerate-options :keys (digit y n esc tab))
             (step s4 classify-confirm-type :types (tool-permission edit-permission yes-no continue))
             (step s5 attach-tool-context :when tool-permission
                                     :fields (tool-name tool-input))
             (step s6 emit ConfirmResponse))
      :egress     (ConfirmResponse ConfirmInfo ConfirmType ConfirmOption ConfirmKey ConfirmAction ToolInfo)
      :surfaces   (rust-trait ClaudeCodeConfirmParser
                   napi-class ConfirmParser)
      :runtime-projection
                  ((trigger "PTY frame containing ? or ❯ + numbered options")
                   (output  "Option<ConfirmInfo { kind, prompt, options[], tool? }>"))))

;; ───────────────────────── Pillar 3 · Status Bar Parsing ──────────────────────
  (pillar status-bar-parsing
    :owns         (status.rs title.rs)
    :depends      (patterns)

    (function parse-status-line
      :entry      "ClaudeCodeStatusParser::parse(ParserContext)"
      :core ((step s1 locate-status-line :hints (spinner-prefix elapsed-suffix))
             (step s2 strip-ansi)
             (step s3 extract-fields :fields (spinner phase-verb elapsed-secs token-count interrupt-hint))
             (step s4 classify-phase :phases StatusPhase)
             (step s5 emit ClaudeCodeStatus))
      :egress     (ClaudeCodeStatus StatusPhase)
      :surfaces   (rust-trait ClaudeCodeStatusParser
                   napi-class StatusParser
                   constants SPINNER_CHARS)
      :runtime-projection
                  ((sample "* Thinking… (12s · 1.2k tokens · esc to interrupt)")))

    (function parse-terminal-title
      :entry      "ClaudeCodeTitleParser::parse(TitleParserContext)"
      :core ((step s1 read-osc-title-bytes)
             (step s2 detect-spinner-glyph :sets (BRAILLE_SPINNERS OTHER_SPINNERS))
             (step s3 extract-cwd-and-task-text)
             (step s4 emit TitleParseResult))
      :egress     (TitleParseResult ClaudeCodeTitle)
      :surfaces   (rust-trait ClaudeCodeTitleParser
                   napi-class TitleParser
                   constants ALL_SPINNERS)))

;; ───────────────────────── Pillar 4 · Tool Output Parsing ─────────────────────
  (pillar tool-output-parsing
    :owns         (tool.rs)
    :depends      (patterns fingerprint-registry)

    (function parse-tool-output
      :entry      "ClaudeCodeToolOutputParser::parse(ParserContext)"
      :core ((step s1 locate-tool-block :markers (tool-call-header bullet-arrow))
             (step s2 identify-tool-name :allow KNOWN_TOOLS)
             (step s3 extract-tool-args)
             (step s4 capture-tool-result-body :until (next-tool-or-prompt))
             (step s5 classify-tool-status :statuses ToolStatus)
             (step s6 emit ToolOutputResult))
      :egress     (ToolOutputResult ClaudeCodeToolOutput ToolStatus)
      :surfaces   (rust-trait ClaudeCodeToolOutputParser
                   napi-class ToolOutputParser
                   constants KNOWN_TOOLS)
      :runtime-projection
                  ((tools-covered (Bash Read Write Edit Grep Glob Task WebFetch WebSearch TodoWrite)))))

;; ───────────────────────── Pillar 5 · Fingerprint Registry ────────────────────
  (pillar fingerprint-registry
    :owns         (fingerprint.rs)
    :depends      (patterns)

    (function build-fingerprint-registry
      :entry      "FingerprintRegistry::new(fingerprints)"
      :core ((step s1 collect-fingerprints :sources (claude_code_fingerprints provider-yaml))
             (step s2 index-by-category :categories FingerprintCategory)
             (step s3 expose-lookup-api :methods (get_by_category get_by_id all)))
      :egress     (FingerprintRegistry Fingerprint FingerprintCategory FingerprintType FingerprintPattern)
      :surfaces   (rust-fn default_registry registry_from claude_code_fingerprints
                                                         claude_code_fingerprints_from
                   napi-class Registry))

    (function detect-fingerprints
      :entry      "FingerprintRegistry::detect(ParserContext)"
      :core ((step s1 iterate-fingerprints :short-circuit-on-required false)
             (step s2 match-pattern :kinds (Enum Regex Substring))
             (step s3 group-matches-by-category)
             (step s4 derive-hints :flags (has-spinner has-prompt has-tool-output has-confirm-dialog has-error))
             (step s5 emit FingerprintResult))
      :egress     (FingerprintResult FingerprintMatch FingerprintHints)
      :surfaces   (napi-fn detect_fingerprints)))

;; ───────────────────────── Pillar 6 · Provider Patterns ───────────────────────
  (pillar provider-patterns
    :owns         (patterns.rs)
    :depends      ()

    (function compile-default-patterns
      :entry      "patterns::default_compiled(CliEngine)"
      :core ((step s1 load-builtin-pattern-table :per-engine (ClaudeCode Gemini Codex))
             (step s2 compile-regex-and-enum-sets)
             (step s3 cache-as-CompiledPatterns))
      :egress     (CompiledPatterns)
      :surfaces   (rust-fn default_compiled))

    (function load-and-hot-reload-patterns
      :entry      "PatternConfig::load_default / maybe_reload"
      :core ((step s1 resolve-yaml-search-paths)
             (step s2 parse-yaml-into-PatternConfig)
             (step s3 stat-watch-for-mtime-change)
             (step s4 swap-CompiledPatterns-atomically))
      :egress     (PatternConfig)
      :surfaces   (rust-fn global_patterns maybe_reload_global_patterns
                   global   GLOBAL_PATTERNS)
      :runtime-projection
                  ((reload-trigger "fs mtime change on patterns.yaml")
                   (atomicity     "Arc<RwLock<PatternConfig>>"))))

;; ───────────────────────── Pillar 7 · N-API Binding ───────────────────────────
  (pillar napi-binding
    :owns         (crates/semantic-terminal-napi/)
    :depends      (state-detection confirmation-parsing status-bar-parsing
                   tool-output-parsing fingerprint-registry)

    (function expose-rust-parsers-to-node
      :entry      "crates/semantic-terminal-napi/src/lib.rs"
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
      :egress     ("semantic_terminal_napi.{darwin,linux,win32}.node")
      :surfaces   (napi-rs-2 cdylib)
      :runtime-projection
                  ((build-cmd  "napi build --cargo-cwd crates/semantic-terminal-napi")
                   (loader     "packages/semantic-terminal/index.js auto-resolves platform package"))))

;; ───────────────────────── Pillar 8 · NPM Packaging ───────────────────────────
  (pillar npm-packaging
    :owns         (packages/semantic-terminal/ packages/semantic-terminal-*/)
    :depends      (napi-binding)

    (function publish-platform-bundle
      :entry      "packages/semantic-terminal/package.json"
      :core ((step s1 declare-main-package
                 :name        "@anthropic/semantic-terminal"
                 :exports     (index.js index.mjs index.d.ts))
             (step s2 declare-platform-subpackages
                 :triples     (aarch64-apple-darwin x86_64-apple-darwin
                               x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
                               x86_64-pc-windows-msvc)
                 :as-optional optionalDependencies)
             (step s3 platform-loader-resolves-at-runtime
                 :file        "index.js"
                 :strategy    "match process.{platform,arch} → require subpkg")
             (step s4 prebuilt-node-files
                 :location    "packages/semantic-terminal-<triple>/<name>.node"))
      :egress     ("@anthropic/semantic-terminal@x" "@anthropic/semantic-terminal-<triple>@x")
      :surfaces   (npm-registry)
      :runtime-projection
                  ((install-flow "npm i @anthropic/semantic-terminal → npm picks one optional subpkg matching host"))))

;; ───────────────────────── Pillar 9 · Test Fixtures ───────────────────────────
  (pillar test-fixtures
    :owns         ("inline #[cfg(test)] modules in each *.rs"
                   "packages/semantic-terminal/test.js")
    :depends      (state-detection confirmation-parsing status-bar-parsing
                   tool-output-parsing fingerprint-registry provider-patterns)

    (function rust-unit-tests
      :entry      "cargo test -p semantic-terminal"
      :core ((step s1 enumerate-inline-test-modules
                 :per-module ((state.rs       30)
                              (status.rs      18)
                              (tool.rs        16)
                              (confirm.rs     11)
                              (title.rs       10)
                              (patterns.rs     9)
                              (fingerprint.rs  8)
                              (gemini_state.rs 8))
                 :total 110)
             (step s2 cover-real-pty-snippets :format "raw string literals")
             (step s3 assert-state-confirm-status-tool-and-fingerprint-shape))
      :egress     ("110 unit tests all-pass invariant")
      :surfaces   (cargo-test)
      :runtime-projection
                  ((command "cargo test -p semantic-terminal")))

    (function node-smoke-test
      :entry      "node packages/semantic-terminal/test.js"
      :core ((step s1 require-built-addon)
             (step s2 invoke-detect_state-on-fixture-lines)
             (step s3 assert-result-shape))
      :egress     ("node test exit 0")
      :surfaces   (node-runtime)))

;; ───────────────────────── Pillar 10 · Source Hygiene ─────────────────────────
  (pillar source-hygiene
    :owns         (".missiond/intent.lisp"
                   ".missiond/intent-manifest.lisp"
                   ".missiond/check.sh"
                   ".missiond/evidence/")
    :depends      ()

    (function ssot-write-discipline
      :entry      "any Claude Code task editing this project"
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
                           ".missiond/check.sh"
                           ".missiond/evidence/**"))
             (step s5 verify-clean-diff
                 :command "git diff --check -- .missiond/intent.lisp .missiond/intent-manifest.lisp .missiond/evidence/"))
      :egress     ("clean .missiond-only commit")
      :surfaces   (git-discipline)
      :runtime-projection
                  ((rule "no cargo fmt / no rustfmt / no npm build / no .node touch"))))

;; ───────────────────────── Pillar 11 · M10 Final-Convergence ──────────────────
;; Pointer-only pillar. The substantive M10 closure lives in
;; .missiond/evidence/m10-final-convergence-report.lisp; this pillar
;; only declares the contract and the acceptance command so a reader
;; of intent.lisp can find the evidence in one hop.
  (pillar m10-final-convergence
    :owns         (".missiond/evidence/m10-final-convergence-report.lisp")
    :depends      (source-hygiene)

    (function declare-final-convergence-loops
      :entry      "static evidence shard loaded by check-project-maturity.mjs"
      :core ((step s1 declare-event-bus-loop
                 :surfaces (pty-event-stream pattern-yaml-event-ingest))
             (step s2 declare-commit-backfill-loop
                 :corpus "110 inline #[cfg(test)] PTY snippets replayed by cargo test")
             (step s3 declare-worker-operational-receipt
                 :driver mission_swarm_run
                 :context-pack-schema "missiond.swarm-context-pack.v1"
                 :write-scope (".missiond/**"))
             (step s4 declare-final-convergence-binding
                 :v3-runtime-ssot v3-runtime-ssot
                 :verdict :evidence-attached))
      :egress     (m10-final-convergence-report)
      :surfaces   (lisp-evidence-shard)
      :runtime-projection
                  ((evidence-file ".missiond/evidence/m10-final-convergence-report.lisp")
                   (acceptance-cmd "node /Users/jinchen/Projects/missiond/scripts/check-project-maturity.mjs --evidence-only --min-level M10 --project semantic-terminal")
                   (acceptance-pass-criteria "exit 0; evidence_level == M10; diagnostics empty")))))
