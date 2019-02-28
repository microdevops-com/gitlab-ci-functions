#!/bin/bash

function postgresql_create_db () {
	local PGHOST="$1"
	local PGPORT="$2"
	local PGUSER="$3"
	local PGPASSWORD="$4"
	local NEW_DB_NAME="$5"
	# check db exist and if not - create
	PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w -lqt | cut -d \| -f 1 | grep -qw "$NEW_DB_NAME" || \
		PGPASSWORD="$PGPASSWORD" createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w "$NEW_DB_NAME"
}
