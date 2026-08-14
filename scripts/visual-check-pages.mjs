#!/usr/bin/env node

import { mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright-core';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = process.env.PAGES_SCREENSHOT_DIR || '/tmp/dsh-computer-use-pages';
const executablePath = process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const pages = [
  { name: 'product', url: pathToFileURL(resolve(root, 'docs/index.html')).href, requiresHeroImage: true },
  { name: 'distribution', url: pathToFileURL(resolve(root, 'docs/distribution.html')).href, requiresHeroImage: false },
];
const viewports = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'mobile', width: 390, height: 844 },
];

await mkdir(outputDir, { recursive: true });
const browser = await chromium.launch({ executablePath, headless: true });

try {
  for (const pageTarget of pages) {
    for (const viewport of viewports) {
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
        deviceScaleFactor: 1,
      });
      const page = await context.newPage();
      await page.goto(pageTarget.url, { waitUntil: 'load' });
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(300);

      const report = await page.evaluate(() => {
        const visible = (element) => {
          const style = getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
        };
        const offenders = Array.from(document.querySelectorAll('body *'))
          .filter(visible)
          .map((element) => ({ element, rect: element.getBoundingClientRect() }))
          .filter(({ element, rect }) => {
            const intentionallyScrollable = element.closest('.code-block pre, .result-line');
            return !intentionallyScrollable && (rect.left < -1 || rect.right > window.innerWidth + 1);
          })
          .slice(0, 10)
          .map(({ element, rect }) => ({
            tag: element.tagName.toLowerCase(),
            className: element.className,
            left: Math.round(rect.left),
            right: Math.round(rect.right),
          }));
        const icon = document.querySelector('.brand img');
        const hero = document.querySelector('.hero');
        const heading = document.querySelector('h1');
        return {
          scrollWidth: document.documentElement.scrollWidth,
          viewportWidth: window.innerWidth,
          offenders,
          iconLoaded: Boolean(icon && icon.complete && icon.naturalWidth > 0),
          heroHasProductImage: Boolean(hero && getComputedStyle(hero).backgroundImage.includes('setup-center.png')),
          heading: heading ? heading.getBoundingClientRect().toJSON() : null,
        };
      });

      const label = `${pageTarget.name}/${viewport.name}`;
      if (report.scrollWidth > report.viewportWidth + 1) {
        throw new Error(`${label}: horizontal overflow ${report.scrollWidth}px > ${report.viewportWidth}px`);
      }
      if (report.offenders.length) {
        throw new Error(`${label}: elements escape viewport: ${JSON.stringify(report.offenders)}`);
      }
      if (!report.iconLoaded || !report.heading) {
        throw new Error(`${label}: primary product identity did not render`);
      }
      if (pageTarget.requiresHeroImage && !report.heroHasProductImage) {
        throw new Error(`${label}: product image did not render in hero`);
      }

      if (viewport.name === 'mobile' && await page.locator('#navToggle').count()) {
        await page.locator('#navToggle').click();
        const menuState = await page.locator('#navLinks').evaluate((element) => ({
          open: element.classList.contains('open'),
          rect: element.getBoundingClientRect().toJSON(),
        }));
        if (!menuState.open || menuState.rect.right > viewport.width + 1) {
          throw new Error(`${label}: navigation menu did not open within viewport`);
        }
        await page.keyboard.press('Escape');
      }

      await page.screenshot({
        path: resolve(outputDir, `${pageTarget.name}-${viewport.name}.png`),
        fullPage: true,
      });
      console.log(`${label}: ${report.viewportWidth}px wide, no overflow, identity loaded`);
      await context.close();
    }
  }
} finally {
  await browser.close();
}

console.log(`Screenshots: ${outputDir}`);
