#!/bin/bash

RABBITMQADMIN="rabbitmqadmin -s -H $RABBITMQ_HOST -P $RABBITMQ_MANAGEMENT_PORT -u $RABBITMQ_MANAGEMENT_USER -p $RABBITMQ_MANAGEMENT_PASS -V /"

function rabbitmq_create_vhost () {
	$RABBITMQADMIN declare vhost name=$1
	$RABBITMQADMIN declare permission vhost=$1 user=root "configure=.*" "write=.*" "read=.*"
}

function rabbitmq_add_permission () {
	$RABBITMQADMIN declare permission vhost=$1 user=$2 "configure=.*" "write=.*" "read=.*"
}

function rabbitmq_add_read_permission () {
	$RABBITMQADMIN declare permission vhost=$1 user=$2 "configure=''" "write=''" "read=.*"
}

function rabbitmq_vhost_sanitize () {
	if [ -z "$2" ]; then
		local LENGTH="62"
	else
		local LENGTH="$2"
	fi
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c $LENGTH | sed "s/-$//g" | tr -d '\n' | tr -d '\r'
}
