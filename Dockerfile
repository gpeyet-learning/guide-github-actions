FROM hugomods/hugo AS builder
COPY . /src
RUN hugo --cleanDestinationDir

FROM caddy
COPY Caddyfile /etc/Caddyfile
COPY --from=builder /src/public/ /var/www/
