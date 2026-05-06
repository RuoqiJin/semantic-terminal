#!/usr/bin/env bash
# semantic-terminal · M10 SSOT checker runner
# Mirrors (checker-plan ...) in .missiond/intent-manifest.lisp.
# Read-only: never stages, commits, formats, installs, or mutates files.
#
# M10 closure: adds the evidence-only m10-evidence-gate which calls
# missiond's check-project-maturity.mjs to confirm evidence_level == M10
# without depending on the central V3 :current literal advancing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# .missiond/ allowlist for the ssot-write-scope gate.
# SSOT_ALLOWED      — file basenames permitted directly under .missiond/.
# SSOT_ALLOWED_DIRS — subdirectories whose entire contents are permitted
#                     (M6 + M10 evidence trail lives here).
SSOT_ALLOWED=("intent.lisp" "intent-manifest.lisp" "semantic-terminal-blueprint.lisp" "check.sh")
SSOT_ALLOWED_DIRS=("evidence")

# Path to MissionD's evidence-only project-maturity checker. Override
# via env if MissionD lives elsewhere on this host.
MISSIOND_MATURITY_CHECKER="${MISSIOND_MATURITY_CHECKER:-/Users/jinchen/Projects/missiond/scripts/check-project-maturity.mjs}"

GATES=(
  "ssot-write-scope"
  "ssot-clean-diff"
  "forbid-source-mutation"
  "forbid-prebuilt-touch"
  "rust-tests"
  "node-smoke"
  "m10-evidence-gate"
)

usage() {
  cat <<'EOF'
Usage: bash .missiond/check.sh [--dry-run] [--skip-rust] [--skip-node] [--skip-m10] [<gate>]

Runs the seven M10 SSOT gates declared in .missiond/intent-manifest.lisp:
  ssot-write-scope          .missiond/ tree contains only the SSOT allowlist
  ssot-clean-diff           git diff --check on intent.lisp + manifest + evidence
  forbid-source-mutation    no diff vs HEAD under crates / packages / Cargo.{toml,lock}
  forbid-prebuilt-touch     no .node prebuilt touched under packages/
  rust-tests                cargo test -p semantic-terminal
  node-smoke                node packages/semantic-terminal/test.js
  m10-evidence-gate         missiond evidence-only M10 maturity check

Flags:
  --dry-run     list all gates, commands, and pass criteria without running
  --skip-rust   skip the rust-tests gate
  --skip-node   skip the node-smoke gate
  --skip-m10    skip the m10-evidence-gate (e.g. when MissionD repo is absent)
  <gate>        run a single named gate

Env:
  MISSIOND_MATURITY_CHECKER  path override for check-project-maturity.mjs
                             (default: /Users/jinchen/Projects/missiond/scripts/check-project-maturity.mjs)

Exit code is 0 on success, non-zero on hard failure. The runner never
stages, commits, formats, installs, or mutates files.
EOF
}

# Per-gate command/pass-if descriptions used by --dry-run and failure logs.
gate_describe() {
  case "$1" in
    ssot-write-scope)
      echo "command : git ls-files --cached --others --exclude-standard -- .missiond/"
      echo "pass-if : root file is one of {${SSOT_ALLOWED[*]}} or path is under .missiond/{${SSOT_ALLOWED_DIRS[*]}}/"
      ;;
    ssot-clean-diff)
      echo "command : git diff --check -- .missiond/intent.lisp .missiond/intent-manifest.lisp"
      echo "pass-if : exit 0 (no whitespace errors)"
      ;;
    forbid-source-mutation)
      echo "command : git diff --name-only HEAD -- crates packages Cargo.toml Cargo.lock"
      echo "pass-if : empty (no changes outside .missiond)"
      ;;
    forbid-prebuilt-touch)
      echo "command : git diff --name-only HEAD -- packages | grep '\\.node\$'"
      echo "pass-if : empty (no prebuilt .node touched)"
      ;;
    rust-tests)
      echo "command : cargo test -p semantic-terminal"
      echo "pass-if : 110 passed; 0 failed"
      echo "skip    : --skip-rust"
      ;;
    node-smoke)
      echo "command : node packages/semantic-terminal/test.js"
      echo "pass-if : exit 0"
      echo "skip    : --skip-node"
      ;;
    m10-evidence-gate)
      echo "command : node \"\$MISSIOND_MATURITY_CHECKER\" --evidence-only --min-level M10 --project semantic-terminal"
      echo "pass-if : exit 0; evidence_level == M10; diagnostics empty"
      echo "skip    : --skip-m10 (auto-skips with warning when checker file is absent)"
      ;;
    *)
      echo "unknown gate: $1" >&2
      return 2
      ;;
  esac
}

run_gate() {
  local gate="$1"
  case "$gate" in
    ssot-write-scope)         gate_ssot_write_scope ;;
    ssot-clean-diff)          gate_ssot_clean_diff ;;
    forbid-source-mutation)   gate_forbid_source_mutation ;;
    forbid-prebuilt-touch)    gate_forbid_prebuilt_touch ;;
    rust-tests)
      if [[ "$SKIP_RUST" == "1" ]]; then
        echo "  ↳ skipped (--skip-rust)"
        return 0
      fi
      gate_rust_tests
      ;;
    node-smoke)
      if [[ "$SKIP_NODE" == "1" ]]; then
        echo "  ↳ skipped (--skip-node)"
        return 0
      fi
      gate_node_smoke
      ;;
    m10-evidence-gate)
      if [[ "$SKIP_M10" == "1" ]]; then
        echo "  ↳ skipped (--skip-m10)"
        return 0
      fi
      gate_m10_evidence
      ;;
    *)
      echo "unknown gate: $gate" >&2
      return 2
      ;;
  esac
}

