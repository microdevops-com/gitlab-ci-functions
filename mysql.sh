#!/bin/bash

function mysql_create_db () {
	local NEW_DB_NAME="$1"
	echo 'CREATE DATABASE IF NOT EXISTS `'$NEW_DB_NAME'`' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT"
}

function mysql_grant_all_privileges_on_db () {
	local DB_NAME="$1"
	local USER_NAME="$2"
	echo 'GRANT ALL PRIVILEGES ON DATABASE `'$DB_NAME'`.* TO `'$USER_NAME'`@`%`;' | mysql -u "$MYSQL_USER" --password="$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT"
}

function mysql_db_sanitize () {
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c 63
}
