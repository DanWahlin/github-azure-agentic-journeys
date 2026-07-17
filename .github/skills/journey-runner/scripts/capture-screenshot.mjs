#!/usr/bin/env node

import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { chromium } from 'playwright';

const args = process.argv.slice(2);
function value(name, fallback) {
  const index = args.indexOf(`--${name}`);
  return index === -1 ? fallback : args[index + 1];
}

const url = value('url');
const output = value('output');
if (!url || !output) {
  console.error('Usage: node capture-screenshot.mjs --url <url> --output <png> [login options]');
  process.exit(2);
}

const username = value('username');
const password = value('password');
const usernameSelector = value('username-selector');
const passwordSelector = value('password-selector');
const submitSelector = value('submit-selector');
const successPath = value('success-path');
const failOnResourceErrors = value('fail-on-resource-errors', 'false') === 'true';
const outputPath = resolve(output);
mkdirSync(dirname(outputPath), { recursive: true });

const failedResources = [];
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('response', (response) => {
    const type = response.request().resourceType();
    if (response.status() >= 400 && ['document', 'image', 'script', 'xhr', 'fetch'].includes(type)) {
      failedResources.push({ status: response.status(), type, url: response.url() });
    }
  });

  const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  if (!response || response.status() >= 400) {
    throw new Error(`Navigation failed with HTTP ${response?.status() ?? 'no response'}`);
  }

  if (username || password) {
    if (!username || !password || !usernameSelector || !passwordSelector || !submitSelector) {
      throw new Error('Login requires username, password, username-selector, password-selector, and submit-selector');
    }
    await page.locator(usernameSelector).fill(username);
    await page.locator(passwordSelector).fill(password);
    await page.locator(submitSelector).click();
    if (successPath) {
      await page.waitForURL((current) => current.pathname.includes(successPath), { timeout: 60000 });
    }
  }

  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await page.screenshot({ path: outputPath, fullPage: true });

  console.log(`Screenshot: ${outputPath}`);
  if (failedResources.length > 0) {
    console.log('Failed browser resources:');
    for (const item of failedResources) {
      console.log(`- HTTP ${item.status} ${item.type} ${item.url}`);
    }
    if (failOnResourceErrors) process.exitCode = 1;
  } else {
    console.log('Failed browser resources: none');
  }
} finally {
  await browser.close();
}
