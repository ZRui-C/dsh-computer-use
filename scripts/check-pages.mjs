#!/usr/bin/env node

import { access, readFile, stat } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const docs = resolve(root, 'docs');
const [productHTML, distributionHTML, css, javascript] = await Promise.all([
  readFile(resolve(docs, 'index.html'), 'utf8'),
  readFile(resolve(docs, 'distribution.html'), 'utf8'),
  readFile(resolve(docs, 'style.css'), 'utf8'),
  readFile(resolve(docs, 'app.js'), 'utf8'),
]);
const html = `${productHTML}\n${distributionHTML}`;

const failures = [];
const requiredText = [
  'DSH Computer Use',
  'tech.zrui',
  'Universal 2',
  'computer_observe',
  'computer_action',
  'https://github.com/ZRui-C/dsh-computer-use',
  'brew tap zrui-c/tap',
  'brew trust zrui-c/tap',
  'brew install --cask dsh-computer-use',
  'data-dmg-link',
];
for (const text of requiredText) {
  if (!html.includes(text) && !javascript.includes(text)) {
    failures.push(`missing required text: ${text}`);
  }
}

for (const stale of ['DeepSeekComputerUseAgent', 'v0.1.0', 'pnpm install\nPackages: +312']) {
  if (html.includes(stale) || css.includes(stale) || javascript.includes(stale)) {
    failures.push(`stale product content: ${stale}`);
  }
}

for (const forbiddenStyle of ['linear-gradient(', 'radial-gradient(', 'letter-spacing: -']) {
  if (css.includes(forbiddenStyle)) failures.push(`forbidden site style: ${forbiddenStyle}`);
}

const localReferences = new Set();
for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
  const reference = match[1];
  if (reference.startsWith('#') || reference.startsWith('http:') || reference.startsWith('https:')) continue;
  localReferences.add(reference.split(/[?#]/, 1)[0]);
}
for (const match of css.matchAll(/url\(["']?([^"')]+)["']?\)/g)) {
  const reference = match[1];
  if (reference.startsWith('data:') || reference.startsWith('http:') || reference.startsWith('https:')) continue;
  localReferences.add(reference.split(/[?#]/, 1)[0]);
}

for (const reference of localReferences) {
  const target = resolve(docs, reference);
  if (!target.startsWith(docs)) {
    failures.push(`local reference escapes docs: ${reference}`);
    continue;
  }
  try {
    await access(target);
  } catch {
    failures.push(`missing local asset: ${reference}`);
  }
}

for (const image of ['assets/app-icon.png', 'assets/setup-center.png']) {
  const info = await stat(resolve(docs, image));
  if (info.size < 1024) failures.push(`image is unexpectedly small: ${image}`);
}

if (failures.length) {
  console.error(failures.map((failure) => `- ${failure}`).join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Pages validation passed (${localReferences.size} local assets checked).`);
}
