#!/usr/bin/env bash

function ssh_import_key {
  echo "SSH -> Import ssh key from SSH_PRIVATE_KEY"
  eval $(ssh-agent -s)
  echo "$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
}

function ssh_execute_cmd {
  COMMAND=$1
  if [[ ${SSH_CMD_DEBUG:=false} == "true" ]]; then
      echo "SSH -> Run CMD: ${SSH_CMD_BEFORE_RUN:=} ${COMMAND}"
  fi
  ssh \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    ${SSH_CMD_USER}@${SSH_CMD_HOST} -p ${SSH_CMD_PORT} ${SSH_CMD_EXTRA_ARGS:=} \
    "${COMMAND}"
}

function ssh_run_cmd {
  COMMAND=$1
  if [[ ${SSH_CMD_DEBUG:=false} == "true" ]]; then
      echo "SSH -> Run CMD: ${SSH_CMD_BEFORE_RUN:=} ${COMMAND}"
  fi
  #-o LogLevel=quiet \
  ssh \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    ${SSH_CMD_USER}@${SSH_CMD_HOST} -p ${SSH_CMD_PORT} ${SSH_CMD_EXTRA_ARGS:=} \
    "cd ${SSH_CMD_BASE_PATH} && ${SSH_CMD_BEFORE_RUN:=} ${COMMAND}"

}

function ssh_copy_files {
  CURRENT_PATH=$1
  REMOTE_PATH=$2
  if [[ ${SSH_CMD_DEBUG:=false} == "true" ]]; then
      echo "SSH -> Copy: ($(pwd)) -> ${CURRENT_PATH:=} to remote host ${REMOTE_PATH}"
  fi
  scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ${SSH_CMD_SCP_EXTRA_ARGS:=} \
    -P ${SSH_CMD_PORT} -rp ${CURRENT_PATH} ${SSH_CMD_USER}@${SSH_CMD_HOST}:${REMOTE_PATH}
}
