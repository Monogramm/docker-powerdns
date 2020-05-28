#!/bin/bash
set -e

log() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%:z)] $@"
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
# source: https://github.com/docker-library/mariadb/blob/master/docker-entrypoint.sh
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        log "Both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

# Loads various settings that are used elsewhere in the script
docker_setup_env() {
    # Initialize values that might be stored in a file

    file_env 'AUTOCONF' "$DEFAULT_AUTOCONF"

    file_env 'MYSQL_HOST' "$MYSQL_DEFAULT_HOST"
    file_env 'MYSQL_DNSSEC' 'no'
    file_env 'MYSQL_DB' "$MYSQL_DEFAULT_DB"
    file_env 'MYSQL_PASS' "$MYSQL_DEFAULT_PASS"
    file_env 'MYSQL_USER' "$MYSQL_DEFAULT_USER"
    file_env 'MYSQL_PORT' "$MYSQL_DEFAULT_PORT"

    file_env 'PGSQL_HOST' "$PGSQL_DEFAULT_HOST"
    file_env 'PGSQL_DNSSEC' 'no'
    file_env 'PGSQL_DB' "$PGSQL_DEFAULT_DB"
    file_env 'PGSQL_PASS' "$PGSQL_DEFAULT_PASS"
    file_env 'PGSQL_USER' "$PGSQL_DEFAULT_USER"
    file_env 'PGSQL_PORT' "$PGSQL_DEFAULT_PORT"

    file_env 'SQLITE_DNSSEC' 'no'
    file_env 'SQLITE_DB' "$SQLITE_DEFAULT_DB"
}

docker_setup_env

[[ -z "$TRACE" ]] || set -x

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server "$1"
# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

# Add backward compatibility
[[ "$MYSQL_AUTOCONF" == false ]] && AUTOCONF=false

# Set credentials to be imported into pdns.conf
case "$AUTOCONF" in
  mysql)
    log 'Setting up mysql properties...'
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgmysqlbackend.so
    export PDNS_LAUNCH=gmysql
    export PDNS_GMYSQL_HOST=${PDNS_GMYSQL_HOST:-$MYSQL_HOST}
    export PDNS_GMYSQL_PORT=${PDNS_GMYSQL_PORT:-$MYSQL_PORT}
    export PDNS_GMYSQL_USER=${PDNS_GMYSQL_USER:-$MYSQL_USER}
    export PDNS_GMYSQL_PASSWORD=${PDNS_GMYSQL_PASSWORD:-$MYSQL_PASS}
    export PDNS_GMYSQL_DBNAME=${PDNS_GMYSQL_DBNAME:-$MYSQL_DB}
    export PDNS_GMYSQL_DNSSEC=${PDNS_GMYSQL_DNSSEC:-$MYSQL_DNSSEC}
  ;;
  postgres)
    log 'Setting up postgres properties...'
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgpgsqlbackend.so
    export PDNS_LAUNCH=gpgsql
    export PDNS_GPGSQL_HOST=${PDNS_GPGSQL_HOST:-$PGSQL_HOST}
    export PDNS_GPGSQL_PORT=${PDNS_GPGSQL_PORT:-$PGSQL_PORT}
    export PDNS_GPGSQL_USER=${PDNS_GPGSQL_USER:-$PGSQL_USER}
    export PDNS_GPGSQL_PASSWORD=${PDNS_GPGSQL_PASSWORD:-$PGSQL_PASS}
    export PDNS_GPGSQL_DBNAME=${PDNS_GPGSQL_DBNAME:-$PGSQL_DB}
    export PDNS_GPGSQL_DNSSEC=${PDNS_GPGSQL_DNSSEC:-$PGSQL_DNSSEC}
    export PGPASSWORD=$PDNS_GPGSQL_PASSWORD
  ;;
  sqlite)
    log 'Setting up sqlite properties...'
    export PDNS_LOAD_MODULES=$PDNS_LOAD_MODULES,libgsqlite3backend.so
    export PDNS_LAUNCH=gsqlite3
    export PDNS_GSQLITE3_DATABASE=${PDNS_GSQLITE3_DATABASE:-$SQLITE_DB}
    export PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS=${PDNS_GSQLITE3_PRAGMA_SYNCHRONOUS:-$SQLITE_PRAGMA_SYNCHRONOUS}
    export PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS=${PDNS_GSQLITE3_PRAGMA_FOREIGN_KEYS:-$SQLITE_PRAGMA_FOREIGN_KEYS}
    export PDNS_GSQLITE3_DNSSEC=${PDNS_GSQLITE3_DNSSEC:-$SQLITE_DNSSEC}
  ;;
