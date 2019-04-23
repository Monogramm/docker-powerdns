#!/bin/sh
set -e

[[ -z "$TRACE" ]] || set -x

# --help, --version
[ "$1" = "--help" ] || [ "$1" = "--version" ] && exec pdns_server $1
# treat everything except -- as exec cmd
[ "${1:0:2}" != "--" ] && exec "$@"

# Add backward compatibility
[[ "$MYSQL_AUTOCONF" == false ]] && AUTOCONF=false

# Set credentials to be imported into pdns.conf
case "$AUTOCONF" in
  mysql)
    echo 'setting up mysql properties...'
    #export PDNS_LOAD_MODULES=libgmysqlbackend.so,$PDNS_LOAD_MODULES
    export PDNS_LAUNCH=gmysql
    export PDNS_GMYSQL_HOST=${PDNS_GMYSQL_HOST:-$MYSQL_HOST}
    export PDNS_GMYSQL_PORT=${PDNS_GMYSQL_PORT:-$MYSQL_PORT}
    export PDNS_GMYSQL_USER=${PDNS_GMYSQL_USER:-$MYSQL_USER}
    export PDNS_GMYSQL_PASSWORD=${PDNS_GMYSQL_PASSWORD:-$MYSQL_PASS}
    export PDNS_GMYSQL_DBNAME=${PDNS_GMYSQL_DBNAME:-$MYSQL_DB}
    export PDNS_GMYSQL_DNSSEC=${PDNS_GMYSQL_DNSSEC:-$MYSQL_DNSSEC}
  ;;
  postgres)
    echo 'setting up postgres properties...'
    #export PDNS_LOAD_MODULES=libgpgsqlbackend.so,$PDNS_LOAD_MODULES
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
    echo 'setting up sqlite properties...'
    #export PDNS_LOAD_MODULES=libgsqlite3backend.so,$PDNS_LOAD_MODULES
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
      pg_isready -d postgres://${PGSQL_HOST}:${PGSQL_PORT}/${PGSQL_DB} 1>/dev/null
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
until [ $(isDBup) -eq 0 ] || [ $RETRY -le 0 ] ; do
  echo "Waiting for database to come up"
  sleep 5
  RETRY=$(expr $RETRY - 1)
done
if [ $RETRY -le 0 ]; then
  if [[ "$MYSQL_HOST" ]]; then
    >&2 echo Error: Could not connect to Database on $MYSQL_HOST:$MYSQL_PORT
    exit 1
  elif [[ "$PGSQL_HOST" ]]; then
    >&2 echo Error: Could not connect to Database on $PGSQL_HOST:$PGSQL_PORT
    exit 1
  fi
fi

# init database and migrate database if necessary
case "$PDNS_LAUNCH" in
  gmysql)
    echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;" | $MYSQLCMD
    MYSQLCMD="$MYSQLCMD $MYSQL_DB"
    if [ "$(echo "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = \"$MYSQL_DB\";" | $MYSQLCMD)" -le 1 ]; then
      echo Initializing MySQL Database
      $MYSQLCMD < /etc/pdns/schema.mysql.sql
    fi
  ;;
  gpgsql)
    #if [[ -z "$(echo "SELECT 1 FROM pg_database WHERE datname = '$PGSQL_DB'" | $PGSQLCMD -t)" ]]; then
    #  echo "CREATE DATABASE $PGSQL_DB;" | $PGSQLCMD
    #fi
    PGSQLCMD="$PGSQLCMD -p ${PGSQL_PORT} -d ${PGSQL_DB} -w "
    if ! PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -t -c "\d" | grep -qw "domains"; then
      echo Initializing Postgres Database
      PGPASSWORD=${PGSQL_PASS} $PGSQLCMD -f /etc/pdns/schema.pgsql.sql
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
      install -D -d -o pdns -g pdns -m 0755 $(dirname $PDNS_GSQLITE3_DATABASE)
      echo Initializing SQLite Database
      sqlite3 $PDNS_GSQLITE3_DATABASE < /etc/pdns/schema.sqlite3.sql
      chown pdns:pdns $PDNS_GSQLITE3_DATABASE
    fi
  ;;
esac

# Split modules to load dynamically
#PDNS_LOAD_MODULES="$(echo $PDNS_LOAD_MODULES | sed 's/^,//')"

# convert all environment variables prefixed with PDNS_ into pdns config directives
printenv | grep ^PDNS_ | cut -f2- -d_ | while read var; do
  val="${var#*=}"
  var="${var%%=*}"
  var="$(echo $var | sed -e 's/_/-/g' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$TRACE" ]] || echo "$var=$val"
  sed -r -i "s#^[# ]*$var=.*#$var=$val#g" /etc/pdns/pdns.conf
done

# environment cleanup
for var in $(printenv | cut -f1 -d= | grep -v -e HOME -e USER -e PATH ); do unset $var; done
export TZ=UTC LANG=C LC_ALL=C

# prepare graceful shutdown
trap "pdns_control quit" SIGHUP SIGINT SIGTERM

# run pdns server
pdns_server "$@" &

wait
