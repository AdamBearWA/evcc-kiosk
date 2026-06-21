# Kiosk UI screenshot

Regenerates `docs/screenshot.png` (shown in the top-level README) by rendering the real
`kiosk/index.html` in a headless browser with representative sample data injected — no running
device or live EVCC instance needed.

## Usage

From this directory:

```
npm install
npx playwright install chromium    # one-time: downloads the headless browser
npm run shot                       # the live dashboard  -> ../../docs/screenshot.png
npm run shot:connecting            # the connecting state -> ../../docs/screenshot-connecting.png
```

Both render at 600×1024 (the portrait panel size) at 2× scale. `shot:connecting` stubs the
websocket so no frame ever arrives, capturing the "Connecting to EVCC…" overlay.

To change what the screenshot shows, edit the `sample` object in `shot.mjs` — it's the flat,
dotted-key shape the page consumes over its websocket (e.g. `loadpoints.0.vehicleSoc`).

## How it works

The page is loaded over `file://` with its `WebSocket` and `/api/sessions` `fetch` stubbed, so it
renders fully populated and deterministically. The page's own rendering code runs unchanged.

## Headless Linux note

If Chromium fails to launch with a missing-library error (e.g. `libnspr4.so`), install its system
dependencies:

```
npx playwright install --with-deps chromium   # needs sudo
```

Without sudo, fetch the missing libraries into a local directory and point `LD_LIBRARY_PATH` at
them:

```
apt-get download libnspr4 libnss3
dpkg-deb -x libnspr4_*.deb libs/ && dpkg-deb -x libnss3_*.deb libs/
LD_LIBRARY_PATH="$PWD/libs/usr/lib/x86_64-linux-gnu" npm run shot
```
