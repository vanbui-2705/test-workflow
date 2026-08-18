#!/usr/bin/env node
// ============================================================
//  test-workflow — cross-platform CLI (runs via npm/npx)
//  Replicates run-tests.sh in pure Node so it works on any OS
//  with Node installed. Pipeline (fail-fast):
//    lint -> unit -> integration -> e2e
//  Usage:  npx test-workflow            (full)
//          npx test-workflow fast       (lint + unit only)
// ============================================================
'use strict';
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const MODE = process.argv[2] || 'full';
const ROOT = process.cwd();
console.log(`🔍 Scanning ${ROOT} for project type...`);

function exists(p) { return fs.existsSync(path.join(ROOT, p)); }
function anyPy() {
  try { return fs.readdirSync(ROOT).some(f => f.endsWith('.py')); }
  catch (e) { return false; }
}
function hasPy() { return exists('pyproject.toml') || exists('requirements.txt') || anyPy(); }
function hasJs() { return exists('package.json'); }

const IS_PY = hasPy();
const IS_JS = hasJs();
console.log(`   Python: ${IS_PY ? 'yes' : 'no'} | JS/TS: ${IS_JS ? 'yes' : 'no'}`);

if (!IS_PY && !IS_JS) {
  console.log('⚠ No Python or JS project markers found — nothing to test.');
  process.exit(0);
}

function hasTool(cmd) {
  try { execSync(`${cmd} --version`, { stdio: 'ignore', shell: true }); return true; }
  catch (e) { return false; }
}
function pkgScripts() {
  try { return require(path.join(ROOT, 'package.json')).scripts || {}; }
  catch (e) { return {}; }
}
function pkgHas(s) { return !!pkgScripts()[s]; }

function run(name, cmd) {
  console.log(`\n── ▶ ${name} ───────────────────────────────`);
  try {
    execSync(cmd, { cwd: ROOT, stdio: 'inherit', shell: true });
    console.log(`✅ ${name} passed`);
  } catch (e) {
    console.log(`❌ ${name} FAILED`);
    process.exit(1);
  }
}

// LINT (fail-fast)
if (IS_PY) {
  if (hasTool('ruff')) run('PY lint (ruff)', 'ruff check .');
  else console.log('⚠ ruff missing — install: pip install ruff');
}
if (IS_JS) {
  if (pkgHas('lint')) run('JS lint', 'npm run lint');
  else console.log('⚠ no lint script in package.json');
}

// UNIT (fail-fast)
if (IS_PY) {
  if (hasTool('pytest')) run('PY unit', exists('tests') ? 'pytest -q tests/' : 'pytest -q .');
  else console.log('⚠ pytest missing — install: pip install pytest');
}
if (IS_JS) {
  if (pkgHas('test:unit')) run('JS unit', 'npm run test:unit');
  else if (pkgHas('test')) run('JS unit', 'npm test');
  else console.log('⚠ no test script in package.json');
}

// INTEGRATION + E2E (skip in fast mode)
if (MODE !== 'fast') {
  if (IS_PY && exists('tests_integration') && hasTool('pytest')) {
    run('PY integration', 'pytest -q tests_integration/');
  }
  if (IS_JS && pkgHas('test:integ')) run('JS integration', 'npm run test:integ');
  if (IS_PY && exists('tests_e2e') && hasTool('pytest')) {
    run('PY e2e', 'pytest -q tests_e2e/');
  }
  if (IS_JS && pkgHas('test:e2e')) run('JS e2e', 'npm run test:e2e');
}

console.log(`\n🎉 Workflow complete (mode: ${MODE})`);
