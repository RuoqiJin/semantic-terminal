#!/usr/bin/env bash
# semantic-terminal · M6 SSOT checker runner
# Mirrors (checker-plan ...) in .missiond/intent-manifest.lisp.
# Read-only: never stages, commits, formats, installs, or mutates files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# .missiond/ allowlist for the ssot-write-scope gate.
SSOT_ALLOWED=("intent.lisp" "intent-manifest.lisp" "check.sh")

GATES=(
  "ssot-write-scope"
  "ssot-clean-diff"
  "forbid-source-mutation"
  "forbid-prebuilt-touch"
  "rust-tests"
  "node-smoke"
)

usage() {
  cat <<'EOF'
Usage: bash .missiond/check.sh [--dry-run] [--skip-rust] [--skip-node] [<gate>]

Runs the six M6 SSOT gates declared in .missiond/intent-manifest.lisp:
  ssot-write-scope          .missiond/ tree contains only the SSOT allowlist
  ssot-clean-diff           git diff --check on intent.lisp / intent-manifest.lisp
  forbid-source-mutation    no diff vs HEAD under crates / packages / Cargo.{toml,lock}
  forbid-prebuilt-touch     no .node prebuilt touched under packages/
  rust-tests                cargo test -p semantic-terminal
  node-smoke                node packages/semantic-terminal/test.js

Flags:
  --dry-run     list all gates, commands, and pass criteria without running
  --skip-rust   skip the rust-tests gate
  --skip-node   skip the node-smoke gate
  <gate>        run a single named gate

Exit code is 0 on success, non-zero on hard failure. The runner never
stages, commits, formats, installs, or mutates files.
EOF
}

# Per-gate command/pass-if descriptions used by --dry-run and failure logs.
gate_describe() {
  case "$1" in
    ssot-write-scope)
      echo "command : git ls-files --cached --others --exclude-standard -- .missiond/"
      echo "pass-if : every path basename is one of {${SSOT_ALLOWED[*]}}"
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

gate_ssot_write_scope() {
  local listing path base unexpected=()
  listing="$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard -- .missiond/)"
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    base="${path##*/}"
    if ! is_allowed_basename "$base"; then
      unexpected+=("$path")
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
    .missiond/intent-manifest.lisp
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

DRY_RUN=0
SKIP_RUST=0
SKIP_NODE=0
TARGET_GATE=""

while (( $# )); do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-rust)  SKIP_RUST=1 ;;
    --skip-node)  SKIP_NODE=1 ;;
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
  echo "semantic-terminal · M6 SSOT checker runner (dry-run)"
  echo "project-root: $PROJECT_ROOT"
  echo "skip-rust: $SKIP_RUST  skip-node: $SKIP_NODE"
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
