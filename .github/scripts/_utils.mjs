import { spawnSync } from 'node:child_process';

export function fail(message) {
  throw new Error(message);
}

export function run(command, args = [], { allowFailure = false, input, timeout = 120000 } = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    shell: false,
    input,
    timeout,
    windowsHide: true,
  });
  const stdout = result.stdout ?? '';
  const stderr = result.stderr ?? '';
  if (!allowFailure && result.status !== 0) {
    fail(`${command} ${args.join(' ')} failed (${result.status ?? 'spawn error'}): ${(stderr || result.error?.message || stdout).trim()}`);
  }
  return { status: result.status, stdout, stderr, error: result.error };
}

export function azdValue(name) {
  const value = run('azd', ['env', 'get-value', name]).stdout.trim();
  if (!value) fail(`${name} is empty. Select the expected azd environment first.`);
  return value.replace(/\/$/, '');
}

export async function request(url, options = {}) {
  const timeoutMs = options.timeoutMs ?? 60000;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, timeoutMs: undefined, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

export async function jsonRequest(url, options = {}, expected = [200]) {
  const response = await request(url, options);
  const text = await response.text();
  if (!expected.includes(response.status)) {
    fail(`${options.method ?? 'GET'} ${url} returned HTTP ${response.status}: ${text.slice(0, 300)}`);
  }
  try {
    return { response, data: text ? JSON.parse(text) : null, text };
  } catch {
    fail(`${url} did not return valid JSON: ${text.slice(0, 300)}`);
  }
}

export function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function poll(url, { attempts = 30, delayMs = 10000 } = {}) {
  let lastStatus = 'request failed';
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const response = await request(url, { timeoutMs: 20000 });
      lastStatus = `HTTP ${response.status}`;
      if (response.status === 200) return response;
    } catch (error) {
      lastStatus = error.message;
    }
    if (attempt < attempts) await sleep(delayMs);
  }
  fail(`${url} did not return HTTP 200 after ${attempts} attempts; last result: ${lastStatus}`);
}

export function asArray(payload, keys = ['data', 'items', 'products', 'todos', 'steps']) {
  if (Array.isArray(payload)) return payload;
  for (const key of keys) {
    if (Array.isArray(payload?.[key])) return payload[key];
  }
  return [];
}

export async function main(fn) {
  try {
    await fn();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exitCode = 1;
  }
}
