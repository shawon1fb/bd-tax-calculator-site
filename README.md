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

> **Full step-by-step guide, env reference and troubleshooting:
> [`deploy/README.md`](deploy/README.md).** The summary below is the short version.

```
Dockerfile              # nginx:alpine + the static files
nginx.conf              # server block (try_files, gzip, app-ads.txt as text/plain)
docker-compose.yml      # local: builds from source, http://localhost:8089
docker-compose.prod.yml # server: runs the image pulled from Docker Hub
scripts/docker-publish.sh          # build (linux/amd64) + push to Docker Hub
deploy/.env.example                # SSH creds + domain + image tag + network
deploy/Caddyfile                   # reverse proxy: taxhelperbd.com → bd-tax-site:80
deploy/scripts/provision.sh        # one-time: prepare a fresh VPS (from your Mac)
deploy/scripts/provision-vps.sh    #   ↳ what runs ON the server (piped in over SSH)
deploy/scripts/remote-deploy.sh    # server pulls the image + restarts
deploy/scripts/remote-proxy.sh     # ship Caddyfile + run/reload Caddy (HTTPS)
deploy/scripts/health.sh           # end-to-end health check (container → TLS → pages)
```

Server `165.99.219.35`, domain `taxhelperbd.com` — the A record must point there
and ports 80 + 443 be open before Caddy can issue a cert. No host port is
published for the site itself; Caddy reaches it by service name (`bd-tax-site`)
over the `bd-tax-network` docker network.

### Local

```bash
docker compose up -d --build   # → http://localhost:8089
docker compose down
```

### First time (once per server)

```bash
cp deploy/.env.example deploy/.env    # fill in host, domain, DEPLOY_ROOT_PASSWORD
bash deploy/scripts/provision.sh      # docker + `deploy` user + your SSH key + swap + ufw
```

`provision.sh` logs in as root (password from `deploy/.env`, via `sshpass`) and
pipes `provision-vps.sh` into the box. It creates a **password-less** `deploy`
user reachable only by the SSH key it installs — generating `~/.ssh/id_ed25519`
first if you have none. Idempotent; re-run any time. Afterwards clear
`DEPLOY_ROOT_PASSWORD` from `deploy/.env` and rotate the root password.

### Every release

```bash
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
  `docker-compose.prod.yml`, then verifies with an in-network curl and appends to
  `.deploy-history`. Rollback = deploy an older tag:
  `bash deploy/scripts/remote-deploy.sh 0.0.1`.

### HTTPS / reverse proxy

```bash
bash deploy/scripts/remote-proxy.sh          # add / refresh this site's route
bash deploy/scripts/remote-proxy.sh reload   # after editing deploy/caddy-site.snippet
bash deploy/scripts/remote-proxy.sh show     # print the live Caddyfile
bash deploy/scripts/remote-proxy.sh down     # remove ONLY taxhelperbd.com's route
```

The same Caddy container also fronts **debtbooktracker.com** on this box, so the
live Caddyfile is assembled — `deploy/Caddyfile` (global options) + other sites'
marked blocks + `deploy/caddy-site.snippet` (this site's block) — validated, then
applied with `caddy reload`. No container recreate, no downtime for either site,
and deploying one site can't delete the other's route. Certs live in the
`caddy_data` volume. Ordinary content redeploys never need this — only a Caddy
config change does. Details: [deploy/README.md](deploy/README.md).

```caddyfile
# >>> bd-tax-calculator … >>>
taxhelperbd.com {
	encode gzip
	header /app-ads.txt Content-Type "text/plain; charset=utf-8"
	reverse_proxy bd-tax-site:80
}
# <<< bd-tax-calculator <<<
```

The `www.` block in `deploy/caddy-site.snippet` is commented out on purpose —
enable it only once `www.taxhelperbd.com` has its own A record, otherwise Caddy
retries ACME forever.

Then the App Store Connect URLs become `https://taxhelperbd.com/`,
`/privacy.html`, `/support.html`.

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
