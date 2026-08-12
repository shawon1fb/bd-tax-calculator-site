FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html privacy.html support.html app-ads.txt /usr/share/nginx/html/
COPY assets/ /usr/share/nginx/html/assets/
