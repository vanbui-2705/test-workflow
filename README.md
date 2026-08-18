# test-workflow

[![npm](https://img.shields.io/badge/npm-test--workflow-blue)](https://www.npmjs.com/package/test-workflow)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen.svg)](https://nodejs.org)

A single, language-agnostic test workflow for **all your projects** (Python and/or JS/TS).
It auto-detects the stack and runs a fail-fast pipeline — `lint → unit → integration → e2e` —
with **zero per-project configuration**. Run it once via `npx`, wire it into pre-commit and CI,
and every repo gets the same consistent quality gate.

## Why

- One command tests any project — no copy-pasting CI YAML into every repo.
- Monorepo-aware: recursively discovers every Python/JS sub-project and tests each in isolation.
- Fail-fast: a red tier stops the run immediately (exit 1) so you fix the first break, not the fifth.
- Local == CI: identical commands and order, so "works on my machine" stops being a lie.
- Respects your environment: prefers the project's own venv, otherwise an isolated `uv run`,
  and never edits source under test.

## Features

- 🔍 **Auto stack detection** — Python (`pyproject.toml` / `requirements.txt` / `*.py`),
  JS/TS (`package.json`), or both in the same tree.
- 🏗️ **Monorepo-aware** — scans recursively (excludes `node_modules`, `.git`, `.venv`, `.next`, …).
- ⚡ **Fail-fast pipeline** — `lint → unit → integration → e2e`, stops at first failure.
- 🐍 **Python env resolution (open, follows your project dir):**
  1. project venv (`.venv` / `venv` / `env`) → its `pytest`
  2. `uv` available → `uv run --python 3.12 pytest` (isolated, installs deps from `pyproject.toml`)
  3. global `pytest` → used as-is
  4. none → warns and skips unit gracefully
- 🧹 **Concise output** — `ruff --output-format concise`, per-tier logs capped to the last 40 lines.
- 🪟 **Cross-platform** — Node CLI runs on Windows / macOS / Linux (no `make` required).

## Install

```bash
# Run without installing (needs network + the repo on npm/GitHub)
npx test-workflow

# Or install globally for a `test-workflow` command everywhere
npm i -g test-workflow

# Or clone the source (gets run-tests.sh, pre-commit, and the GitHub Action)
git clone https://github.com/vanbui-2705/test-workflow ~/test-workflow
```

> The `npx`/`npm` entry point is `bin/test-workflow.js` — a pure Node CLI, cross-platform.

## Usage

From inside any project directory:

```bash
cd path/to/your-project

test-workflow fast     # lint + unit only (local / pre-commit)
test-workflow          # full: lint + unit + integration + e2e

# or, using the bundled shell runner (no npm needed):
bash ~/test-workflow/run-tests.sh fast
bash ~/test-workflow/run-tests.sh
```

Get help:

```bash
test-workflow --help
```

### Wire it into a project (recommended for long-lived repos)

```bash
cd path/to/your-project

# 1) Runner, living inside the project
cp ~/test-workflow/run-tests.sh ./run-tests.sh && chmod +x ./run-tests.sh

# 2) Pre-commit hook — runs the fast tier before every commit
cp ~/test-workflow/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

# 3) CI — runs the full pipeline on GitHub Actions
mkdir -p .github/workflows
cp ~/test-workflow/github-actions/test.yml .github/workflows/test.yml
```

Then:

```bash
./run-tests.sh fast   # local, fast
git commit -m "..."   # fast tier runs automatically
git push              # GitHub Actions runs the full pipeline
```

## How it works

```
lint → unit → integration → e2e
 │      │        │             │
 │      │        │             └ E2E: critical paths only (few, slow)
 │      │        └ INTEGRATION: modules wired together, externals mocked
 │      └ UNIT: single functions, isolated, fully mocked (many, fast)
 └ LINT: ruff (py) / eslint (js) — static, instant
```

A failing tier stops the run immediately (exit 1) and prints `❌`. Later tiers do not run.

| Mode   | Tiers                              | Use for            |
|--------|------------------------------------|--------------------|
| `fast` | `lint` + `unit`                    | local / pre-commit |
| (full) | `lint` + `unit` + `integration` + `e2e` | CI          |

## Auto-detection

| Marker in the project                          | Workflow runs        |
|------------------------------------------------|----------------------|
| `pyproject.toml` / `requirements.txt` / `*.py` | Python tier          |
| `package.json`                                  | JS/TS tier           |
| both                                           | both stacks          |
| none                                           | `⚠ No markers` → skip (exit 0) |

## Project layout conventions

```
your-project/
├── run-tests.sh
├── .github/workflows/test.yml
├── src/ (or *.py / *.ts)
├── tests/              # UNIT tests (recommended)
├── tests_integration/  # INTEGRATION (optional)
└── tests_e2e/          # E2E (optional)
```

**Python** — `tests/test_example.py`:

```python
def test_add():
    assert 1 + 1 == 2
```

**JS/TS** — add scripts to `package.json`:

```json
{
  "scripts": {
    "lint": "eslint .",
    "test:unit": "vitest run",
    "test:integ": "vitest run --mode integration",
    "test:e2e": "playwright test"
  }
}
```

If a project has no tests yet, the workflow still runs lint and reports "no tests found" — it does not fail.

## Environment requirements (one-time)

```bash
# Python tooling
pip install ruff pytest

# JS/TS tooling (per project)
npm install   # provides eslint / vitest / playwright per package.json
```

`uv` is optional but recommended — when present, the workflow uses it to run an isolated,
dependency-correct test environment instead of the global interpreter.

On Windows/MSYS, `make` is not installed by default; use `run-tests.sh` (no `make` needed).
On Linux/CI, `make` is available and the bundled `Makefile` can drive the same commands.

## Design principles

```
SYSTEM: You are a Shared Test Workflow runner.
ROLE:   Verify any Python or JS/TS project with one command, zero per-project config.
PIPELINE (fail-fast): lint → unit → integration → e2e
DETECT:  py if pyproject/requirements/*.py; js if package.json; both → run both; none → skip.
RULES:
  1. Never edit source under test — only verify.
  2. Fail-fast: any tier non-zero → exit 1, stop.
  3. Deterministic: callers mock externals (network/time).
  4. Idempotent: re-run = same result.
  5. Local == CI: same commands, same order.
OUTPUT: ✅ per tier, 🎉 on success, ❌ + exit 1 on failure.
```

## Troubleshooting

| Symptom                          | Cause                    | Fix                              |
|----------------------------------|--------------------------|----------------------------------|
| `⚠ ruff missing`                 | ruff not installed       | `pip install ruff`               |
| `⚠ pytest unavailable … skipping`| no venv/uv/global pytest  | `pip install pytest` or install `uv` |
| `No Python or JS markers`        | wrong directory          | `cd` into the project            |
| exit 1 at lint                   | style/import issue       | fix per ruff/eslint hint         |
| red CI, green local              | missing dep on CI        | add install step in `test.yml`   |

## License

MIT © vanbui-2705 — https://github.com/vanbui-2705/test-workflow
