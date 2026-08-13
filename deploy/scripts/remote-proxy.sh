#!/usr/bin/env bash
#
# Put HTTPS in front of the site — runs Caddy on the server, driven from the dev
# machine. Caddy fetches + renews a free Let's Encrypt certificate automatically.
#
#     bash deploy/scripts/remote-proxy.sh          # add / refresh this site's route
#     bash deploy/scripts/remote-proxy.sh reload   # same thing (alias)
#     bash deploy/scripts/remote-proxy.sh down     # remove ONLY this site's route
#     bash deploy/scripts/remote-proxy.sh show     # print the server's live Caddyfile
#
# ONE PROXY, SEVERAL SITES
# ------------------------
# This box also serves debtbooktracker.com through the same Caddy container —
# only one process can bind ports 80/443. So the live Caddyfile is *assembled*
# rather than overwritten:
#
#     deploy/Caddyfile            global options (email, …)
#   + other sites' marked blocks  copied straight from the live file
#   + deploy/caddy-site.snippet   this site's block, between its own markers
#
# Every site owns exactly one "# >>> <name> >>> … # <<< <name> <<<" block and
# rewrites only that one, so deploying one site never deletes another's route.
# (Before this, the script scp'd its whole Caddyfile over the live one and
# recreated the container — which silently dropped every other site.)
#
# Re-running is idempotent: the file is rebuilt from base + blocks every time,
# so nothing accumulates. A running container is NEVER recreated — the assembled
# file is validated inside the container and applied with `caddy reload`
# (in-process config swap: no dropped connections, no certificate re-issue).
# A container is started only when none is running.
#
# deploy/.env keys used:
#   DEPLOY_SSH_HOST / _USER / _PORT   how to reach the box
#   DEPLOY_DOMAIN                     the domain to serve, e.g. taxhelperbd.com (required)
#   DEPLOY_ACME_EMAIL                 email for Let's Encrypt notices (optional)
#   DEPLOY_NETWORK                    docker network shared with the site container
#   CADDY_CONTAINER                   proxy container name (default bd-tax-caddy)
#
# BEFORE running: point DEPLOY_DOMAIN's DNS A record at the server IP, and make
# sure ports 80 + 443 are open (provision-vps.sh opens them).
set -euo pipefail

cd "$(dirname "$0")/../.."

