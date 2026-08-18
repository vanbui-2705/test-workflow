#!/usr/bin/env node
// ============================================================
//  test-workflow — cross-platform, monorepo-aware test CLI
//  Runs via npm/npx. Discovers ALL python/js sub-projects
//  (recursively, excluding node_modules/.git/.venv) and runs
//  a fail-fast pipeline on each: lint -> unit -> integration -> e2e.
//
//  Python test env resolution (open, follows project dir):
//    1. project venv (.venv/venv/env) -> use its pytest
//    2. uv available                  -> uv run --with pytest pytest
//    3. global pytest                 -> use it (caller catches crashes)
//    4. none                          -> warn, skip unit gracefully
//
//  Usage:  npx test-workflow            (full, all sub-projects)
//          npx test-workflow fast       (lint + unit only)
// ============================================================
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const rawArg = process.argv[2] || 'full';
if (rawArg === '--help' || rawArg === '-h' || rawArg === 'help') {
  console.log(`test-workflow — monorepo-aware test runner
Usage:
  npx test-workflow            full pipeline (lint+unit+integration+e2e)
  npx test-workflow fast       lint + unit only (local / pre-commit)
  npx test-workflow --root DIR run against DIR (default: cwd)
Discovers every Python/JS sub-project, runs fail-fast tiers.
Repo: https://github.com/vanbui-2705/test-workflow`);
  process.exit(0);
}
const MODE = rawArg.replace(/^--mode=/, '');
const ROOT = process.cwd();
const EXCLUDE = new Set(['node_modules', '.git', '.venv', 'venv', '__pycache__', '.next', 'dist', 'build', '.codex-tmp', '.superpowers']);
const TAIL = 40; // cap output lines per tier to avoid giant dumps

console.log(`🔍 Scanning ${ROOT} for projects (monorepo-aware)...`);

function walk(dir, found) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
  const isPy = fs.existsSync(path.join(dir, 'pyproject.toml')) || fs.existsSync(path.join(dir, 'requirements.txt'));
  const isJs = fs.existsSync(path.join(dir, 'package.json'));
  if (isPy || isJs) found.push(dir);
  for (const e of entries) {
    if (!e.isDirectory() || EXCLUDE.has(e.name)) continue;
    walk(path.join(dir, e.name), found);
  }
}
const projects = [];
walk(ROOT, projects);
projects.sort((a, b) => a.split(path.sep).length - b.split(path.sep).length);
const uniq = [...new Set(projects)];
console.log(`   Found ${uniq.length} project(s):`);
uniq.forEach(p => console.log('     • ' + (path.relative(ROOT, p) || '(root)')));

if (uniq.length === 0) {
  console.log('⚠ No Python or JS project markers found — nothing to test.');
  process.exit(0);
}

function hasTool(cmd) {
  try { execSync(`${cmd} --version`, { stdio: 'ignore', shell: true }); return true; }
  catch (e) { return false; }
}
function pkgScripts(dir) {
  try { return require(path.join(dir, 'package.json')).scripts || {}; }
  catch (e) { return {}; }
}

// Resolve a pytest command for a project (open, follows project dir)
// Priority: project venv -> uv run -> global pytest -> none
function resolvePytest(proj) {
  const cands = [
    path.join(proj, '.venv', 'Scripts', 'pytest.exe'),
    path.join(proj, 'venv', 'Scripts', 'pytest.exe'),
    path.join(proj, 'env', 'Scripts', 'pytest.exe'),
    path.join(proj, '.venv', 'bin', 'pytest'),
    path.join(proj, 'venv', 'bin', 'pytest'),
  ];
  for (const c of cands) if (fs.existsSync(c)) return `"${c}"`;
  // uv run installs deps from pyproject/requirements -> prefers project deps
  // unset VIRTUAL_ENV+PYTHONPATH so uv doesn't inherit the caller's (e.g. Hermes) venv
  if (fs.existsSync(path.join(proj, 'pyproject.toml'))) {
    if (hasTool('uv')) return 'env -u VIRTUAL_ENV -u PYTHONPATH uv run --python 3.12 pytest';
  } else if (fs.existsSync(path.join(proj, 'requirements.txt'))) {
    if (hasTool('uv')) return 'env -u VIRTUAL_ENV -u PYTHONPATH uv run --python 3.12 --with pytest pytest';
  }
  if (hasTool('pytest')) return 'pytest';
  return null;
}

let failed = 0;
for (const proj of uniq) {
  const label = path.relative(ROOT, proj) || '(root)';
  console.log(`\n╔════════════════════════════════════════════════════`);
  console.log(`║ PROJECT: ${label}`);
  console.log(`╚════════════════════════════════════════════════════`);

  const hasPy = fs.existsSync(path.join(proj, 'pyproject.toml')) || fs.existsSync(path.join(proj, 'requirements.txt')) || fs.readdirSync(proj).some(f => f.endsWith('.py'));
  const hasJs = fs.existsSync(path.join(proj, 'package.json'));
  const scripts = hasJs ? pkgScripts(proj) : {};

  const runTier = (name, cmd) => {
    console.log(`\n── ▶ ${name} ───────────────────────────────`);
    try {
      const out = execSync(cmd, { cwd: proj, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: true, maxBuffer: 20 * 1024 * 1024 });
      if (out.trim()) process.stdout.write(out);
      console.log(`✅ ${name} passed`);
    } catch (e) {
      const out = (e.stdout || '') + (e.stderr || '');
      const lines = out.split('\n').filter(Boolean);
      if (lines.length) process.stdout.write(lines.slice(-TAIL).join('\n') + '\n');
      console.log(`❌ ${name} FAILED`);
      failed++;
    }
  };

  // LINT
  if (hasPy && hasTool('ruff')) runTier('PY lint (ruff)', 'ruff check --output-format concise .');
  else if (hasPy) console.log('⚠ ruff missing — pip install ruff');
  if (hasJs && scripts.lint) runTier('JS lint', `npm run lint --prefix "${proj}"`);

  // UNIT
  if (hasPy) {
    const pytestCmd = resolvePytest(proj);
    if (pytestCmd) {
      const tdir = fs.existsSync(path.join(proj, 'tests')) ? 'tests' : '.';
      runTier('PY unit', `${pytestCmd} -q ${tdir}`);
    } else {
      console.log('\n── ▶ PY unit ───────────────────────────────');
      console.log('⚠ pytest unavailable (no .venv, no uv, no global) — skipping unit');
    }
  }
  if (hasJs && (scripts['test:unit'] || scripts.test)) runTier('JS unit', `npm run ${scripts['test:unit'] ? 'test:unit' : 'test'} --prefix "${proj}" --if-present`);

  // INTEGRATION + E2E
  if (MODE !== 'fast') {
    if (hasPy) {
      const pytestCmd = resolvePytest(proj);
      if (fs.existsSync(path.join(proj, 'tests_integration')) && pytestCmd) runTier('PY integration', `${pytestCmd} -q tests_integration`);
      if (fs.existsSync(path.join(proj, 'tests_e2e')) && pytestCmd) runTier('PY e2e', `${pytestCmd} -q tests_e2e`);
    }
    if (hasJs && scripts['test:integ']) runTier('JS integration', `npm run test:integ --prefix "${proj}"`);
    if (hasJs && scripts['test:e2e']) runTier('JS e2e', `npm run test:e2e --prefix "${proj}"`);
  }
}

console.log(`\n🎉 Workflow complete (mode: ${MODE}) — ${uniq.length} project(s), ${failed} tier(s) failed`);
process.exit(failed ? 1 : 0);
