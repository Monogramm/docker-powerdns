# PowerDNS Docker Container

[![Build Status](https://travis-ci.org/psitrax/powerdns.svg)](https://travis-ci.org/psitrax/powerdns)
[![Image Size](https://images.microbadger.com/badges/image/psitrax/powerdns.svg)](https://microbadger.com/images/psitrax/powerdns)
[![Docker Stars](https://img.shields.io/docker/stars/psitrax/powerdns.svg)](https://hub.docker.com/r/psitrax/powerdns/)
[![Docker Pulls](https://img.shields.io/docker/pulls/psitrax/powerdns.svg)](https://hub.docker.com/r/psitrax/powerdns/)
[![Docker Automated buil](https://img.shields.io/docker/automated/psitrax/powerdns.svg)](https://hub.docker.com/r/psitrax/powerdns/)

* Small Alpine based Image
* MySQL (default), Postgres, SQLite and Bind backend included
* DNSSEC support optional
* Automatic database initialization for MySQL, Postgres or SQLite
* Latest PowerDNS version (if not pls file an issue)
* Guardian process enabled
* Graceful shutdown using pdns_control

## Supported tags

* Exact: i.e. `4.3.0`: PowerDNS Version 4.3.0
* `4.0`: PowerDNS Version 4.0.x, latest image build
* `4`: PowerDNS Version 4.x.x, latest image build

## Usage

### MySQL

```shell
# Start a MySQL Container
$ docker run -d \
  --name pdns-mysql \
  -e MYSQL_ROOT_PASSWORD=supersecret \
  -v $PWD/mysql-data:/var/lib/mysql \
  mariadb:10.1

$ docker run --name pdns \
  --link pdns-mysql:mysql \
  -p 53:53 \
  -p 53:53/udp \
  -e MYSQL_USER=root \
  -e MYSQL_PASS=supersecret \
  psitrax/powerdns \
    --cache-ttl=120 \
    --allow-axfr-ips=127.0.0.1,123.1.2.3
```

With docker-compose:
```yml
  powerdnsdb:
    image: mariadb:10.1
    container_name: powerdnsdb
    restart: always
    ports:
      - "23342:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=rootsupersecret
      - MYSQL_DATABASE=powerdnsdb
      - MYSQL_USER=powerdns
      - MYSQL_PASSWORD=supersecret
    volumes:
      - /srv/powerdns/db/data:/var/lib/mysql

  powerdns:
    image: psitrax/powerdns
    container_name: powerdns
    restart: always
    ports:
      - 53/tcp:53/tcp
      - 53/udp:53/udp
    environment:
      - MYSQL_HOST=powerdnsdb
      - MYSQL_PORT=3306
      - MYSQL_DB=powerdnsdb
      - MYSQL_USER=powerdns
      - MYSQL_PASS=supersecret
```

Then, just run your containers:
```shell
$ docker-compose up -d
```

### Postgres

```shell
# Start a Postgres Container
$ docker run -d \
  --name pdns-postgres \
  -e POSTGRES_PASSWORD=supersecret \
  -v $PWD/postgres-data:/var/lib/postgresql \
  postgres:9.6
$ docker run --name pdns \
  --link pdns-postgres:postgres \
  -p 53:53 \
  -p 53:53/udp \
  -e AUTOCONF=postgres \
  -e PGSQL_USER=postgres \
  -e PGSQL_PASS=supersecret \
  psitrax/powerdns \
    --cache-ttl=120 \
    --allow-axfr-ips=127.0.0.1,123.1.2.3
```

### SQLite

```shell
$ docker run --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -e AUTOCONF=sqlite \
  psitrax/powerdns \
    --cache-ttl=120 \
    --allow-axfr-ips=127.0.0.1,123.1.2.3
```

## Configuration

**Environment Configuration:**

* MySQL connection settings
  * `MYSQL_HOST=mysql`
  * `MYSQL_PORT=3306`
  * `MYSQL_USER=root`
  * `MYSQL_PASS=root`
  * `MYSQL_DB=pdns`
  * `MYSQL_DNSSEC=no`
* Postgres connection settings
  * `AUTOCONF=postgres`
  * `PGSQL_HOST=postgresql`
  * `PGSQL_PORT=5532`
  * `PGSQL_USER=pdns`
  * `PGSQL_PASS=pdnspassword`
  * `PGSQL_DB=pdns`
  * `PGSQL_DNSSEC=no`
* SQLite connection settings
  * `AUTOCONF=sqlite`
  * `SQLITE_DB=/pdns.sqlite3`
  * `SQLITE_DNSSEC=no`
* Want to disable mysql initialization? Use `AUTOCONF=false`
* Want to apply 12Factor-Pattern? Apply environment variables of the form `PDNS_$pdns-config-variable=$config-value`, like `PDNS_WEBSERVER=yes`
* To support docker secrets, use same variables as above with suffix `_FILE`.
* DNSSEC is disabled by default, to enable use `MYSQL_DNSSEC=yes` or `PGSQL_DNSSEC=yes` or `SQLITE_DNSSEC=yes`
* Want to use own config files? Mount a Volume to `/etc/pdns/conf.d` or simply overwrite `/etc/pdns/pdns.conf`

**PowerDNS Configuration:**

Append the PowerDNS setting to the command as shown in the example above.
See `docker run --rm psitrax/powerdns --help`


## License

[GNU General Public License v2.0](https://github.com/PowerDNS/pdns/blob/master/COPYING) applyies to PowerDNS and all files in this repository.


## Maintainer

* Christoph Wiechert <wio@psitrax.de>

### Credits

* Mathias Kaufmann <me@stei.gr>: Reduced image size