ENV_FILE="deploy/.env"
[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE not found."; exit 1; }
set -a; . "$ENV_FILE"; set +a

HOST="${DEPLOY_SSH_HOST:?set DEPLOY_SSH_HOST in deploy/.env}"
SSH_USER="${DEPLOY_SSH_USER:-deploy}"
SSH_PORT="${DEPLOY_SSH_PORT:-22}"
DOMAIN="${DEPLOY_DOMAIN:?set DEPLOY_DOMAIN in deploy/.env (e.g. taxhelperbd.com)}"
EMAIL="${DEPLOY_ACME_EMAIL:-}"
NAME="${CADDY_CONTAINER:-bd-tax-caddy}"
SITE_CONTAINER="bd-tax-calculator-site"
SITE_SERVICE="bd-tax-site"          # what the Caddyfile proxies to
NETWORK="${DEPLOY_NETWORK:-bd-tax-network}"
ACTION="${1:-up}"

MARK_BEGIN="# >>> bd-tax-calculator"
MARK_END="# <<< bd-tax-calculator <<<"

SSH_TARGET="${SSH_USER}@${HOST}"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

export DOCKER_HOST="ssh://${SSH_TARGET}:${SSH_PORT}"
docker version >/dev/null 2>&1 || { echo "❌ Can't reach Docker on the server. Provision first: bash deploy/scripts/provision.sh"; exit 1; }

running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

# Host path of the Caddyfile bind-mounted into the proxy container.
caddyfile_path() {
  docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy/Caddyfile"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null | tr -d '\r\n'
}

REMOTE_HOME="$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'echo "$HOME"')"
REMOTE_DIR="${REMOTE_HOME}/bd-tax-caddy"
CF_DEFAULT="${REMOTE_DIR}/Caddyfile"

CF="$CF_DEFAULT"
if running "$NAME"; then
  MOUNTED="$(caddyfile_path "$NAME")"
  [ -n "$MOUNTED" ] && CF="$MOUNTED"
fi

# ── show ──────────────────────────────────────────────────────────────────
if [ "$ACTION" = "show" ]; then
  echo "▶ ${CF}"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cat '${CF}'"
  exit 0
fi

# ── down: drop only this site's block, leave the proxy (and other sites) up ──
if [ "$ACTION" = "down" ]; then
  if ! running "$NAME"; then
    echo "Nothing to do — ${NAME} is not running."
    exit 0
  fi
  echo "▶ Removing the ${DOMAIN} block from ${NAME}:${CF}"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "CF='${CF}' B='${MARK_BEGIN}' E='${MARK_END}' bash -s" <<'REMOTE'
set -euo pipefail
cp "$CF" "${CF}.bak.$(date +%s)"
awk -v b="$B" -v e="$E" '
  index($0, b) == 1 { skip = 1 }
  skip == 0 { print }
  index($0, e) == 1 { skip = 0 }
' "$CF" > "${CF}.new"
mv "${CF}.new" "$CF"
ls -t "${CF}".bak.* 2>/dev/null | tail -n +11 | xargs -r rm -f || true
REMOTE
  docker exec "$NAME" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
  echo "✅ ${DOMAIN} removed from ${NAME}. Other sites untouched."
  echo "   Stop the proxy entirely (ALL sites go down): docker rm -f ${NAME}"
  exit 0
fi

# ── up / reload ───────────────────────────────────────────────────────────
docker network inspect "$NETWORK" >/dev/null 2>&1 || {
  echo "▶ Network ${NETWORK} missing — creating it"
  docker network create "$NETWORK" >/dev/null
}

# Bind mounts resolve on the Docker host (the server, via DOCKER_HOST=ssh://),
# NOT this machine — so ship the pieces to the server first.
TMP="$(mktemp -t bd-tax-caddy)"
sed "s|__DOMAIN__|${DOMAIN}|g" deploy/caddy-site.snippet > "$TMP"

echo "▶ Shipping deploy/Caddyfile + deploy/caddy-site.snippet → ${SSH_TARGET}:${REMOTE_DIR}/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_DIR}'"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -q deploy/Caddyfile "${SSH_TARGET}:${REMOTE_DIR}/base.caddy"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -q "$TMP" "${SSH_TARGET}:${REMOTE_DIR}/site.caddy"
rm -f "$TMP"

echo "▶ Assembling ${CF}  (global + other sites' blocks + ${DOMAIN})"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
  "CF='${CF}' DIR='${REMOTE_DIR}' B='${MARK_BEGIN}' bash -s" <<'REMOTE'
set -euo pipefail
# Both sites read-modify-write this one file. Serialise, so two deploys running
# at once can't drop each other's block.
exec 9>"${CF}.lock"
command -v flock >/dev/null 2>&1 && flock -w 30 9
BASE="${DIR}/base.caddy"; SNIP="${DIR}/site.caddy"; NEW="${CF}.new"; BAK=""

if [ -f "$CF" ]; then
  BAK="${CF}.bak.$(date +%s)"
  cp "$CF" "$BAK"
  echo "$BAK" > "${DIR}/.last-backup"
fi

cat "$BASE" > "$NEW"

if [ -n "$BAK" ]; then
  # Carry over every marked block that belongs to ANOTHER site.
  awk -v own="$B" '
    index($0, "# >>> ") == 1 { inblk = 1; buf = ""; mine = (index($0, own) == 1) }
    inblk { buf = buf $0 ORS }
    index($0, "# <<< ") == 1 { if (inblk && !mine) printf "%s", buf; inblk = 0 }
  ' "$BAK" >> "$NEW"

  # Anything outside a marked block is dropped — name those site addresses so a
  # hand-edited route cannot disappear silently.
  DROPPED="$(awk '
    index($0, "# >>> ") == 1 { inblk = 1 }
    index($0, "# <<< ") == 1 { inblk = 0; next }
    inblk { next }
    # top-level, non-comment, non-indented line opening a block — i.e. a site
    # address such as `example.com {` or `{$DEPLOY_DOMAIN:example.com} {`.
    # The global options block (a bare `{`) is not one.
    /\{[[:space:]]*$/ && $0 !~ /^[#[:space:]]/ && $0 !~ /^\{[[:space:]]*$/ { print "     " $0 }
  ' "$BAK")"
  if [ -n "$DROPPED" ]; then
    echo "  ⚠️  unmarked site block(s) in the old file were not carried over:"
    echo "$DROPPED"
    echo "     (expected once — the taxhelperbd.com block now lives in deploy/caddy-site.snippet)"
    echo "     backup: $BAK"
  fi
fi

printf '\n' >> "$NEW"
cat "$SNIP" >> "$NEW"
mv "$NEW" "$CF"

# Keep the 10 newest backups; deploys run often and these are tiny but endless.
ls -t "${CF}".bak.* 2>/dev/null | tail -n +11 | xargs -r rm -f || true
REMOTE

# ── start the proxy only if it isn't already running ──────────────────────
if running "$NAME"; then
  if ! docker exec "$NAME" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    echo "❌ Assembled Caddyfile is invalid — restoring the backup."
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cp \"\$(cat '${REMOTE_DIR}/.last-backup')\" '${CF}'"
    docker exec "$NAME" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile || true
    exit 1
  fi
  echo "▶ Reloading ${NAME} (zero downtime — other sites keep serving)"
  docker exec "$NAME" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
else
  BUSY="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ':(80|443)->' || true)"
  if [ -n "$BUSY" ]; then
    echo "❌ Ports 80/443 already used by another container:"
    echo "$BUSY"
    echo "   Set CADDY_CONTAINER in deploy/.env to that container and re-run."
    exit 1
  fi
  echo "▶ Starting Caddy (${DOMAIN}) → ${SITE_SERVICE}:80"
  docker rm -f "$NAME" >/dev/null 2>&1 || true   # remove a stopped leftover
  docker run -d --name "$NAME" \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 80:80 -p 443:443 \
    -e DEPLOY_DOMAIN="$DOMAIN" \
    ${EMAIL:+-e DEPLOY_ACME_EMAIL="$EMAIL"} \
    -v caddy_data:/data -v caddy_config:/config \
    -v "${CF}:/etc/caddy/Caddyfile:ro" \
    caddy:2 caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
fi

# The proxy must share the site's network to resolve ${SITE_SERVICE}.
if ! docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$NAME" | grep -qw "$NETWORK"; then
  echo "▶ Attaching ${NAME} to ${NETWORK}"
  docker network connect "$NETWORK" "$NAME"
fi

running "$SITE_CONTAINER" \
  || echo "⚠️  Site container not running — Caddy will 502 until: bash deploy/scripts/remote-deploy.sh"

echo
echo "✅ Done. In ~30 s Caddy fetches the certificate, then:"
echo "   https://${DOMAIN}"
echo "   https://${DOMAIN}/privacy.html   https://${DOMAIN}/support.html"
echo "   https://${DOMAIN}/app-ads.txt"
echo "Check progress:  DOCKER_HOST=ssh://${SSH_TARGET}:${SSH_PORT} docker logs -f ${NAME}"
echo "Live config:     bash deploy/scripts/remote-proxy.sh show"
echo "DNS must resolve:  dig +short ${DOMAIN}   → ${HOST}"
