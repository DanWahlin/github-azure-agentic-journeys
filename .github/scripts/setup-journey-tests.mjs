#!/usr/bin/env node
import readline from 'node:readline/promises';
import { Writable } from 'node:stream';
import { run } from './_utils.mjs';

class MutedOutput extends Writable {
  muted = false;
  _write(chunk, encoding, callback) {
    if (!this.muted) process.stdout.write(chunk, encoding);
    callback();
  }
}

const output = new MutedOutput();
const rl = readline.createInterface({ input: process.stdin, output, terminal: Boolean(process.stdin.isTTY) });

async function ask(label, fallback = '') {
  if (!process.stdin.isTTY) {
    if (fallback) return fallback;
    throw new Error(`${label} is required in a non-interactive session; provide it through the documented environment variable`);
  }
  const suffix = fallback ? ` [${fallback.slice(0, 8)}${fallback.length > 8 ? '...' : ''}]` : '';
  const answer = (await rl.question(`${label}${suffix}: `)).trim();
  return answer || fallback;
}

async function askSecret(label, fallback = '') {
  if (!process.stdin.isTTY) return fallback;
  process.stdout.write(`${label}${fallback ? ' [press Enter to keep configured value]' : ''}: `);
  output.muted = true;
  const answer = (await rl.question('')).trim();
  output.muted = false;
  process.stdout.write('\n');
  return answer || fallback;
}

async function confirm(label, defaultYes = true) {
  if (!process.stdin.isTTY) return false;
  const answer = (await rl.question(`${label} ${defaultYes ? '[Y/n]' : '[y/N]'}: `)).trim().toLowerCase();
  return answer ? answer === 'y' || answer === 'yes' : defaultYes;
}

function parseJson(command, args) {
  return JSON.parse(run(command, args).stdout || '{}');
}

try {
  console.log('=== Journey E2E repository setup ===');
  run('gh', ['auth', 'status']);
  run('az', ['account', 'show']);

  const detectedRepo = parseJson('gh', ['repo', 'view', '--json', 'nameWithOwner']).nameWithOwner;
  const account = parseJson('az', ['account', 'show', '-o', 'json']);
  const repo = await ask('GitHub repository', process.env.GH_REPO || detectedRepo);
  const subscriptionId = await ask('Azure subscription ID', process.env.AZURE_SUBSCRIPTION_ID || account.id);
  let tenantId = await ask('Azure tenant ID', process.env.AZURE_TENANT_ID || account.tenantId);
  const scope = `/subscriptions/${subscriptionId}`;
  const spName = 'github-azure-agentic-journeys-e2e';
  const existing = parseJson('az', ['ad', 'sp', 'list', '--display-name', spName, '-o', 'json'])[0];
  let clientId = process.env.AZURE_CLIENT_ID || existing?.appId || '';
  let clientSecret = process.env.AZURE_CLIENT_SECRET || '';

  if (existing) {
    console.log(`Found service principal ${spName} (${clientId.slice(0, 8)}...).`);
    if (!clientSecret && await confirm('Create a fresh one-year credential for this service principal?')) {
      const reset = parseJson('az', ['ad', 'app', 'credential', 'reset', '--id', clientId, '--display-name', 'github-actions-journey-e2e', '--years', '1', '-o', 'json']);
      clientSecret = reset.password;
    }
  } else if (await confirm(`Create ${spName} with Contributor on ${scope}?`)) {
    const created = parseJson('az', ['ad', 'sp', 'create-for-rbac', '--name', spName, '--role', 'Contributor', '--scopes', scope, '--years', '1', '-o', 'json']);
    clientId = created.appId;
    clientSecret = created.password;
    tenantId = created.tenant || tenantId;
  } else {
    clientId = await ask('Existing service principal client ID', clientId);
    clientSecret = await askSecret('Existing service principal client secret', clientSecret);
  }

  const secretNames = parseJson('gh', ['secret', 'list', '--repo', repo, '--json', 'name']).map((item) => item.name);
  const existingCopilot = secretNames.includes('COPILOT_GITHUB_TOKEN');
  const copilotToken = await askSecret('Copilot GitHub token', process.env.COPILOT_GITHUB_TOKEN || '');
  for (const [name, value] of Object.entries({ AZURE_CLIENT_ID: clientId, AZURE_TENANT_ID: tenantId, AZURE_SUBSCRIPTION_ID: subscriptionId })) {
    if (!value) throw new Error(`${name} is required`);
    run('gh', ['variable', 'set', name, '--body', value, '--repo', repo]);
  }
  if (!clientSecret) throw new Error('AZURE_CLIENT_SECRET is required');
  run('gh', ['secret', 'set', 'AZURE_CLIENT_SECRET', '--repo', repo], { input: clientSecret });
  if (copilotToken) run('gh', ['secret', 'set', 'COPILOT_GITHUB_TOKEN', '--repo', repo], { input: copilotToken });
  else if (!existingCopilot) throw new Error('COPILOT_GITHUB_TOKEN is required when the repository has no existing secret');

  console.log('PASS: repository variables and secrets configured.');
  console.log('Next: gh variable list --repo <owner/repo>; gh secret list --repo <owner/repo>');
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exitCode = 1;
} finally {
  rl.close();
}
