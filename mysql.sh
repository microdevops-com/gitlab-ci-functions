#!/bin/bash

function mysql_create_db () {
	local NEW_DB_NAME="$1"
	echo 'CREATE DATABASE IF NOT EXISTS `'$NEW_DB_NAME'`;' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT"
}

function mysql_truncate_table () {
	local DB_NAME="$1"
	local TABLE="$2"
	echo 'TRUNCATE TABLE `'$TABLE'`;' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$DB_NAME"
}

function mysql_query_from_file () {
	local DB_NAME="$1"
	local FILE="$2"
	cat "$FILE" | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$DB_NAME"
}

function mysql_grant_all_privileges_on_db () {
	local DB_NAME="$1"
	local USER_NAME="$2"
	echo 'GRANT ALL PRIVILEGES ON `'$DB_NAME'`.* TO `'$USER_NAME'`@`%`;' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT"
}

function mysql_db_sanitize () {
	if [ -z "$2" ]; then
		local LENGTH="63"
	else
		local LENGTH="$2"
	fi
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c $LENGTH | sed "s/-$//g" | tr -d '\n' | tr -d '\r'
}

function mysql_delete_from_table_where () {
	local DB_NAME="$1"
	local TABLE="$2"
	local WHERE="$3"
	echo 'DELETE FROM TABLE `'$TABLE'` WHERE '$WHERE';' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT" "$DB_NAME"
}
