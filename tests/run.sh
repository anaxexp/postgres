#!/bin/bash

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

export POSTGRES_PASSWORD='password'
export POSTGRES_USER='superuser'
export POSTGRES_DB='postgres'

cid="$(
	docker run -d \
		-e POSTGRES_PASSWORD \
		-e POSTGRES_USER \
		-e POSTGRES_DB \
		-e POSTGRES_DB_EXTENSIONS=pg_trgm \
		-e DEBUG \
		--name "${NAME}" \
		"${IMAGE}"
)"
trap "docker rm -vf ${cid} > /dev/null" EXIT

postgres() {
	docker run --rm -i \
	    -e POSTGRES_USER -e POSTGRES_PASSWORD -e POSTGRES_DB -e DEBUG \
	    -v /tmp:/mnt \
	    --link "${NAME}":"postgres" \
	    "${IMAGE}" \
	    "$@" \
	    host="postgres"
}

postgres make check-ready max_try=12 wait_seconds=5

echo -n "Checking extensions... "
postgres make query-silent query='\dx' | grep -q 'pg_trgm'
echo "OK"

echo -n "Running queries... "
postgres make query query="CREATE TABLE test (a INT, b INT, c VARCHAR(255))"
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test')" = 0 ]
postgres make query query="INSERT INTO test VALUES (1, 2, 'hello')"
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test')" = 1 ]
postgres make query query="INSERT INTO test VALUES (2, 3, 'goodbye!')"
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test')" = 2 ]
postgres make query query="DELETE FROM test WHERE a = 1"
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test')" = 1 ]
postgres make query query="DELETE FROM test WHERE a = 1"
[ "$(postgres make query-silent query='SELECT c FROM test')" = 'goodbye!' ]
postgres make query query="DELETE FROM test WHERE a = 1"

postgres make query query="CREATE TABLE test1 (a INT, b INT, c VARCHAR(255))"
postgres make query query="CREATE TABLE test2 (a INT, b INT, c VARCHAR(255))"
postgres make query query="INSERT INTO test1 VALUES (1, 2, 'hello')"
postgres make query query="INSERT INTO test2 VALUES (1, 2, 'hello!')"
echo "OK"

echo -n "Running backups... "
postgres make backup filepath="/mnt/export.sql.gz" ignore="test1;test2"
echo "OK"

echo -n "Running import from file... "
postgres make import source="/mnt/export.sql.gz"
echo "OK"

echo -n "Checking ignored tables from backup/import... "
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test')" = 1 ]
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test1')" = 0 ]
[ "$(postgres make query-silent query='SELECT COUNT(*) FROM test2')" = 0 ]
echo "OK"

echo -n "Running import from URL source (.zip)... "
postgres make import source="https://s3-us-west-1.amazonaws.com/anaxexp-sample-files/postgres-import-test/export.zip"
echo "OK"

echo -n "Running import from URL source (.tar.gz)... "
postgres make import source="https://s3-us-west-1.amazonaws.com/anaxexp-sample-files/postgres-import-test/export.tar.gz"
echo "OK"