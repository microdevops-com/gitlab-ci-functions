#!/bin/bash

function postgresql_create_db () {
	local NEW_DB_NAME="$1"
	# check db exist and if not - create
	echo "Creating DB: $NEW_DB_NAME"
	PGPASSWORD="$POSTGRESQL_PASS" psql -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w -lqt | cut -d \| -f 1 | grep -qw "$NEW_DB_NAME" || \
		PGPASSWORD="$POSTGRESQL_PASS" createdb -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w "$NEW_DB_NAME"
}

function postgresql_grant_all_privileges_on_db () {
	local DB_NAME="$1"
	local USER_NAME="$2"
	echo 'GRANT ALL PRIVILEGES ON DATABASE "'$DB_NAME'" TO "'$USER_NAME'";' | PGPASSWORD="$POSTGRESQL_PASS" psql -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w "$DB_NAME"
}

function postgresql_db_sanitize () {
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c 63
}
