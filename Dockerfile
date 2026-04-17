FROM hugomods/hugo
COPY src/ /tmp/
RUN hugo -v --cleanDestinationDir

FROM caddy
COPY Caddyfile /etc/Caddyfile
COPY --from=hugo /tmp/public/ /var/www/
