FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html privacy.html support.html 404.html /usr/share/nginx/html/
COPY app-ads.txt robots.txt sitemap.xml /usr/share/nginx/html/
COPY assets/ /usr/share/nginx/html/assets/

# Docker marks the container unhealthy if nginx stops answering — visible in
# `docker ps` and used by deploy/scripts/health.sh. wget ships with busybox.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
