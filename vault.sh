#!/bin/bash

function vault_agent_cmd {
  COMMAND=$1
  if [[ ${VAULT_RUN_MODE:=legacy} == "docker" ]]; then
    local VAULT_DOCKER_ARGS

    VAULT_DOCKER_ARGS=(
      --cap-add IPC_LOCK
      -e VAULT_TOKEN="${VAULT_TOKEN}"
      -e VAULT_ADDR="${VAULT_ADDR}"
      -e VAULT_LOG_LEVEL="${VAULT_LOG_LEVEL:=info}"
    )
    docker run --rm  -t  \
      "${VAULT_DOCKER_ARGS[@]}" \
      ${VAULT_DOCKER_IMAGE:=vault:latest} \
      vault ${COMMAND}
  else
    vault ${COMMAND}
  fi
}

function vault_get_all_keys_by_secret_path {
  SECRET_PATH=$1
  vault_agent_cmd "kv get -format json -field=data ${SECRET_PATH}"
}
