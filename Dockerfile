#
# Builder Caddy
#
FROM abiosoft/caddy:builder as builder

ARG version_caddy="1.0.3"
ARG plugins="cors,realip"

# process wrapper
RUN go get -v github.com/abiosoft/parent

RUN VERSION=${version_caddy} PLUGINS=${plugins} ENABLE_TELEMETRY=false /bin/sh /usr/bin/builder.sh

#
# Final stage
#
FROM alpine:3.10
ARG ttrss_repo="https://git.tt-rss.org/fox/tt-rss.git"

# select TTRSS branch/tag repo to build
ARG ttrss_branch="1.15.3"
ARG ttrss_dir="/srv/tt-rss"

LABEL maintainer "TonyBounty <tonybounty@tutanota.com>"

ARG version_caddy="1.0.3"
LABEL caddy_version="$version_caddy"

# Let's Encrypt Agreement
ENV ACME_AGREE="false"

# Telemetry Stats
ENV ENABLE_TELEMETRY="false"

# Packages for Caddy
RUN apk add --no-cache \
    ca-certificates \
    git \
    mailcap \
    openssh-client \
    tzdata 

# Packages for TTRSS 
RUN apk add --no-cache php7 php7-fpm \
	php7-pdo php7-gd php7-pgsql php7-pdo_pgsql php7-mbstring \
	php7-intl php7-xml php7-curl php7-session \
	php7-dom php7-fileinfo php7-ctype php7-json \
	git postgresql-client dcron sudo 

# install caddy
COPY --from=builder /install/caddy /usr/bin/caddy

# validate install Caddy
RUN /usr/bin/caddy -version
RUN /usr/bin/caddy -plugins

EXPOSE 2015
WORKDIR /srv

# Copying configuration files
COPY Caddyfile /etc/Caddyfile
COPY index.php /srv/
COPY startup.sh /
COPY update /etc/periodic/15min/

# Using Unix Socket for Caddy<->PHP7
RUN sed -i.bak 's%^listen = 127.0.0.1:9000%listen = /run/php/php7-fpm.sock%' /etc/php7/php-fpm.d/www.conf

# Cloning git repository from TTRSS
RUN git clone --branch ${ttrss_branch} ${ttrss_repo} ${ttrss_dir}
RUN git clone https://git.tt-rss.org/fox/ttrss-nginx-xaccel.git ${ttrss_dir}/plugins.local/nginx_xaccel
RUN addgroup app && adduser -D -h /srv -G app app
RUN chown -R app:app ${ttrss_dir}
RUN chmod +x /etc/periodic/15min/*
RUN /bin/sh -c 'for d in cache lock feed-icons; do chmod -R 777 ${ttrss_dir}/$d; done'
RUN mkdir -p /run/php
RUN mkdir -p /var/cache/ttrss

ENV TTRSS_DIR=${ttrss_dir}

# install process wrapper
COPY --from=builder /go/bin/parent /bin/parent

ENTRYPOINT ["/startup.sh"]
