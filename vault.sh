#!/bin/bash
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install for correct work"
    exit 1
fi

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

function vault_get_keys_by_secret_path {
  SECRET_PATH=$1
  vault_agent_cmd "kv get -format json -field=data ${SECRET_PATH}"
}

function vault_load_variables_by_secret_path {
  SECRET_PATH=$1
  IS_EXPORT=${2:-false}

  local values=$(vault_agent_cmd "kv get -format json -field=data ${SECRET_PATH}")
  while IFS="=" read key value; do
    if [[ ${IS_EXPORT} == true ]]; then
      export ${key}="${value}"
    else
      eval ${key}="${value}"
    fi
  done < <( echo $values | jq --raw-output 'to_entries|map("\(.key|ascii_upcase)=\"\(.value|tostring)\"")|.[]')
}
