import { spawnSync } from 'node:child_process';

export const WINDOWS_CLI_RUNNER = [
  "$ErrorActionPreference = 'Stop'",
  '$payload = ConvertFrom-Json -InputObject $env:AZURE_NATIVE_CLI_PAYLOAD',
  '$command = [string]$payload[0]',
  '$arguments = @($payload | Select-Object -Skip 1)',
  '$resolved = Get-Command -Name $command -ErrorAction Stop',
  '$target = [string]$resolved.Source',
  'if (-not $target) { $target = $command }',
  'if ($target.EndsWith(".cmd", [System.StringComparison]::OrdinalIgnoreCase) -or $target.EndsWith(".bat", [System.StringComparison]::OrdinalIgnoreCase)) {',
  "  $unsafe = [char[]]'\"&|<>^%!()'",
  '  foreach ($argument in $arguments) { $text = [string]$argument; if ($text.IndexOfAny($unsafe) -ge 0 -or $text.Contains([char]10) -or $text.Contains([char]13)) { [Console]::Error.WriteLine("Arguments containing shell metacharacters or control characters cannot be passed safely to a Windows .cmd/.bat shim."); exit 2 } }',
  '}',
  '& $target @arguments',
  '$ok = $?',
  '$code = $LASTEXITCODE',
  'if ($null -ne $code) { exit $code }',
  'if (-not $ok) { exit 1 }',
].join('; ');

export function fail(message) {
  throw new Error(message);
}

export function buildInvocation(command, args = [], platform = process.platform) {
  if (platform !== 'win32') {
    return { file: command, args, env: process.env };
  }
  return {
    file: 'powershell.exe',
    args: ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', WINDOWS_CLI_RUNNER],
    env: { ...process.env, AZURE_NATIVE_CLI_PAYLOAD: JSON.stringify([command, ...args]) },
  };
}

export function run(command, args = [], { allowFailure = false, input, timeout = 120000, cwd } = {}) {
  const invocation = buildInvocation(command, args);
  const result = spawnSync(invocation.file, invocation.args, {
    encoding: 'utf8',
    cwd,
    env: invocation.env,
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
