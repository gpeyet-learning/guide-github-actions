FROM hugomods/hugo AS builder
COPY src/ /tmp/
RUN hugo -v --cleanDestinationDir

FROM caddy
COPY Caddyfile /etc/Caddyfile
COPY --from=builder /tmp/public/ /var/www/
