# BD Tax Calculator — Website

**Live:** https://shawon1fb.github.io/bd-tax-calculator-site/

Marketing + legal pages for the **BD Tax Calculator** iOS app, used for App Store submission.

| Page | File | App Store field |
|---|---|---|
| Landing | `index.html` | Marketing URL |
| Privacy Policy | `privacy.html` | Privacy Policy URL (**required**) |
| Support + FAQ | `support.html` | Support URL (**required**) |

Static HTML/CSS/JS — no build step. Bilingual (English / বাংলা) via a language toggle; the choice persists in `localStorage`. Light and dark themes follow the OS setting.

The landing page has a floating 3-phone hero mockup, a scrolling tax-year ticker, count-up stats, and scroll-reveal animation on sections/cards (`assets/screenshots/*.png` — real app screenshots, resized to 414px wide with `sips`). Everything respects `prefers-reduced-motion`.

## Deploy (GitHub Pages)

1. Push this repo to GitHub.
2. Settings → Pages → Source: `Deploy from a branch` → `main` / `root`.
3. Pages will serve at `https://shawon1fb.github.io/bd-tax-calculator-site/`.
4. Use these URLs in App Store Connect:
   - Privacy Policy URL → `.../privacy.html`
   - Support URL → `.../support.html`
   - Marketing URL → `.../` (index)

## Before you publish — fill these in

- **Support email:** currently `contact.marufalam@gmail.com` in `privacy.html` and `support.html`. Change it if you want a different public contact.
- **App icon:** the real iOS app icon (`assets/app-icon-*.png`), pulled from the Xcode project's `AppIcon.appiconset/AppIcon.png` and resized with `sips` (32/64/96/180/512, plus the untouched 1024 source). Used for favicon, apple-touch-icon, og:image, and the nav/footer brand mark. Re-run the resize if the app icon changes:
  ```sh
  SRC="path/to/AppIcon.png"
  sips -Z 512 "$SRC" --out assets/app-icon-512.png
  sips -Z 180 "$SRC" --out assets/app-icon-180.png
  sips -Z 96  "$SRC" --out assets/app-icon-96.png
  sips -Z 64  "$SRC" --out assets/app-icon-64.png
  sips -Z 32  "$SRC" --out assets/app-icon-32.png
  ```
- **App Store link:** the "Download on the App Store" buttons in `index.html` point to `#`. Replace with the real App Store URL once the app is live (there are two: the hero button and the closing CTA).
- **Last updated date** in `privacy.html` — bump when you change the policy.

## Notes

- The privacy policy reflects the shipping app: Google AdMob ads + Firebase Cloud Messaging push, no account, tax inputs kept on device, TIN lookups sent to NBR only on request. Keep it in sync if those change.
- Includes the NBR non-affiliation disclaimer required for a tax tool that queries a government service.
