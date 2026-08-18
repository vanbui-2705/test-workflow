#!/usr/bin/env node
// ============================================================
//  test-workflow — cross-platform, monorepo-aware test CLI
//  Runs via npm/npx. Discovers ALL python/js sub-projects
//  (recursively, excluding node_modules/.git/.venv) and runs
//  a fail-fast pipeline on each: lint -> unit -> integration -> e2e.
//
//  Usage:  npx test-workflow            (full, all sub-projects)
//          npx test-workflow fast       (lint + unit only)
//          npx test-workflow --root .   (explicit root, default cwd)
// ============================================================
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const MODE = (process.argv[2] || 'full').replace(/^--mode=/, '');
const ROOT = process.cwd();
const EXCLUDE = new Set(['node_modules', '.git', '.venv', 'venv', '__pycache__', '.next', 'dist', 'build', '.codex-tmp', '.superpowers']);

console.log(`🔍 Scanning ${ROOT} for projects (monorepo-aware)...`);

// --- discover sub-projects ---
function walk(dir, found) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
  let isPy = fs.existsSync(path.join(dir, 'pyproject.toml')) || fs.existsSync(path.join(dir, 'requirements.txt'));
  let isJs = fs.existsSync(path.join(dir, 'package.json'));
  if (isPy || isJs) found.push(dir);
  for (const e of entries) {
    if (!e.isDirectory() || EXCLUDE.has(e.name)) continue;
    walk(path.join(dir, e.name), found);
  }
}
const projects = [];
walk(ROOT, projects);
// Dedupe + sort by depth (shallow first)
projects.sort((a, b) => a.split(path.sep).length - b.split(path.sep).length);
const uniq = [...new Set(projects)];
console.log(`   Found ${uniq.length} project(s):`);
uniq.forEach(p => console.log('     • ' + path.relative(ROOT, p) || '   (root)'));

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

let failed = 0;
for (const proj of uniq) {
  const label = path.relative(ROOT, proj) || '(root)';
  console.log(`\n╔════════════════════════════════════════════════════`);
  console.log(`║ PROJECT: ${label}`);
  console.log(`╚════════════════════════════════════════════════════`);

  const hasPy = fs.existsSync(path.join(proj, 'pyproject.toml')) || fs.existsSync(path.join(proj, 'requirements.txt')) || fs.readdirSync(proj).some(f => f.endsWith('.py'));
  const hasJs = fs.existsSync(path.join(proj, 'package.json'));
  const scripts = hasJs ? pkgScripts(proj) : {};

  const tier = (name, cmd) => {
    console.log(`\n── ▶ ${name} ───────────────────────────────`);
    try {
      execSync(cmd, { cwd: proj, stdio: 'inherit', shell: true });
      console.log(`✅ ${name} passed`);
    } catch (e) {
      console.log(`❌ ${name} FAILED`);
      failed++;
    }
  };

  // LINT
  if (hasPy && hasTool('ruff')) tier('PY lint (ruff)', 'ruff check .');
  else if (hasPy) console.log('⚠ ruff missing — pip install ruff');
  if (hasJs && scripts.lint) tier('JS lint', `npm run lint --prefix "${proj}"`);

  // UNIT
  if (hasPy && hasTool('pytest')) {
    const tdir = fs.existsSync(path.join(proj, 'tests')) ? 'tests' : '.';
    tier('PY unit', `pytest -q ${tdir}`);
  } else if (hasPy) console.log('⚠ pytest missing');
  if (hasJs && scripts['test:unit']) tier('JS unit', `npm run test:unit --prefix "${proj}"`);
  else if (hasJs && scripts.test) tier('JS unit', `npm test --prefix "${proj}"`);

  // INTEGRATION + E2E
  if (MODE !== 'fast') {
    if (hasPy && fs.existsSync(path.join(proj, 'tests_integration')) && hasTool('pytest'))
      tier('PY integration', 'pytest -q tests_integration');
    if (hasJs && scripts['test:integ']) tier('JS integration', `npm run test:integ --prefix "${proj}"`);
    if (hasPy && fs.existsSync(path.join(proj, 'tests_e2e')) && hasTool('pytest'))
      tier('PY e2e', 'pytest -q tests_e2e');
    if (hasJs && scripts['test:e2e']) tier('JS e2e', `npm run test:e2e --prefix "${proj}"`);
  }
}

console.log(`\n🎉 Workflow complete (mode: ${MODE}) — ${uniq.length} project(s), ${failed} tier(s) failed`);
process.exit(failed ? 1 : 0);
