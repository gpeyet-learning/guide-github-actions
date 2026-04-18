FROM caddy
COPY Caddyfile /etc/Caddyfile
COPY public/ /var/www/
