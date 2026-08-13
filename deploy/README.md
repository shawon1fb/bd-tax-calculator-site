# Deploy guide — bd-tax-calculator-site

How this site gets from your Mac to `https://taxhelperbd.com`.

**Model:** you build the Docker image locally, push it to Docker Hub, the server
pulls it. **Nothing is ever built on the server** — no git clone there, no source
code, no node/npm. Caddy sits in front and handles HTTPS.

```
  your Mac                     Docker Hub                     VPS 165.99.219.35
┌──────────────┐            ┌────────────────┐            ┌────────────────────────┐
│ docker-      │  push      │ shawon1fb/     │   pull     │  ┌──────────────────┐  │
│ publish.sh   │ ─────────► │ bd-tax-        │ ◄───────── │  │ bd-tax-caddy     │  │
│              │            │ calculator-    │            │  │ :80 :443  (TLS)  │  │
│ remote-      │  ssh       │ site:<tag>     │            │  └────────┬─────────┘  │
│ deploy.sh    │ ─────────────────────────────────────►   │           │ bd-tax-    │
│              │  DOCKER_HOST=ssh://deploy@host           │           │ network    │
│ remote-      │            └────────────────┘            │  ┌────────▼─────────┐  │
│ proxy.sh     │                                          │  │ bd-tax-          │  │
└──────────────┘                                          │  │ calculator-site  │  │
                                                          │  │ nginx :80        │  │
                                                          │  └──────────────────┘  │
                                                          └────────────────────────┘
```

The site container publishes **no host port**. Only Caddy is reachable from the
internet; it forwards to `bd-tax-site:80` by container name over the
`bd-tax-network` docker network.

---

## 0. Prerequisites

On your Mac:

- Docker Desktop running (`docker buildx` — ships with it)
- A Docker Hub account with push access to `shawon1fb/bd-tax-calculator-site`
- `sshpass` — **only** for the very first provision run:
  `brew install hudochenkov/sshpass/sshpass`

