#!/bin/bash

function postgresql_create_db () {
	local NEW_DB_NAME="$1"
	# check db exist and if not - create
	PGPASSWORD="$POSTGRESQL_PASS" psql -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w -lqt | cut -d \| -f 1 | grep -qw "$NEW_DB_NAME" || \
		PGPASSWORD="$POSTGRESQL_PASS" createdb -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w "$NEW_DB_NAME"
}
