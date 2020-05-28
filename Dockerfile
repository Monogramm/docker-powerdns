FROM alpine:3.9

ENV REFRESHED_AT="2020-05-24" \
    POWERDNS_VERSION=4.3.0 \
    MYSQL_DEFAULT_AUTOCONF=true \
    MYSQL_DEFAULT_HOST="mysql" \
    MYSQL_DEFAULT_PORT="3306" \
    MYSQL_DEFAULT_USER="root" \
    MYSQL_DEFAULT_PASS="root" \
    MYSQL_DEFAULT_DB="pdns" \
    PGSQL_DEFAULT_HOST="pgsql" \
    PGSQL_DEFAULT_PORT="5432" \
    PGSQL_DEFAULT_USER="postgres" \
    PGSQL_DEFAULT_PASS="postgres" \
    PGSQL_DEFAULT_DB="pdns" \
    SQLITE_DEFAULT_DB="pdns.sqlite3"

RUN set -ex; \
  apk --update --no-cache add \
    bash \
    curl-dev \
    libpq \
    libstdc++ \
    libgcc \
    lua-dev \
    mariadb-connector-c \
    mariadb-client \
    postgresql-client \
    sqlite \
    sqlite-libs \
  ; \
  apk add --virtual .build-deps \
    binutils \
    boost-dev \
    curl \
    file \
    g++ \
    make \
    mariadb-connector-c-dev \
    mariadb-dev \
    postgresql-dev \
    sqlite-dev \
  ; \
  curl -sSL https://downloads.powerdns.com/releases/pdns-$POWERDNS_VERSION.tar.bz2 | tar xj -C /tmp; \
  cd /tmp/pdns-$POWERDNS_VERSION; \
  ./configure \
    --prefix="" \
    --exec-prefix=/usr \
    --sysconfdir=/etc/pdns \
    --with-modules="" \
    --with-dynmodules="bind gmysql gpgsql gsqlite3" \
  ; \
  make; \
  make install-strip; \
  cd /; \
  cp ./modules/gmysqlbackend/*schema.mysql.sql /etc/pdns/; \
  mkdir -p /etc/pdns/conf.d; \
  addgroup -S pdns 2>/dev/null; \
  adduser -S -D -H -h /var/empty -s /bin/false -G pdns -g pdns pdns 2>/dev/null; \
  cp /usr/lib/libboost_program_options-mt.so* /tmp; \
  apk del --purge .build-deps; \
  mv /tmp/lib* /usr/lib/; \
  rm -rf /tmp/pdns-$POWERDNS_VERSION /var/cache/apk/*

COPY pdns.conf /etc/pdns/
COPY entrypoint.sh /

RUN set -ex; \
  chmod +x /entrypoint.sh

EXPOSE 53/tcp 53/udp

VOLUME [ "/etc/pdns/.docker" ]

ENTRYPOINT ["/entrypoint.sh"]

ARG VCS_REF
ARG BUILD_DATE

# Container labels (http://label-schema.org/)
# Container annotations (https://github.com/opencontainers/image-spec)
LABEL maintainer="Christoph Wiechert <wio@psitrax.de>" \
      contributors="Mathias Kaufmann <me@stei.gr>, Cloudesire <cloduesire-dev@eng.it>, Monogramm <opensource@monogramm.io>" \
      product="PowerDNS" \
      version=$POWERDNS_VERSION \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/psi-4ward/docker-powerdns" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="PowerDNS" \
      org.label-schema.description="Open source DNS software." \
      org.label-schema.url="https://www.powerdns.com/" \
      org.label-schema.vendor="PowerDNS.COM BV" \
      org.label-schema.version=$POWERDNS_VERSION \
      org.label-schema.schema-version="1.0" \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.source="https://github.com/psi-4ward/docker-powerdns" \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="PowerDNS" \
      org.opencontainers.image.description="Open source DNS software." \
      org.opencontainers.image.url="https://www.powerdns.com/" \
      org.opencontainers.image.vendor="PowerDNS.COM BV" \
      org.opencontainers.image.version=$POWERDNS_VERSION \
      org.opencontainers.image.authors="Christoph Wiechert <wio@psitrax.de>"
