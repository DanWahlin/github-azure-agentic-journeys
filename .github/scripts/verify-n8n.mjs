#!/usr/bin/env node
import { azdValue, main, poll, request } from './_utils.mjs';

main(async () => {
  console.log('=== verify-n8n ===');
  const url = azdValue('N8N_URL');
  await poll(`${url}/healthz`);
  const response = await request(url, { timeoutMs: 60000 });
  const html = await response.text();
  if (response.status !== 200) throw new Error(`n8n UI returned HTTP ${response.status}; HTTP 401 is not accepted`);
  if (!/n8n/i.test(html)) throw new Error('n8n UI response did not contain the expected n8n marker');
  console.log('PASS: /healthz and UI returned HTTP 200');
  console.log(`Open: ${url}`);
});