esac

MYSQLCMD="mysql --host=${MYSQL_HOST} --user=${MYSQL_USER} --password=${MYSQL_PASS} --port=${MYSQL_PORT} -r -N"
PGSQLCMD="psql --host=${PGSQL_HOST} --username=${PGSQL_USER}"

# wait for Database come ready
isDBup () {
  case "$PDNS_LAUNCH" in
    gmysql)
      echo "SHOW STATUS" | $MYSQLCMD 1>/dev/null
      echo $?
    ;;
    gpgsql)
      pg_isready -d "postgres://${PGSQL_HOST}:${PGSQL_PORT}/${PGSQL_DB}" 1>/dev/null
      echo $?
      # Alternative way to check DB is up
      #PGSQLCMD="$PGSQLCMD -p ${PGSQL_PORT} -d ${PGSQL_DB} -w "
      #PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -c "select version()" 1>/dev/null
      #echo $?
      # Yet another way to check DB is up
      #echo "SELECT 1" | $PGSQLCMD 1>/dev/null
      #echo $?
    ;;
    *)
      echo 0
    ;;
  esac
}

RETRY=10
until [ $(isDBup) -eq 0 ] || [ "$RETRY" -le 0 ] ; do
  log "Waiting for database to come up"
  sleep 5
  RETRY=$((RETRY-1))
done
if [ "$RETRY" -le 0 ]; then
  if [[ "$MYSQL_HOST" ]]; then
    >&2 echo "Error: Could not connect to Database on $MYSQL_HOST:$MYSQL_PORT"
    exit 1
  elif [[ "$PGSQL_HOST" ]]; then
    >&2 echo "Error: Could not connect to Database on $PGSQL_HOST:$PGSQL_PORT"
    exit 1
  fi
fi