DNS (do this first — TLS can't be issued without it):

```bash
dig +short taxhelperbd.com      # must print 165.99.219.35
```

If it doesn't, add an `A` record at your registrar and wait for propagation.
Don't run the proxy script before this resolves — Caddy will hammer Let's
Encrypt and get rate-limited.

---

## 1. Configure (once)

```bash
cp deploy/.env.example deploy/.env
```

Open `deploy/.env` and set:

| Key | Value | Used by |
|---|---|---|
| `DEPLOY_SSH_HOST` | `165.99.219.35` | all scripts |
| `DEPLOY_SSH_USER` | `deploy` — created by provisioning | all scripts |
| `DEPLOY_SSH_PORT` | `22` | all scripts |
| `DEPLOY_PROVISION_USER` | `root` | `provision.sh` |
| `DEPLOY_ROOT_PASSWORD` | the root password (temporary) | `provision.sh` |
| `DEPLOY_DOMAIN` | `taxhelperbd.com` | `remote-proxy.sh`, Caddyfile |
| `DEPLOY_ACME_EMAIL` | your email, for cert-expiry notices | Caddyfile |
| `DEPLOY_IMAGE_REPO` | `shawon1fb/bd-tax-calculator-site` | publish + deploy |
| `DEPLOY_TAG` | `latest` — auto-bumped on each publish | `remote-deploy.sh` |
| `DEPLOY_NETWORK` | `bd-tax-network` | deploy + proxy |
| `CADDY_CONTAINER` | `bd-tax-caddy` | `remote-proxy.sh` |

`deploy/.env` is gitignored. Never commit it.

---

## 2. Provision the server (once per box)

```bash
bash deploy/scripts/provision.sh
```

Logs in as `root` (key first, else the password via `sshpass`) and pipes
`provision-vps.sh` into the box, which:

1. installs Docker Engine + the compose plugin
2. creates the **password-less** `deploy` user, in the `docker` group
3. installs your `~/.ssh/id_ed25519.pub` into its `authorized_keys`
   (generates the key first if you don't have one)
4. adds a 2 GB swapfile if the box has none
5. opens ufw for SSH + 80 + 443, denies everything else

Idempotent — safe to re-run. Verify:

```bash
ssh deploy@165.99.219.35 'docker --version && id'
```

**Right after this succeeds:** blank `DEPLOY_ROOT_PASSWORD` in `deploy/.env` and
rotate the root password on the server (`passwd` as root). The scripts only ever
need the key from here on.

---

## 3. Publish the image

```bash
bash scripts/docker-publish.sh          # auto-version: highest Hub tag + 1
bash scripts/docker-publish.sh 0.2.0    # or pin a version
bash scripts/docker-publish.sh -y       # skip the confirm prompt
```

- Cross-builds `linux/amd64` via buildx, so an Apple-Silicon Mac produces an
  image the x86_64 VPS can actually run.
- Pushes three tags: `<version>`, `<git-sha>`, `latest`.
- Bumps `DEPLOY_TAG` in `deploy/.env` to the version it just pushed.
- Prompts for `docker login` if you aren't logged in.

---

## 4. Deploy it

```bash
bash deploy/scripts/remote-deploy.sh          # uses DEPLOY_TAG from deploy/.env
bash deploy/scripts/remote-deploy.sh 0.1.4    # or an explicit tag
```

Points the **local** Docker CLI at the server's daemon (`DOCKER_HOST=ssh://…`),
creates `bd-tax-network` if missing, then `compose pull` + `up -d` with
`docker-compose.prod.yml`. Verifies by curling `http://bd-tax-site:80/` from a
throwaway container on the same network (there's no host port to curl), and
appends the tag + timestamp to `.deploy-history`.

Fails loudly with the last 50 log lines if the check doesn't hit 200.

---

## 5. HTTPS (once, then only on Caddy config changes)

```bash
bash deploy/scripts/remote-proxy.sh
```

### One proxy, several sites

This box also serves **debtbooktracker.com** (repo `debtbook-legal`) through the
same `bd-tax-caddy` container — only one process can bind ports 80/443. So the
live Caddyfile (`~/bd-tax-caddy/Caddyfile`) is **assembled**, never overwritten:

```
  deploy/Caddyfile           global options only (ACME email)
+ other sites' blocks        copied from the live file, e.g. the debtbook one
+ deploy/caddy-site.snippet  this site's block, between its own markers
```

Each site owns one `# >>> <name> >>> … # <<< <name> <<<` block and rewrites only
that one, so deploying taxhelperbd.com can no longer delete debtbooktracker.com's
route (the old script scp'd its whole Caddyfile over the live one and recreated
the container — which did exactly that).

A **running** container is never recreated: the assembled file is checked with
`caddy validate` inside the container and applied with `caddy reload` — an
in-process config swap, so no dropped connections and no certificate re-issue.
On failure the previous file is restored automatically. A container is started
only when none is running. Certificates live in the `caddy_data` volume and
survive recreation. A timestamped `.bak` is kept server-side (10 newest).

Re-running is idempotent — the file is rebuilt from scratch every time, so
repeated deploys never accumulate blocks or blank lines.

```bash
bash deploy/scripts/remote-proxy.sh reload   # after editing the snippet — zero downtime
bash deploy/scripts/remote-proxy.sh show     # print the live Caddyfile
bash deploy/scripts/remote-proxy.sh down     # remove ONLY taxhelperbd.com's block
```

`down` no longer kills the proxy (that would take debtbooktracker.com down too).
To stop everything: `docker rm -f bd-tax-caddy`.

Bind mounts resolve on the **Docker host** (the server), not your Mac — that's
why the files are shipped over first rather than mounted from `$(pwd)`.

**Where the site block lives:** `deploy/caddy-site.snippet`, not
`deploy/Caddyfile`. `__DOMAIN__` in the snippet is replaced with `DEPLOY_DOMAIN`
before shipping.

Give it ~30 s for the certificate, then:

```bash
curl -I https://taxhelperbd.com/
curl -s https://taxhelperbd.com/app-ads.txt
```

---

## Health check

```bash
bash deploy/scripts/health.sh          # full report
bash deploy/scripts/health.sh --quiet  # only failures — for cron/CI, exit 1 on any failure
```

Checks, end to end:

| # | Check | Fails when |
|---|---|---|
| 1 | Docker reachable over SSH | server down, key broken |
| 2 | `bd-tax-calculator-site` running + docker `HEALTHCHECK` status | container crashed / nginx dead |
| 3 | `http://bd-tax-site/healthz` from inside the network | nginx not answering, wrong network |
| 4 | `bd-tax-caddy` running | proxy never started |
| 5 | DNS resolves to the server IP | record changed / not propagated |
| 6 | `http://` redirects to `https://` | Caddy misconfigured |
| 7 | `/`, `/privacy.html`, `/support.html`, `/app-ads.txt`, `/healthz` over HTTPS | pages missing, bad build |
| 8 | TLS certificate expiry (warn <21 days, fail <7) | renewal broken |
| 9 | Server disk usage (warn ≥75%, fail ≥90%) | images piling up — `docker system prune -af` |

The image itself ships a `HEALTHCHECK` (`wget /healthz` every 30 s), so
`docker ps` shows `healthy`/`unhealthy` on its own, and `remote-deploy.sh` waits
for `healthy` before it declares the deploy good.

`/healthz` returns a plain `ok` straight from nginx — no filesystem access, and
it's kept out of the access log.

Cron it on your Mac if you want to be told when the site goes down:

```bash
# crontab -e — every 15 min, only mails/prints on failure
*/15 * * * * cd /path/to/bd-tax-calculator-site && bash deploy/scripts/health.sh --quiet
```

## Day-to-day: content change → live

Edit HTML/CSS, then:

```bash
bash scripts/docker-publish.sh -y
bash deploy/scripts/remote-deploy.sh
```

Two commands. Caddy and the proxy config are untouched.

## Rollback

Deploy any older tag — images stay on Docker Hub:

```bash
cat .deploy-history                            # what was deployed, when
bash deploy/scripts/remote-deploy.sh 0.1.3
```

---

## Troubleshooting

**`… is not answering (TCP connect timed out)` / `Operation timed out`**
The box is unreachable at the network level — no credential will help. Confirm
with `nc -vz <ip> 22` and `ping -c3 <ip>`. A *refused* connection means the host
is alive but nothing listens; a *timeout* means packets are dropped: VM off, not
finished building, IP not routed yet, or a provider firewall. Fix it in the
provider panel (power state, firewall/security group allowing 22/80/443) and use
its VNC console to check `ip a`, `systemctl status ssh`, `ufw status`.

**`Can't SSH to deploy@… with a key`**
Provisioning hasn't run, or your key changed. Re-run `provision.sh`, or
`ssh-copy-id deploy@165.99.219.35`.

**`Docker not reachable on …`**
Docker isn't installed/running on the box, or the `deploy` user isn't in the
`docker` group. `ssh deploy@host 'docker ps'` to confirm; re-run `provision.sh`.

**Deploy verify fails (HTTP 000 / 502)**
The image started but nginx isn't serving. Check logs:
```bash
DOCKER_HOST=ssh://deploy@165.99.219.35 docker logs --tail=50 bd-tax-calculator-site
```

**Caddy serves 502**
The site container is down or not on `bd-tax-network`:
```bash
DOCKER_HOST=ssh://deploy@165.99.219.35 docker network inspect bd-tax-network
```
Re-run `remote-deploy.sh` — it attaches the container to that network.

**No certificate / `https` hangs**
DNS or the firewall. `dig +short taxhelperbd.com` must be the server IP, and 80
must be open (ACME's HTTP-01 challenge needs it). Watch Caddy:
```bash
DOCKER_HOST=ssh://deploy@165.99.219.35 docker logs -f bd-tax-caddy
```

**`Ports 80/443 already used by …`**
Another container (an old Caddy, nginx, Apache) holds them. Stop it, then
`bash deploy/scripts/remote-proxy.sh`.

**Wrong architecture (`exec format error`)**
The image was built for arm64. Always publish through `docker-publish.sh`, which
forces `--platform linux/amd64`.

---

## Useful one-liners

```bash
# what's running on the server
DOCKER_HOST=ssh://deploy@165.99.219.35 docker ps

# live nginx logs
DOCKER_HOST=ssh://deploy@165.99.219.35 docker logs -f bd-tax-calculator-site

# restart the site without redeploying
DOCKER_HOST=ssh://deploy@165.99.219.35 docker restart bd-tax-calculator-site

# disk cleanup on the server
DOCKER_HOST=ssh://deploy@165.99.219.35 docker system prune -af

# test the exact production image locally
docker run --rm -p 8089:80 shawon1fb/bd-tax-calculator-site:latest
```

## Security notes

- `deploy/.env` holds real credentials — gitignored, keep it that way.
- The `deploy` user has no password; SSH key only.
- Docker writes its own iptables rules, so a published port is reachable even if
  ufw would deny it. Only Caddy publishes ports here — keep it that way.
- Rotate the root password once provisioning is done, and blank
  `DEPLOY_ROOT_PASSWORD`.
