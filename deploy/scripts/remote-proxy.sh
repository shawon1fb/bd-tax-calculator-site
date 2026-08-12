#!/usr/bin/env bash
#
# Put HTTPS in front of the site — runs Caddy on the server, driven from the dev
# machine. Caddy fetches + renews a free Let's Encrypt certificate automatically.
#
#     bash deploy/scripts/remote-proxy.sh          # start / update
#     bash deploy/scripts/remote-proxy.sh reload   # re-ship Caddyfile, no downtime
#     bash deploy/scripts/remote-proxy.sh down     # remove
#
# deploy/.env keys used:
#   DEPLOY_SSH_HOST / _USER / _PORT   how to reach the box
#   DEPLOY_DOMAIN                     the domain to serve, e.g. taxhelperbd.com (required)
#   DEPLOY_ACME_EMAIL                 email for Let's Encrypt notices (optional)
#   DEPLOY_NETWORK                    docker network shared with the site container
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

export DOCKER_HOST="ssh://${SSH_USER}@${HOST}:${SSH_PORT}"
docker version >/dev/null 2>&1 || { echo "❌ Can't reach Docker on the server. Provision first: bash deploy/scripts/provision.sh"; exit 1; }

if [ "$ACTION" = "down" ]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  echo "✅ ${NAME} removed."
  exit 0
fi

docker network inspect "$NETWORK" >/dev/null 2>&1 || {
  echo "▶ Network ${NETWORK} missing — creating it"
  docker network create "$NETWORK" >/dev/null
}

# Bind mounts resolve on the Docker host (the server, via DOCKER_HOST=ssh://),
# NOT this machine — so ship the Caddyfile to the server first, then mount the
# server-side path.
SSH_TARGET="${SSH_USER}@${HOST}"
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
REMOTE_HOME="$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'echo "$HOME"')"
REMOTE_DIR="${REMOTE_HOME}/bd-tax-caddy"

echo "▶ Shipping deploy/Caddyfile → ${SSH_TARGET}:${REMOTE_DIR}/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_DIR}'"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -q deploy/Caddyfile "${SSH_TARGET}:${REMOTE_DIR}/Caddyfile"

# `reload` = config-only change, container keeps running (no cert re-issue, no
# dropped connections). Falls through to a full start if it isn't up.
if [ "$ACTION" = "reload" ] && docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker exec "$NAME" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
  echo "✅ ${NAME} reloaded with the new Caddyfile."
  exit 0
fi

# Anything else already holding :80/:443 will make the run fail — say so first.
BUSY="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ':(80|443)->' | grep -v "^${NAME} " || true)"
[ -n "$BUSY" ] && { echo "⚠️  Ports 80/443 already used by:"; echo "$BUSY"; }

echo "▶ Starting Caddy (${DOMAIN}) → ${SITE_SERVICE}:80"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
  --restart unless-stopped \
  --network "$NETWORK" \
  -p 80:80 -p 443:443 \
  -e DEPLOY_DOMAIN="$DOMAIN" \
  ${EMAIL:+-e DEPLOY_ACME_EMAIL="$EMAIL"} \
  -v caddy_data:/data -v caddy_config:/config \
  -v "${REMOTE_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2 caddy run --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null

docker ps --format '{{.Names}}' | grep -qx "$SITE_CONTAINER" \
  || echo "⚠️  Site container not running — Caddy will 502 until: bash deploy/scripts/remote-deploy.sh"

echo
echo "✅ Done. In ~30 s Caddy fetches the certificate, then:"
echo "   https://${DOMAIN}"
echo "   https://${DOMAIN}/privacy.html   https://${DOMAIN}/support.html"
echo "   https://${DOMAIN}/app-ads.txt"
echo "Check progress:  DOCKER_HOST=ssh://${SSH_TARGET}:${SSH_PORT} docker logs -f ${NAME}"
echo "DNS must resolve:  dig +short ${DOMAIN}   → ${HOST}"
