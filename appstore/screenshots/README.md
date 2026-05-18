# PromoKit App Store Screenshots

A Next.js page that renders App Store screenshots for PromoKit and exports them at all four Apple-required iPhone resolutions.

## Drop your captures here

Save your iOS Simulator captures to:

```
public/screenshots/shelf.png    ← main shelf / app + offer list
public/screenshots/share.png    ← QR share card sheet
```

Capture at iPhone 16 Pro Max (1320×2868) in Simulator (Cmd+S). The captures are gitignored — real promo codes won't leak.

## Run

```bash
pnpm dev
```

Then open http://localhost:3000.

## Export

In the toolbar:

- **Export current size** — downloads both slides at the size selected in the dropdown
- **Export all 4 sizes** — downloads all 8 PNGs (2 slides × 4 sizes) ready for App Store Connect

Filenames are zero-padded so they sort correctly:

```
01-hero-1320x2868.png
02-share-1320x2868.png
01-hero-1284x2778.png
…
```

## What it does

- Renders each slide at the export resolution (no upscaling)
- Uses the iPhone mockup PNG and clips your captures inside the screen area
- Dark/moody developer-tool palette with App Store blue accent
- SF Pro / system stack for type
- Pre-loads images as data URIs to avoid blank exports
- Double-call to `html-to-image` so fonts and gradients render reliably

## Editing copy or layout

Everything is in `src/app/page.tsx`. Two slide components (`Slide1`, `Slide2`) with caption + phone composition. Edit the headlines or styling there.
