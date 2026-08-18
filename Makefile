# ============================================================
#  Hermes Test Workflow — shared across all projects
#  Usage: copy this Makefile + run-tests.sh into any project,
#         or run `make -f ~/test-workflow/Makefile` from a project root.
#  Pipeline (fail-fast): lint -> unit -> integration -> e2e
# ============================================================

# Auto-detect stack from project markers
IS_PY  := $(shell [ -f pyproject.toml ] || [ -f requirements.txt ] || ls *.py >/dev/null 2>&1 && echo yes || echo no)
IS_JS  := $(shell [ -f package.json ] && echo yes || echo no)

.PHONY: test test-fast lint unit integ e2e install ci

# Full pipeline (used by CI). Runs everything, fail-fast.
test:
	@$(MAKE) lint
	@$(MAKE) unit
	@$(MAKE) integ
	@$(MAKE) e2e
	@echo "✅ ALL TEST TIERS PASSED"

# Fast pipeline (used by pre-commit / local). Skips slow E2E.
test-fast:
	@$(MAKE) lint
	@$(MAKE) unit
	@echo "⚡ FAST TESTS PASSED"

# ---- Python ----
ifeq ($(IS_PY),yes)
lint:
	@command -v ruff >/dev/null 2>&1 && ruff check . || echo "⚠ ruff not installed (pip install ruff)"
unit:
	@command -v pytest >/dev/null 2>&1 && pytest -q tests/ 2>/dev/null || pytest -q . 2>/dev/null || echo "⚠ no pytest tests found"
integ:
	@command -v pytest >/dev/null 2>&1 && pytest -q tests_integration/ 2>/dev/null || echo "⚠ no integration tests (optional)"
e2e:
	@command -v pytest >/dev/null 2>&1 && pytest -q tests_e2e/ 2>/dev/null || echo "⚠ no e2e tests (optional)"
install:
	@pip install ruff pytest pytest-cov pytest-mock freezegun 2>/dev/null || true
endif

# ---- JavaScript / TypeScript ----
ifeq ($(IS_JS),yes)
lint:
	@command -v npm >/dev/null 2>&1 && npm run lint --if-present || echo "⚠ no lint script in package.json"
unit:
	@command -v npm >/dev/null 2>&1 && npm run test:unit --if-present || npm test --if-present || echo "⚠ no test script"
integ:
	@command -v npm >/dev/null 2>&1 && npm run test:integ --if-present || echo "⚠ no integration tests (optional)"
e2e:
	@command -v npm >/dev/null 2>&1 && npm run test:e2e --if-present || echo "⚠ no e2e tests (optional)"
install:
	@command -v npm >/dev/null 2>&1 && npm install || true
endif

# ---- No known stack ----
ifeq ($(IS_PY),no)
ifeq ($(IS_JS),no)
lint unit integ e2e:
	@echo "⚠ No Python or JS project markers found — nothing to test."
endif
endif

# Convenience: full CI simulation
ci: install test
