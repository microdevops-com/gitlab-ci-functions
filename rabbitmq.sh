#!/bin/bash

RABBITMQADMIN="rabbitmqadmin -s -H $RABBITMQ_HOST -P $RABBITMQ_MANAGEMENT_PORT -u $RABBITMQ_MANAGEMENT_USER -p $RABBITMQ_MANAGEMENT_PASS -V /"

function rabbitmq_create_vhost () {
	$RABBITMQADMIN declare vhost name=$1
	$RABBITMQADMIN declare permission vhost=$1 user=root "configure=.*" "write=.*" "read=.*"
}

function rabbitmq_add_permission () {
	$RABBITMQADMIN declare permission vhost=$1 user=$2 "configure=.*" "write=.*" "read=.*"
}
