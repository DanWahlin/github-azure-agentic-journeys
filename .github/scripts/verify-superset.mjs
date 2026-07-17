#!/usr/bin/env node
import { azdValue, jsonRequest, main, request, run } from './_utils.mjs';

main(async () => {
  console.log('=== verify-superset ===');
  const pods = JSON.parse(run('kubectl', ['get', 'pods', '-n', 'superset', '-o', 'json']).stdout);
  const items = pods.items ?? [];
  if (items.length === 0) throw new Error('No pods found in namespace superset');
  for (const pod of items) {
    const statuses = pod.status?.containerStatuses ?? [];
    if (pod.status?.phase !== 'Running' || statuses.length === 0 || statuses.some((item) => !item.ready)) {
      throw new Error(`Pod ${pod.metadata?.name} is not fully Ready/Running`);
    }
  }
  const pod = items[0].metadata.name;
  const initLogs = run('kubectl', ['logs', '-n', 'superset', pod, '-c', 'superset-init'], { allowFailure: true }).stdout;
  const appLogs = run('kubectl', ['logs', '-n', 'superset', pod, '-c', 'superset'], { allowFailure: true }).stdout;
  const logs = `${initLogs}\n${appLogs}`;
  if (/SQLiteImpl|sqlite:\/{3,4}/i.test(logs)) throw new Error('SQLite fallback detected in Superset logs');
  if (!/PostgresqlImpl|postgresql:\/\/|postgres:\/\//i.test(logs)) throw new Error('No PostgreSQL evidence found in Superset logs');
  const url = azdValue('SUPERSET_URL');
  const response = await request(`${url}/health`, { timeoutMs: 60000 });
  if (response.status !== 200) throw new Error(`/health returned HTTP ${response.status}`);
  console.log(`PASS: ${items.length} pod(s) Ready/Running, PostgreSQL confirmed, /health HTTP 200`);
  console.log(`Open: ${url}`);
});
