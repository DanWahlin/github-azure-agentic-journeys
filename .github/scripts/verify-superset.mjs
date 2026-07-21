// Superset AKS deployment verification through Azure run command.
// The host needs only az, azd, and Node.js. The script never prints secrets.
import { spawnSync } from 'node:child_process';

const WINDOWS_CLI_RUNNER = [
  "$ErrorActionPreference = 'Stop'",
  '$payload = ConvertFrom-Json -InputObject $env:AZURE_NATIVE_CLI_PAYLOAD',
  '$command = [string]$payload[0]',
  '$arguments = @($payload | Select-Object -Skip 1)',
  '$resolved = Get-Command -Name $command -ErrorAction Stop',
  '$target = [string]$resolved.Source',
  'if (-not $target) { $target = $command }',
  'if ($target.EndsWith(".cmd", [System.StringComparison]::OrdinalIgnoreCase) -or $target.EndsWith(".bat", [System.StringComparison]::OrdinalIgnoreCase)) {',
  '  foreach ($argument in $arguments) { if (([string]$argument).Contains([char]34)) { [Console]::Error.WriteLine("Arguments containing double quotes cannot be passed safely to a Windows .cmd/.bat shim."); exit 2 } }',
  '}',
  '& $target @arguments',
  '$ok = $?',
  '$code = $LASTEXITCODE',
  'if ($null -ne $code) { exit $code }',
  'if (-not $ok) { exit 1 }',
].join('; ');

function run(cmd, args) {
  const invocation = process.platform === 'win32'
    ? {
        file: 'powershell.exe',
        args: ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', WINDOWS_CLI_RUNNER],
        env: { ...process.env, AZURE_NATIVE_CLI_PAYLOAD: JSON.stringify([cmd, ...args]) },
      }
    : { file: cmd, args, env: process.env };
  const res = spawnSync(invocation.file, invocation.args, {
    encoding: 'utf8',
    env: invocation.env,
    windowsHide: true,
  });
  if (res.error) throw res.error;
  if (res.status !== 0) {
    throw new Error(`Command failed (${res.status}): ${cmd} ${args.join(' ')}\n${res.stderr || ''}`);
  }
  return res;
}

function azdEnv() {
  const res = run('azd', ['env', 'get-values', '--output', 'json']);
  return JSON.parse(res.stdout);
}

function aksCommand(env, command) {
  const res = run('az', [
    'aks', 'command', 'invoke',
    '--resource-group', env.AZURE_RESOURCE_GROUP,
    '--name', env.AZURE_AKS_CLUSTER_NAME,
    '--command', command,
    '--output', 'json',
    '--only-show-errors',
  ]);

  let result;
  try {
    result = JSON.parse(res.stdout);
  } catch {
    throw new Error(`AKS command returned invalid JSON: ${(res.stdout || '').slice(0, 500)}`);
  }
  if (result.provisioningState !== 'Succeeded' || result.exitCode !== 0) {
    throw new Error(`Remote AKS command failed (${result.exitCode ?? 'unknown'}):\n${result.logs || result.reason || ''}`);
  }
  return result.logs || '';
}

const results = [];
function record(name, pass, detail) {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? `: ${detail}` : ''}`);
}

async function main() {
  const env = azdEnv();
  const url = env.SUPERSET_URL;
  if (!url) throw new Error('SUPERSET_URL not set in azd environment');
  if (!env.AZURE_RESOURCE_GROUP || !env.AZURE_AKS_CLUSTER_NAME) {
    throw new Error('AKS resource group or cluster name is missing from the azd environment');
  }

  const podsJson = JSON.parse(aksCommand(
    env,
    'kubectl get pods -n superset -l app=superset -o json'
  ));
  if (!podsJson.items.length) {
    record('Superset pod exists', false, 'no pods found');
  }
  let podName = null;
  for (const pod of podsJson.items) {
    const phase = pod.status.phase;
    const statuses = pod.status.containerStatuses || [];
    const ready = statuses.length > 0 && statuses.every((item) => item.ready);
    const readyCount = statuses.filter((item) => item.ready).length;
    record(`Pod ${pod.metadata.name} Ready ${readyCount}/${statuses.length} (${phase})`,
      phase === 'Running' && ready);
    if (phase === 'Running' && ready) podName = pod.metadata.name;
  }
  if (!podName) podName = podsJson.items[0]?.metadata?.name;
  if (!podName) { finish(); return; }

  const initLogs = aksCommand(
    env,
    `kubectl logs -n superset ${podName} -c superset-init`
  );
  record('Init logs contain PostgresqlImpl', /PostgresqlImpl/.test(initLogs));
  record('Init logs have no SQLiteImpl fallback', !/SQLiteImpl/.test(initLogs));

  const mainLogs = aksCommand(
    env,
    `kubectl logs -n superset ${podName} -c superset`
  );
  record('Main logs retrieved with no SQLiteImpl fallback', Boolean(mainLogs.trim()) && !/SQLiteImpl/.test(mainLogs));

  const psycopg = aksCommand(
    env,
    `kubectl exec -n superset ${podName} -c superset -- python -c 'import psycopg2; print(1)'`
  );
  record('psycopg2 importable in main container', /^1\s*$/.test(psycopg));

  try {
    const response = await fetch(`${url}/health`, { redirect: 'manual' });
    const body = await response.text();
    record('GET /health returns HTTP 200', response.status === 200,
      `status=${response.status} body=${body.trim().slice(0, 40)}`);
  } catch (error) {
    record('GET /health returns HTTP 200', false, error.message);
  }

  finish();
}

function finish() {
  const failed = results.filter((result) => !result.pass);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((err) => { console.error(err.message || String(err)); process.exit(1); });
