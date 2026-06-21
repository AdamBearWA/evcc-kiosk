// Renders the real kiosk page (kiosk/index.html) to docs/screenshot.png for the README.
// The page is loaded over file:// with its websocket and /api/sessions fetch stubbed, so it
// renders fully populated and deterministically - no running device or live EVCC needed.
//
// Usage (from tools/screenshot/):  npm install && npx playwright install chromium && npm run shot
// Optional args:                   node shot.mjs [path/to/index.html] [path/to/out.png]

import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const target = process.argv[2] || path.join(repoRoot, 'kiosk', 'index.html');
const out = process.argv[3] || path.join(repoRoot, 'docs', 'screenshot.png');

// Representative "charging on solar" scene, in the flat dotted-key shape the page consumes over
// its websocket. Edit these values to change what the screenshot shows.
const sample = {
  siteTitle: 'EVCC', currency: 'USD', tariffGrid: 0.30, tariffFeedIn: 0.08,
  statistics: { '30d': { solarPercentage: 80 } },
  pvPower: 4100, homePower: 650,
  grid: { power: -1200 },                            // negative = exporting
  battery: { power: -900, soc: 75, capacity: 10.0 }, // negative = charging
  'loadpoints.0.title': 'Charger',
  'loadpoints.0.vehicleTitle': 'Sample Vehicle',
  'loadpoints.0.connected': true,
  'loadpoints.0.charging': true,
  'loadpoints.0.mode': 'pv',
  'loadpoints.0.chargePower': 7400,
  'loadpoints.0.vehicleSoc': 62,
  'loadpoints.0.effectiveLimitSoc': 80,
  'loadpoints.0.vehicleRange': 300,
  'loadpoints.0.sessionEnergy': 4200,                // Wh
  'loadpoints.0.pvAction': 'enable'
};

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 600, height: 1024 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();

await page.addInitScript((sample) => {
  // Fake websocket: connects, then pushes one snapshot frame.
  class FakeWS {
    constructor() {
      this.readyState = 1;
      setTimeout(() => {
        this.onopen && this.onopen();
        this.onmessage && this.onmessage({ data: JSON.stringify(sample) });
      }, 10);
    }
    send() {} close() {}
  }
  window.WebSocket = FakeWS;
  // Stub fetch: /api/sessions returns one finished session today; anything else is a no-op.
  window.fetch = (url) => {
    if (('' + url).includes('/api/sessions')) {
      const today = new Date().toISOString();
      return Promise.resolve({ json: () => Promise.resolve([{ created: today, finished: today, chargedEnergy: 6.1 }]) });
    }
    return Promise.resolve({ ok: true, json: () => Promise.resolve('pv') });
  };
}, sample);

await page.goto('file://' + target);
await page.waitForTimeout(700);
await page.screenshot({ path: out });
await browser.close();
console.log('wrote ' + out);
