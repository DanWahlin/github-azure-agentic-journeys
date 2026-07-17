#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(2);
}

const args = process.argv.slice(2);
const promptIndex = args.indexOf('--prompt-file');
const cwdIndex = args.indexOf('--cwd');

if (promptIndex === -1 || !args[promptIndex + 1]) {
  fail('Usage: node run-copilot-prompt.mjs --prompt-file <path> [--cwd <path>]');
}

const promptPath = resolve(args[promptIndex + 1]);
const cwd = cwdIndex === -1 ? process.cwd() : resolve(args[cwdIndex + 1]);
const prompt = readFileSync(promptPath, 'utf8').trim();

if (!prompt) {
  fail(`Prompt file is empty: ${promptPath}`);
}

// Copilot CLI accepts prompt text through -p. It does not support a
// --prompt-file option, so this helper reads the file and passes one argv value.
const result = spawnSync('copilot', ['-p', prompt], {
  cwd,
  env: process.env,
  shell: false,
  stdio: 'inherit',
});

if (result.error) {
  fail(`Could not start Copilot CLI: ${result.error.message}`);
}

process.exit(result.status ?? 1);
