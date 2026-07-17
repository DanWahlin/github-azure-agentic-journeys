#!/usr/bin/env node
import { azdValue, jsonRequest, main } from './_utils.mjs';

main(async () => {
  console.log('=== verify-grafana ===');
  const url = azdValue('GRAFANA_URL');
  const { data } = await jsonRequest(`${url}/api/health`);
  if (data?.database !== 'ok') throw new Error(`/api/health database was ${JSON.stringify(data?.database)}, expected "ok"`);
  console.log(`PASS: ${url}/api/health returned HTTP 200 and database=ok`);
  console.log(`Open: ${url}`);
});
