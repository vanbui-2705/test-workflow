#!/usr/bin/env bash
# ============================================================
#  run-tests.sh — shared test runner (drop into any project)
#  Auto-detects stack, then runs the fail-fast pipeline:
#    lint -> unit -> integration -> e2e
#  Usage:  ~/test-workflow/run-tests.sh          (full)
#          ~/test-workflow/run-tests.sh fast     (lint+unit only)
# ============================================================
set -uo pipefail

MODE="${1:-full}"
ROOT="$(pwd)"
echo "🔍 Scanning $ROOT for project type..."

detect_stack() {
  IS_PY=no; IS_JS=no
  if [ -f pyproject.toml ] || [ -f requirements.txt ] || compgen -G "*.py" >/dev/null 2>&1; then
    IS_PY=yes
  fi
  if [ -f package.json ]; then
    IS_JS=yes
  fi
}
detect_stack
echo "   Python: $IS_PY | JS/TS: $IS_JS"

if [ "$IS_PY" = no ] && [ "$IS_JS" = no ]; then
  echo "⚠ No Python or JS project markers found — nothing to test."
  exit 0
fi

# Each tier must fail the whole run if it fails (fail-fast).
tier() {
  local name="$1"; shift
  echo ""
  echo "── ▶ $name ───────────────────────────────"
  if "$@"; then
    echo "✅ $name passed"
  else
    echo "❌ $name FAILED"
    exit 1
  fi
}

# LINT (fail-fast)
if [ "$IS_PY" = yes ]; then
  if command -v ruff >/dev/null 2>&1; then
    tier "PY lint (ruff)" ruff check .
  else
    echo "⚠ ruff missing — install: pip install ruff"
  fi
fi
if [ "$IS_JS" = yes ]; then
  if [ -f package.json ] && grep -q '"lint"' package.json 2>/dev/null; then
    tier "JS lint" npm run lint
  else
    echo "⚠ no lint script in package.json"
  fi
fi

# UNIT (fail-fast)
if [ "$IS_PY" = yes ]; then
  if command -v pytest >/dev/null 2>&1; then
    if [ -d tests ]; then
      tier "PY unit" pytest -q tests/
    else
      tier "PY unit" pytest -q .
    fi
  else
    echo "⚠ pytest missing — install: pip install pytest"
  fi
fi
if [ "$IS_JS" = yes ]; then
  if grep -q '"test:unit"\|"test"' package.json 2>/dev/null; then
    tier "JS unit" npm run test:unit --if-present
  else
    echo "⚠ no test script in package.json"
  fi
fi

# INTEGRATION + E2E (skip in fast mode, fail-fast)
if [ "$MODE" != "fast" ]; then
  if [ "$IS_PY" = yes ] && [ -d tests_integration ] && command -v pytest >/dev/null 2>&1; then
    tier "PY integration" pytest -q tests_integration/
  fi
  if [ "$IS_JS" = yes ] && grep -q '"test:integ"' package.json 2>/dev/null; then
    tier "JS integration" npm run test:integ
  fi
  if [ "$IS_PY" = yes ] && [ -d tests_e2e ] && command -v pytest >/dev/null 2>&1; then
    tier "PY e2e" pytest -q tests_e2e/
  fi
  if [ "$IS_JS" = yes ] && grep -q '"test:e2e"' package.json 2>/dev/null; then
    tier "JS e2e" npm run test:e2e
  fi
fi

echo ""
echo "🎉 Workflow complete (mode: $MODE)"