log 'Init database and migrate database if necessary...'
case "$PDNS_LAUNCH" in
  gmysql)
    echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;" | $MYSQLCMD
    MYSQLCMD="$MYSQLCMD $MYSQL_DB"
    if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DB\";" | $MYSQLCMD)" -le 1 ]; then
      log 'Initializing MySQL Database'
      $MYSQLCMD < /etc/pdns/schema.mysql.sql

      echo "Storing MySQL Database version"
      echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt

      # Run custom mysql post-init sql scripts
      if [ -d "/etc/pdns/mysql-postinit" ]; then
        for SQLFILE in $(ls -1 /etc/pdns/mysql-postinit/*.sql | sort) ; do
          echo "Source $SQLFILE"
          $MYSQLCMD < "$SQLFILE"
        done
      fi
    elif [ -f '/etc/pdns/.docker/db-version.txt' ]; then
      DB_VERSION=$(cat '/etc/pdns/.docker/db-version.txt')

      if [ -f "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql" ]; then
        echo "Updating MySQL Database from ${DB_VERSION} to ${POWERDNS_VERSION}"
        cat "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql" | $MYSQLCMD

        echo "Updating MySQL Database version"
        echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt
      fi
    fi
  ;;
  gpgsql)
    if [[ -z "$(echo "SELECT 1 FROM pg_database WHERE datname = '$PGSQL_DB'" | $PGSQLCMD -t)" ]]; then
      echo "CREATE DATABASE $PGSQL_DB;" | $PGSQLCMD
    fi
    PGSQLCMD="$PGSQLCMD -p ${PGSQL_PORT} -d ${PGSQL_DB} -w "
    if ! PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -t -c "\d" | grep -qw "domains"; then
      log 'Initializing Postgres Database'
      PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -f /etc/pdns/schema.pgsql.sql

      echo "Storing Postgres Database version"
      echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt

      # Run custom pgsql post-init sql scripts
      if [ -d "/etc/pdns/pgsql-postinit" ]; then
        for SQLFILE in $(ls -1 /etc/pdns/pgsql-postinit/*.sql | sort) ; do
          echo "Source $SQLFILE"
          PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -f "$SQLFILE"
        done
      fi
    elif [ -f '/etc/pdns/.docker/db-version.txt' ]; then
      DB_VERSION=$(cat '/etc/pdns/.docker/db-version.txt')

      if [ -f "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql" ]; then
        echo "Updating Postgres Database from ${DB_VERSION} to ${POWERDNS_VERSION}"
        PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -f "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql"

        echo "Updating Postgres Database version"
        echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt
      fi
    fi
    # Yet another way to init DB
    #PGSQLCMD="$PGSQLCMD $PGSQL_DB"
    #if [[ -z "$(printf '\dt' | $PGSQLCMD -qAt)" ]]; then
    #  echo Initializing Database
    #  $PGSQLCMD < /etc/pdns/schema.pgsql.sql
    #fi
  ;;
  gsqlite3)
    if [[ ! -f "$PDNS_GSQLITE3_DATABASE" ]]; then
      install -D -d -o pdns -g pdns -m 0755 $(dirname "$PDNS_GSQLITE3_DATABASE")
      log 'Initializing SQLite Database'
      sqlite3 "$PDNS_GSQLITE3_DATABASE" < /etc/pdns/schema.sqlite3.sql
      chown pdns:pdns "$PDNS_GSQLITE3_DATABASE"

      echo "Storing SQLite Database version"
      echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt

      # Run custom pgsql post-init sql scripts
      if [ -d "/etc/pdns/sqlite3-postinit" ]; then
        for SQLFILE in $(ls -1 /etc/pdns/sqlite3-postinit/*.sql | sort) ; do
          echo "Source $SQLFILE"
          sqlite3 "$PDNS_GSQLITE3_DATABASE" < "$SQLFILE"
        done
      fi
    elif [ -f '/etc/pdns/.docker/db-version.txt' ]; then
      DB_VERSION=$(cat '/etc/pdns/.docker/db-version.txt')

      if [ -f "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql" ]; then
        echo "Updating SQLite Database from ${DB_VERSION} to ${POWERDNS_VERSION}"
        sqlite3 "$PDNS_GSQLITE3_DATABASE" < "/etc/pdns/${DB_VERSION}_to_${POWERDNS_VERSION}_schema.mysql.sql"

        echo "Updating SQLite Database version"
        echo "${POWERDNS_VERSION}" > /etc/pdns/.docker/db-version.txt
      fi
    fi
  ;;
esac

log 'Split modules to load dynamically...'
PDNS_LOAD_MODULES=$(echo "$PDNS_LOAD_MODULES" | sed 's/^,//')

log 'Convert all environment variables prefixed with PDNS_ into pdns config directives...'
printenv | grep ^PDNS_ | cut -f2- -d_ | while read var; do
  val="${var#*=}"
  var="${var%%=*}"
  var=$(echo "$var" | sed -e 's/_/-/g' | tr '[:upper:]' '[:lower:]')
  [[ -z "$TRACE" ]] || echo "$var=$val"
  sed -r -i "s#^[# ]*$var=.*#$var=$val#g" /etc/pdns/pdns.conf
done

log 'Environment cleanup...'
for var in $(printenv | cut -f1 -d= | grep -v -e HOME -e USER -e PATH ); do unset "$var"; done
export TZ=UTC LANG=C LC_ALL=C

log 'Prepare graceful shutdown...'
trap "pdns_control quit" SIGHUP SIGINT SIGTERM

log 'Run pdns server...'
pdns_server "$@" &

wait
