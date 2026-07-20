#!/usr/bin/env node
import { asArray, azdValue, jsonRequest, main, request } from './_utils.mjs';

function absolute(base, path) {
  return new URL(path, `${base}/`).toString();
}

main(async () => {
  console.log('=== verify-aimarket ===');
  const api = azdValue('API_URL');
  const web = azdValue('WEB_URL');
  await jsonRequest(`${api}/api/health`);
  const { data: productPayload } = await jsonRequest(`${api}/api/products`);
  const products = asArray(productPayload);
  if (products.length !== 10) throw new Error(`Expected 10 products, received ${products.length}`);
  for (const product of products) {
    if (!product.imageUrl) throw new Error(`${product.id ?? product.name} has no imageUrl`);
    const image = await request(product.imageUrl, { timeoutMs: 30000 });
    if (!image.ok || !(image.headers.get('content-type') ?? '').startsWith('image/')) {
      throw new Error(`${product.id ?? product.name} image failed: HTTP ${image.status}`);
    }
  }
  const { data: searchPayload } = await jsonRequest(`${api}/api/products/search`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ query: 'budget friendly electronics' }),
  });
  if (asArray(searchPayload, ['data', 'items', 'products', 'results']).length === 0) throw new Error('Semantic search returned no products');
  const { data: chatPayload } = await jsonRequest(`${api}/api/chat`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ messages: [{ role: 'user', content: 'What laptops do you have?' }] }), timeoutMs: 120000,
  });
  if (chatPayload?.role !== 'assistant' || typeof chatPayload?.content !== 'string') {
    throw new Error('Chat response did not match the required assistant message shape');
  }
  if (!chatPayload.content.toLowerCase().includes('ultrabook pro 15')) {
    throw new Error('Chat response did not mention the catalog product UltraBook Pro 15');
  }
  const page = await request(web, { timeoutMs: 60000 });
  const html = await page.text();
  if (page.status !== 200) throw new Error(`Storefront returned HTTP ${page.status}`);
  const sources = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map((match) => match[1]);
  if (sources.length === 0) throw new Error('No JavaScript assets found in storefront HTML');
  const apiHost = new URL(api).host;
  let integrated = false;
  for (const source of sources.slice(0, 10)) {
    const asset = await request(absolute(web, source), { timeoutMs: 60000 });
    if (asset.ok && (await asset.text()).includes(apiHost)) { integrated = true; break; }
  }
  if (!integrated) throw new Error(`Storefront assets don't reference production API host ${apiHost}`);
  console.log('PASS: health, 10 products, images, search, chat, storefront, and API integration');
});