is_allowed_basename() {
  local name="$1" allowed
  for allowed in "${SSOT_ALLOWED[@]}"; do
    [[ "$name" == "$allowed" ]] && return 0
  done
  return 1
}

is_allowed_subdir() {
  local name="$1" allowed
  for allowed in "${SSOT_ALLOWED_DIRS[@]}"; do
    [[ "$name" == "$allowed" ]] && return 0
  done
  return 1
}

gate_ssot_write_scope() {
  local listing path rel top unexpected=()
  listing="$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard -- .missiond/)"
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    rel="${path#.missiond/}"
    if [[ "$rel" == */* ]]; then
      top="${rel%%/*}"
      if ! is_allowed_subdir "$top"; then
        unexpected+=("$path")
      fi
    else
      if ! is_allowed_basename "$rel"; then
        unexpected+=("$path")
      fi
    fi
  done <<< "$listing"
  if (( ${#unexpected[@]} > 0 )); then
    printf '  ↳ unexpected path under .missiond/: %s\n' "${unexpected[@]}" >&2
    return 1
  fi
}

gate_ssot_clean_diff() {
  git -C "$PROJECT_ROOT" diff --check -- \
    .missiond/intent.lisp \
    .missiond/intent-manifest.lisp \
    .missiond/evidence/
}

gate_forbid_source_mutation() {
  local changed
  changed="$(git -C "$PROJECT_ROOT" diff --name-only HEAD -- \
    crates packages Cargo.toml Cargo.lock)"
  if [[ -n "$changed" ]]; then
    printf '  ↳ source mutation detected:\n%s\n' "$changed" >&2
    return 1
  fi
}

gate_forbid_prebuilt_touch() {
  local changed
  changed="$(git -C "$PROJECT_ROOT" diff --name-only HEAD -- packages \
    | grep -E '\.node$' || true)"
  if [[ -n "$changed" ]]; then
    printf '  ↳ prebuilt .node mutation detected:\n%s\n' "$changed" >&2
    return 1
  fi
}

gate_rust_tests() {
  ( cd "$PROJECT_ROOT" && cargo test -p semantic-terminal )
}

gate_node_smoke() {
  ( cd "$PROJECT_ROOT" && node packages/semantic-terminal/test.js )
}

gate_m10_evidence() {
  if [[ ! -f "$MISSIOND_MATURITY_CHECKER" ]]; then
    echo "  ↳ MissionD checker not found at $MISSIOND_MATURITY_CHECKER" >&2
    echo "  ↳ set MISSIOND_MATURITY_CHECKER=<path> or pass --skip-m10" >&2
    return 1
  fi
  node "$MISSIOND_MATURITY_CHECKER" \
    --evidence-only \
    --min-level M10 \
    --project semantic-terminal
}

DRY_RUN=0
SKIP_RUST=0
SKIP_NODE=0
SKIP_M10=0
TARGET_GATE=""

while (( $# )); do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-rust)  SKIP_RUST=1 ;;
    --skip-node)  SKIP_NODE=1 ;;
    --skip-m10)   SKIP_M10=1 ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; break ;;
    -*)
      echo "unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$TARGET_GATE" ]]; then
        echo "only one gate name accepted; got '$TARGET_GATE' and '$1'" >&2
        exit 2
      fi
      TARGET_GATE="$1"
      ;;
  esac
  shift
done

if [[ "$DRY_RUN" == "1" ]]; then
  echo "semantic-terminal · M10 SSOT checker runner (dry-run)"
  echo "project-root: $PROJECT_ROOT"
  echo "missiond-checker: $MISSIOND_MATURITY_CHECKER"
  echo "skip-rust: $SKIP_RUST  skip-node: $SKIP_NODE  skip-m10: $SKIP_M10"
  for gate in "${GATES[@]}"; do
    [[ -n "$TARGET_GATE" && "$TARGET_GATE" != "$gate" ]] && continue
    echo
    echo "─── gate: $gate"
    gate_describe "$gate"
  done
  exit 0
fi

if [[ -n "$TARGET_GATE" ]]; then
  found=0
  for gate in "${GATES[@]}"; do
    [[ "$gate" == "$TARGET_GATE" ]] && found=1
  done
  if (( ! found )); then
    echo "unknown gate: $TARGET_GATE" >&2
    echo "valid gates: ${GATES[*]}" >&2
    exit 2
  fi
  echo "─── gate: $TARGET_GATE"
  run_gate "$TARGET_GATE"
  exit 0
fi

failed=()
for gate in "${GATES[@]}"; do
  echo "─── gate: $gate"
  if ! run_gate "$gate"; then
    failed+=("$gate")
  fi
done

if (( ${#failed[@]} > 0 )); then
  echo
  printf 'FAIL gates: %s\n' "${failed[*]}" >&2
  exit 1
fi

echo
echo "all gates passed"
