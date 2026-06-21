// Renders the real kiosk page (kiosk/index.html) to docs/screenshot.png for the README.
// The page is loaded over file:// with its websocket and /api/sessions fetch stubbed, so it
// renders fully populated and deterministically - no running device or live EVCC needed.
//
// Usage (from tools/screenshot/):  npm install && npx playwright install chromium
//   Live dashboard (default):      npm run shot              -> docs/screenshot.png
//   Connecting overlay:            npm run shot:connecting   -> docs/screenshot-connecting.png
// Optional positional args:        node shot.mjs [--connecting] [path/to/index.html] [out.png]

import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const argv = process.argv.slice(2);
const connecting = argv.includes('--connecting'); // render the "Connecting to EVCC…" overlay instead
const positional = argv.filter((a) => !a.startsWith('--'));
const target = positional[0] || path.join(repoRoot, 'kiosk', 'index.html');
const out = positional[1] || path.join(repoRoot, 'docs', connecting ? 'screenshot-connecting.png' : 'screenshot.png');

// Representative "charging on solar" scene, in the flat dotted-key shape the page consumes over
// its websocket. Edit these values to change what the screenshot shows.
// Powers obey EVCC's balance: pv + grid + battery = home + charge
// (grid +import/-export, battery +discharge/-charge). Here a big solar day powers
// the car and battery and still exports: 10000 - 1400 - 1000 = 600 + 7000 = 7600 W.
const sample = {
  siteTitle: 'EVCC', currency: 'USD', tariffGrid: 0.30, tariffFeedIn: 0.08,
  statistics: { '30d': { solarPercentage: 80 } },
  pvPower: 10000, homePower: 600,
  grid: { power: -1400 },                             // negative = exporting
  battery: { power: -1000, soc: 75, capacity: 10.0 }, // negative = charging
  'loadpoints.0.title': 'Charger',
  'loadpoints.0.vehicleTitle': 'Sample Vehicle',
  'loadpoints.0.connected': true,
  'loadpoints.0.charging': true,
  'loadpoints.0.mode': 'pv',
  'loadpoints.0.chargePower': 7000,
  'loadpoints.0.vehicleSoc': 62,
  'loadpoints.0.effectiveLimitSoc': 80,
  'loadpoints.0.vehicleRange': 300,
  'loadpoints.0.sessionEnergy': 4200,                // Wh
  'loadpoints.0.pvAction': 'enable'
};

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 600, height: 1024 }, deviceScaleFactor: 2 });
const page = await ctx.newPage();

await page.addInitScript(({ sample, connecting }) => {
  if (connecting) {
    // Never delivers a frame, so the page keeps its "Connecting to EVCC…" overlay up.
    class DeadWS { constructor() { this.readyState = 0; } send() {} close() {} }
    window.WebSocket = DeadWS;
    window.fetch = () => new Promise(() => {});
    return;
  }
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
}, { sample, connecting });

await page.goto('file://' + target);
await page.waitForTimeout(700);
await page.screenshot({ path: out });
await browser.close();
console.log('wrote ' + out);
