# BD Tax Calculator — Website

**Live (GitHub Pages):** https://shawon1fb.github.io/bd-tax-calculator-site/
**Self-hosted:** Docker + nginx behind Caddy on the VPS — see [Deploy](#deploy-vps-docker--caddy).

Marketing + legal pages for the **BD Tax Calculator** iOS app, used for App Store submission.

| Page | File | App Store field |
|---|---|---|
| Landing | `index.html` | Marketing URL |
| Privacy Policy | `privacy.html` | Privacy Policy URL (**required**) |
| Support + FAQ | `support.html` | Support URL (**required**) |

Static HTML/CSS/JS — no build step. Bilingual (English / বাংলা) via a language toggle; the choice persists in `localStorage`. Light and dark themes follow the OS setting.

The landing page has a floating 3-phone hero mockup, a scrolling tax-year ticker, count-up stats, and scroll-reveal animation on sections/cards (`assets/screenshots/*.png` — real app screenshots, resized to 414px wide with `sips`). Everything respects `prefers-reduced-motion`.

## Deploy (VPS, Docker + Caddy)

Same flow as `kickoff-marketing-site`: build an image locally, push it to Docker
Hub, then the server pulls that image. **Nothing is built on the server.**

```
Dockerfile              # nginx:alpine + the static files
nginx.conf              # server block (try_files, gzip, app-ads.txt as text/plain)
docker-compose.yml      # local: builds from source, http://localhost:8089
docker-compose.prod.yml # server: runs the image pulled from Docker Hub
scripts/docker-publish.sh    # build (linux/amd64) + push to Docker Hub
deploy/.env.example          # SSH creds + image tag + network
deploy/scripts/remote-deploy.sh  # server pulls the image + restarts
```

### Local

```bash
docker compose up -d --build   # → http://localhost:8089
docker compose down
```

### Publish → deploy

```bash
cp deploy/.env.example deploy/.env   # first time only — fill in SSH details

bash scripts/docker-publish.sh       # build (linux/amd64) + push to Docker Hub
bash deploy/scripts/remote-deploy.sh # server pulls that image + restarts
```

- **`scripts/docker-publish.sh`** — cross-builds `linux/amd64` via buildx (so an
  Apple-Silicon Mac produces an image the x86_64 VPS runs), pushes three tags
  (`<version>`, `<git-sha>`, `latest`) to `shawon1fb/bd-tax-calculator-site`, and
  bumps `DEPLOY_TAG` in `deploy/.env`. Version auto-increments from the highest
  semver tag on Hub; override explicitly: `bash scripts/docker-publish.sh 0.2.0`.
- **`deploy/scripts/remote-deploy.sh`** — points the local Docker CLI at the
  server over SSH (`DOCKER_HOST=ssh://…`), `compose pull` + `up -d` with
  `docker-compose.prod.yml`, then verifies with an in-network curl.
  Rollback = deploy an older tag: `bash deploy/scripts/remote-deploy.sh 0.0.1`.

Requires on the server: Docker, key-based SSH for the `deploy` user, and the
external network in `DEPLOY_NETWORK` (default `football-admin-backend-network`,
shared with Caddy) already existing — `docker network create <name>` if not.

### One-time proxy wiring

No host port is published; Caddy reaches the container by service name:

```caddyfile
bdtaxcalculator.app {
  reverse_proxy bd-tax-site:80
}
```

```bash
docker exec afc-caddy caddy reload --config /etc/caddy/Caddyfile
```

App Store Connect URLs then become `https://<domain>/`, `/privacy.html`,
`/support.html`.

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
