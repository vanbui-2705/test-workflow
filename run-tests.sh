#!/usr/bin/env bash
# ============================================================
#  run-tests.sh — monorepo-aware shared test runner
#  Discovers ALL python/js sub-projects recursively (excluding
#  node_modules/.git/.venv/.next) and runs fail-fast pipeline
#  (lint -> unit -> integration -> e2e) on each.
#  Usage:  ~/test-workflow/run-tests.sh          (full)
#          ~/test-workflow/run-tests.sh fast     (lint+unit only)
# ============================================================
set -uo pipefail

MODE="${1:-full}"
ROOT="$(pwd)"
EXCLUDE='node_modules|.git|.venv|venv|__pycache__|.next|dist|build|.codex-tmp|.superpowers'
echo "🔍 Scanning $ROOT for projects (monorepo-aware)..."

# Collect project dirs
mapfile -t PROJS < <(find "$ROOT" -type f \( -name pyproject.toml -o -name requirements.txt -o -name package.json \) 2>/dev/null \
  | grep -vE "/($EXCLUDE)/" \
  | xargs -n1 dirname 2>/dev/null | sort -u)

if [ "${#PROJS[@]}" -eq 0 ]; then
  echo "⚠ No Python or JS project markers found — nothing to test."
  exit 0
fi
echo "   Found ${#PROJS[@]} project(s):"
printf '     • %s\n' "${PROJS[@]}"

FAILED=0
for proj in "${PROJS[@]}"; do
  echo ""
  echo "╔════════════════════════════════════════════════════"
  echo "║ PROJECT: $proj"
  echo "╚════════════════════════════════════════════════════"

  IS_PY=no; IS_JS=no
  [ -f "$proj/pyproject.toml" ] || [ -f "$proj/requirements.txt" ] || compgen -G "$proj/*.py" >/dev/null 2>&1 && IS_PY=yes
  [ -f "$proj/package.json" ] && IS_JS=yes

  tier() {
    local name="$1"; shift
    echo ""
    echo "── ▶ $name ───────────────────────────────"
    if "$@"; then echo "✅ $name passed"; else echo "❌ $name FAILED"; FAILED=$((FAILED+1)); fi
  }

  # LINT
  if [ "$IS_PY" = yes ] && command -v ruff >/dev/null 2>&1; then
    tier "PY lint (ruff)" bash -c "cd '$proj' && ruff check ."
  elif [ "$IS_PY" = yes ]; then echo "⚠ ruff missing"; fi
  if [ "$IS_JS" = yes ] && grep -q '"lint"' "$proj/package.json" 2>/dev/null; then
    tier "JS lint" bash -c "cd '$proj' && npm run lint"
  fi

  # UNIT
  if [ "$IS_PY" = yes ] && command -v pytest >/dev/null 2>&1; then
    [ -d "$proj/tests" ] && tier "PY unit" bash -c "cd '$proj' && pytest -q tests/" \
                          || tier "PY unit" bash -c "cd '$proj' && pytest -q ."
  elif [ "$IS_PY" = yes ]; then echo "⚠ pytest missing"; fi
  if [ "$IS_JS" = yes ] && grep -q '"test:unit"\|"test"' "$proj/package.json" 2>/dev/null; then
    tier "JS unit" bash -c "cd '$proj' && npm run test:unit --if-present"
  fi

  # INTEGRATION + E2E
  if [ "$MODE" != "fast" ]; then
    if [ "$IS_PY" = yes ] && [ -d "$proj/tests_integration" ] && command -v pytest >/dev/null 2>&1; then
      tier "PY integration" bash -c "cd '$proj' && pytest -q tests_integration/"
    fi
    if [ "$IS_JS" = yes ] && grep -q '"test:integ"' "$proj/package.json" 2>/dev/null; then
      tier "JS integration" bash -c "cd '$proj' && npm run test:integ"
    fi
    if [ "$IS_PY" = yes ] && [ -d "$proj/tests_e2e" ] && command -v pytest >/dev/null 2>&1; then
      tier "PY e2e" bash -c "cd '$proj' && pytest -q tests_e2e/"
    fi
    if [ "$IS_JS" = yes ] && grep -q '"test:e2e"' "$proj/package.json" 2>/dev/null; then
      tier "JS e2e" bash -c "cd '$proj' && npm run test:e2e"
    fi
  fi
done

echo ""
echo "🎉 Workflow complete (mode: $MODE) — ${#PROJS[@]} project(s), $FAILED tier(s) failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
