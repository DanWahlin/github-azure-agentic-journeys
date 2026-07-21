#!/usr/bin/env node

import { fail, run } from './_utils.mjs';

const command = process.argv.slice(2).join(' ').trim();
if (!command) {
  console.error('Usage: node .github/scripts/run-aks-command.mjs "kubectl <arguments>"');
  process.exit(2);
}
if (!/^(kubectl|helm)\s/.test(command)) {
  console.error('Only kubectl or helm diagnostic commands are allowed.');
  process.exit(2);
}

const envResult = run('azd', ['env', 'get-values', '--output', 'json']);
let env;
try {
  env = JSON.parse(envResult.stdout);
} catch {
  fail('azd env get-values did not return valid JSON. Select the expected azd environment first.');
}

const resourceGroup = env.AZURE_RESOURCE_GROUP;
const clusterName = env.AZURE_AKS_CLUSTER_NAME;
if (!resourceGroup || !clusterName) {
  fail('AZURE_RESOURCE_GROUP or AZURE_AKS_CLUSTER_NAME is missing from the selected azd environment.');
}

const result = run('az', [
  'aks', 'command', 'invoke',
  '--resource-group', resourceGroup,
  '--name', clusterName,
  '--command', command,
  '--output', 'json',
  '--only-show-errors',
]);

let remote;
try {
  remote = JSON.parse(result.stdout);
} catch {
  fail(`AKS command returned invalid JSON: ${(result.stdout || '').slice(0, 500)}`);
}

const hasExitCode = Object.hasOwn(remote, 'exitCode');
if (remote.provisioningState !== 'Succeeded' || !hasExitCode || typeof remote.exitCode !== 'number' || remote.exitCode !== 0) {
  fail(`Remote AKS command failed (${hasExitCode ? remote.exitCode : 'missing exit code'}):\n${remote.logs || remote.reason || ''}`);
}

if (remote.logs) process.stdout.write(remote.logs.endsWith('\n') ? remote.logs : `${remote.logs}\n`);
