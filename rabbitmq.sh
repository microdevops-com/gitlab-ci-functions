#!/bin/bash

function rabbitmq_check_api_availability() {
  MAX_CHECKS=180
  SLEEP_TIME=1
  I=0

  set -eu
  echo "Waiting for rabbitmq is running:"
  while [[ $I -lt $MAX_CHECKS ]]; do
    CMD_EXIT_CODE=0
    rabbitmq_cmd "list vhosts" > /dev/null 2>&1 || CMD_EXIT_CODE=$?

    if [[ ${CMD_EXIT_CODE} != 0 ]]; then
      echo -n "."
    else
      echo ""
      echo "RabbitMQ API running."
      break;
    fi

      I=$((I + 1))
      sleep ${SLEEP_TIME}
  done

  if [[ $I -eq $MAX_CHECKS ]]; then
      echo ""
      echo "ERROR: Waiting for rabbitmq API ready timeout."
      exit 1
  fi
}

function rabbitmq_create_vhost () {
  rabbitmq_cmd "-V / declare vhost name=$1"
  rabbitmq_cmd "-V / declare permission vhost=$1 user=root \"configure=.*\" \"write=.*\" \"read=.*\""
}

function rabbitmq_add_permission () {
  rabbitmq_cmd "-V / declare permission vhost=$1 user=$2 \"configure=.*\" \"write=.*\" \"read=.*\""
}

function rabbitmq_add_read_permission () {
  rabbitmq_cmd "-V / declare permission vhost=$1 user=$2 \"configure=''\" \"write=''\" \"read=.*\""
}

function rabbitmq_vhost_sanitize () {
  if [ -z "$2" ]; then
    local LENGTH="62"
  else
    local LENGTH="$2"
  fi
  echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c $LENGTH | sed "s/-$//g" | tr -d '\n' | tr -d '\r'
}

function rabbitmq_purge_queue () {
  VHOST=$1
  QUEUE=$2
  rabbitmq_cmd "-V $VHOST purge queue name=$QUEUE"
}


function rabbitmq_cmd() {
  COMMAND=$1
  if [[ ${CI_RABBITMQADMIN_MODE:=cmd} == "cmd" ]]; then
    RABBITMQADMIN="rabbitmqadmin -s -H $RABBITMQ_HOST -P $RABBITMQ_MANAGEMENT_PORT -u $RABBITMQ_MANAGEMENT_USER -p $RABBITMQ_MANAGEMENT_PASS"
    ${RABBITMQADMIN} ${COMMAND}
  else
    RABBITMQADMIN="rabbitmqadmin ${CI_RABBITMQADMIN_EXTRA_ARGS:-} -H ${CI_RABBITMQADMIN_HOST} -P ${CI_RABBITMQADMIN_PORT} -u ${CI_RABBITMQADMIN_USER} -p ${CI_RABBITMQADMIN_PASS}"
    if [[ ${CI_RABBITMQADMIN_DEBUG:=false} == "true" ]]; then
      echo CMD in docker: "rabbitmqadmin ${CI_RABBITMQADMIN_EXTRA_ARGS:-} -H ${CI_RABBITMQADMIN_HOST} -P ${CI_RABBITMQADMIN_PORT} -u ${CI_RABBITMQADMIN_USER} -p **********" ${COMMAND}
    fi

    if [[ ${CI_RABBITMQADMIN_DRY_RUN:=false} == "true" ]]; then
      echo CMD in docker: WARNING - dry-run mode
    else
      docker run -i rabbitmq:${CI_RABBITMQADMIN_VERSION}-management-alpine bash -c "${RABBITMQADMIN} ${COMMAND} "
    fi

  fi
}
