#!/usr/bin/env bash
# ============================================================
#  run-tests.sh — monorepo-aware shared test runner
#  Discovers ALL python/js sub-projects recursively (excluding
#  node_modules/.git/.venv/.next) and runs fail-fast pipeline
#  (lint -> unit -> integration -> e2e) on each.
#
#  Python test env (open, follows project dir):
#    1. project venv (.venv/venv/env) -> its pytest
#    2. uv available                  -> uv run --with pytest pytest
#    3. global pytest                 -> use it
#    4. none                          -> warn, skip unit gracefully
#  Usage:  ~/test-workflow/run-tests.sh          (full)
#          ~/test-workflow/run-tests.sh fast     (lint+unit only)
# ============================================================
set -uo pipefail

MODE="${1:-full}"
ROOT="$(pwd)"
EXCLUDE='node_modules|.git|.venv|venv|__pycache__|.next|dist|build|.codex-tmp|.superpowers'
TAIL=40
echo "🔍 Scanning $ROOT for projects (monorepo-aware)..."

mapfile -t PROJS < <(find "$ROOT" -type f \( -name pyproject.toml -o -name requirements.txt -o -name package.json \) 2>/dev/null \
  | grep -vE "/($EXCLUDE)/" | xargs -n1 dirname 2>/dev/null | sort -u)

if [ "${#PROJS[@]}" -eq 0 ]; then
  echo "⚠ No Python or JS project markers found — nothing to test."
  exit 0
fi
echo "   Found ${#PROJS[@]} project(s):"
printf '     • %s\n' "${PROJS[@]}"

# Resolve pytest command for a project dir ($1). Echoes command or empty.
# Priority: project venv -> uv run (with deps) -> global pytest -> none
resolve_pytest() {
  local p="$1"
  for v in .venv venv env; do
    for exe in "$p/$v/Scripts/pytest.exe" "$p/$v/bin/pytest"; do
      [ -x "$exe" ] && { echo "$exe"; return; }
    done
  done
  if [ -f "$p/pyproject.toml" ]; then
    command -v uv >/dev/null 2>&1 && { echo "env -u VIRTUAL_ENV -u PYTHONPATH uv run --python 3.12 pytest"; return; }
  elif [ -f "$p/requirements.txt" ]; then
    command -v uv >/dev/null 2>&1 && { echo "env -u VIRTUAL_ENV -u PYTHONPATH uv run --python 3.12 --with pytest pytest"; return; }
  fi
  command -v pytest >/dev/null 2>&1 && { echo "pytest"; return; }
  echo ""
}

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
    local out rc
    out=$(("$@") 2>&1); rc=$?
    if [ -n "$out" ]; then
      local n; n=$(printf '%s\n' "$out" | grep -c .)
      if [ "$n" -gt "$TAIL" ]; then printf '%s\n' "$out" | tail -n "$TAIL"; else printf '%s\n' "$out"; fi
    fi
    if [ "$rc" -eq 0 ]; then echo "✅ $name passed"; else echo "❌ $name FAILED"; FAILED=$((FAILED+1)); fi
  }

  # LINT
  if [ "$IS_PY" = yes ] && command -v ruff >/dev/null 2>&1; then
    tier "PY lint (ruff)" bash -c "cd '$proj' && ruff check --output-format concise ."
  elif [ "$IS_PY" = yes ]; then echo "⚠ ruff missing"; fi
  if [ "$IS_JS" = yes ] && grep -q '"lint"' "$proj/package.json" 2>/dev/null; then
    tier "JS lint" bash -c "cd '$proj' && npm run lint"
  fi

  # UNIT
  if [ "$IS_PY" = yes ]; then
    PYTEST_CMD="$(resolve_pytest "$proj")"
    if [ -n "$PYTEST_CMD" ]; then
      [ -d "$proj/tests" ] && TD="tests" || TD="."
      tier "PY unit" bash -c "cd '$proj' && $PYTEST_CMD -q $TD"
    else
      echo ""
      echo "── ▶ PY unit ───────────────────────────────"
      echo "⚠ pytest unavailable (no .venv, no uv, no global) — skipping unit"
    fi
  fi
  if [ "$IS_JS" = yes ] && grep -q '"test:unit"\|"test"' "$proj/package.json" 2>/dev/null; then
    tier "JS unit" bash -c "cd '$proj' && npm run test:unit --if-present"
  fi

  # INTEGRATION + E2E
  if [ "$MODE" != "fast" ]; then
    if [ "$IS_PY" = yes ]; then
      PYTEST_CMD="$(resolve_pytest "$proj")"
      if [ -d "$proj/tests_integration" ] && [ -n "$PYTEST_CMD" ]; then
        tier "PY integration" bash -c "cd '$proj' && $PYTEST_CMD -q tests_integration"
      fi
      if [ -d "$proj/tests_e2e" ] && [ -n "$PYTEST_CMD" ]; then
        tier "PY e2e" bash -c "cd '$proj' && $PYTEST_CMD -q tests_e2e"
      fi
    fi
    if [ "$IS_JS" = yes ] && grep -q '"test:integ"' "$proj/package.json" 2>/dev/null; then
      tier "JS integration" bash -c "cd '$proj' && npm run test:integ"
    fi
    if [ "$IS_JS" = yes ] && grep -q '"test:e2e"' "$proj/package.json" 2>/dev/null; then
      tier "JS e2e" bash -c "cd '$proj' && npm run test:e2e"
    fi
  fi
done

echo ""
echo "🎉 Workflow complete (mode: $MODE) — ${#PROJS[@]} project(s), $FAILED tier(s) failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
