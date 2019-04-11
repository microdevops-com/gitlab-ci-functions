#!/bin/bash

function postgresql_create_db () {
	local NEW_DB_NAME="$1"
	# check db exist and if not - create
	echo "Creating DB: $NEW_DB_NAME"
	if PGPASSWORD="$POSTGRESQL_PASS" psql -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w -lqtA | cut -d \| -f 1 | grep "^${NEW_DB_NAME}$"; then
		echo "DB $NEW_DB_NAME already exists"
	else
		PGPASSWORD="$POSTGRESQL_PASS" createdb -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w "$NEW_DB_NAME"
	fi
}

function postgresql_grant_all_privileges_on_db () {
	local DB_NAME="$1"
	local USER_NAME="$2"
	echo 'GRANT ALL PRIVILEGES ON DATABASE "'$DB_NAME'" TO "'$USER_NAME'";' | PGPASSWORD="$POSTGRESQL_PASS" psql -h "$POSTGRESQL_HOST" -p "$POSTGRESQL_PORT" -U "$POSTGRESQL_USER" -w "$DB_NAME"
}

function postgresql_db_sanitize () {
	if [ -z "$2" ]; then
		local LENGTH="63"
	else
		local LENGTH="$2"
	fi
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c $LENGTH | sed "s/-$//g" | tr -d '\n' | tr -d '\r'
}
