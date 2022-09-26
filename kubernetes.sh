#!/bin/bash

if [[ ${KUBE_MODE:=rancher} == "rancher" ]]; then
  . .gitlab-ci-functions/rancher.sh
else
  KUBECTL="kubectl --v=${KUBECTL_VERBOSE_LEVEL:-0} --kubeconfig ${PWD}/.kube/config.yml"
  HELM="helm --kubeconfig ${PWD}/.kube/config.yml"

  function kube_cluster_login {	
    mkdir -p ${PWD}/.kube/
    touch ${PWD}/.kube/config.yml
    chmod 0600 ${PWD}/.kube/config.yml

    if [[ ${KUBE_AUTH_TYPE} == "basic" ]]; then
      ${KUBECTL} config set-cluster remote-cluster --server=${KUBE_SERVER}
      ${KUBECTL} config set-credentials ${KUBE_AUTH_USER} --password="${KUBE_AUTH_PASSWORD}".

    elif [[ ${KUBE_AUTH_TYPE} == "cert" ]]; then
      echo ${KUBE_AUTH_CERTIFICATE_AUTHORITY} | base64 --decode > ${PWD}/.kube/certificate-authority.crt
      echo ${KUBE_AUTH_CLIENT_CERTIFICATE} | base64 --decode > ${PWD}/.kube/client-certificate.crt
      echo ${KUBE_AUTH_CLIENT_KEY} | base64 --decode > ${PWD}/.kube/client-key.crt

      ${KUBECTL} config set-cluster remote-cluster --server=${KUBE_SERVER} --certificate-authority=${PWD}/.kube/certificate-authority.crt
      ${KUBECTL} config set-credentials ${KUBE_AUTH_USER} --client-certificate=${PWD}/.kube/client-certificate.crt --client-key=${PWD}/.kube/client-key.crt

    elif [[ ${KUBE_AUTH_TYPE} == "token" ]]; then
      ${KUBECTL} config set-cluster remote-cluster --server=${KUBE_SERVER}
      ${KUBECTL} config set-credentials ${KUBE_AUTH_USER} --token="${KUBE_AUTH_TOKEN}"

    fi

    ${KUBECTL} config set-context ${KUBE_AUTH_USER}-context --cluster=remote-cluster --user=${KUBE_AUTH_USER}
    ${KUBECTL} config use-context ${KUBE_AUTH_USER}-context

  }

  function kube_cluster_logout {
    rm -rvf ${PWD}/.kube/*
  }
fi

. .gitlab-ci-functions/logger.sh

function kubernetes_namespace_sanitize () {
	if [ -z "$2" ]; then
		local LENGTH="62"
	else
		local LENGTH="$2"
	fi
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c $LENGTH | sed "s/-$//g" | tr -d '\n' | tr -d '\r'
}

function kubectl_namespace {
  ${KUBECTL} create namespace ${KUBE_NAMESPACE} --dry-run=client -o yaml | ${KUBECTL} apply -f -
  if [[ ${KUBE_RANCHER_NAMESPACE} == "true" ]]; then
    ${KUBECTL} annotate namespace ${KUBE_NAMESPACE} field.cattle.io/projectId="${KUBE_RANCHER_CLUSTER_ID}:${KUBE_RANCHER_PROJECT_ID}" --overwrite=true
  fi
}

function namespace_secret_project_registry {
	if [ -z "${CI_REGISTRY}" ]; then
		echo "ERROR: var CI_REGISTRY is empty"
		exit 1
	fi
	if [ -z "${CI_DEPLOY_USER}" ]; then
		echo "ERROR: var CI_DEPLOY_USER is empty"
		exit 1
	fi
	if [ -z "${CI_DEPLOY_PASSWORD}" ]; then
		echo "ERROR: var CI_DEPLOY_PASSWORD is empty"
		exit 1
	fi
	$KUBECTL -n $KUBE_NAMESPACE create secret docker-registry docker-registry-${CI_PROJECT_PATH_SLUG} \
		--docker-server=${CI_REGISTRY} --docker-username=${CI_DEPLOY_USER} --docker-password=${CI_DEPLOY_PASSWORD} --docker-email=${ADMIN_EMAIL} \
		-o yaml --dry-run=client | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_additional_project_registry () {
	local SAFE_REGISTRY_NAME=$(echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | sed "s/-$//g" | tr -d '\n' | tr -d '\r')
	$KUBECTL -n $KUBE_NAMESPACE create secret docker-registry docker-registry-${SAFE_REGISTRY_NAME} \
		--docker-server=${CI_REGISTRY} --docker-username=$2 --docker-password=$3 --docker-email=${ADMIN_EMAIL} \
		-o yaml --dry-run=client | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_acme_cert () {
  local SECRET_NAME="$1"
  local DNS_DOMAIN="$2"
  echo "Domain: ${DNS_DOMAIN}"

  if [[ ${ACME_MODE:=legacy} == "docker" ]]; then
    local ACME_DIR="${HOME}/.acme/${ACME_DOMAIN}-${ACME_ACCOUNT}-${ACME_CA_SERVER}"

    if [[ ! -d "${ACME_DIR}/.zerossl-register-account"  ]] && [[ ${ACME_CA_SERVER} == "zerossl" ]]; then
      docker run --rm -t \
        -v "${ACME_DIR}":/acme.sh \
        "${ACME_DOCKER_ENV_VARS[@]}" \
        neilpang/acme.sh:${ACME_DOCKER_VERSION:=latest} \
        --register-account -m "${ACME_ZEROSSL_EMAIL}"
      docker run --rm -t -v "${ACME_DIR}":/acme.sh alpine mkdir -pv "/acme.sh/.zerossl-register-account"
    fi

    if [[ ${ACME_ACCOUNT} == "cloudflare" ]]; then
      local ACME_DOCKER_ENV_VARS

      if [[ ${ACME_CLOUDFLARE_AUTH_TYPE:=email} == "email" ]]; then
        ACME_DOCKER_ENV_VARS=(
          -e CF_Email="${ACME_CLOUDFLARE_AUTH_EMAIL}"
          -e CF_Key="${ACME_CLOUDFLARE_AUTH_KEY}"
        )
      elif [[ ${ACME_CLOUDFLARE_AUTH_TYPE:=email} == "token" ]]; then
        ACME_DOCKER_ENV_VARS=(
          -e CF_Token="${ACME_CLOUDFLARE_AUTH_TOKEN}"
          -e CF_Account_ID="${ACME_CLOUDFLARE_AUTH_ACCOUNT_ID}"
        )
      elif [[ ${ACME_CLOUDFLARE_AUTH_TYPE:=email} == "zone" ]]; then
        ACME_DOCKER_ENV_VARS=(
          -e CF_Token="${ACME_CLOUDFLARE_AUTH_TOKEN}"
          -e CF_Account_ID="${ACME_CLOUDFLARE_AUTH_ACCOUNT_ID}"
          -e CF_Zone_ID="${ACME_CLOUDFLARE_AUTH_ZONE_ID}"
        )
      else
        echo "ACME_CLOUDFLARE_AUTH_TYPE not supported: ${ACME_CLOUDFLARE_AUTH_TYPE}. Only: email,token,zone"
        exit 1
      fi
        local ACME_EXIT_CODE=0
        docker run --rm  -t  \
          -v "${ACME_DIR}":/acme.sh \
          "${ACME_DOCKER_ENV_VARS[@]}" \
          neilpang/acme.sh:${ACME_DOCKER_VERSION:=latest} \
          --issue --domain "${DNS_DOMAIN}" \
          ${ACME_DOCKER_CLI_ARGS:=} \
          --dns dns_cf || ACME_EXIT_CODE=$?
        echo ACME exit code: ${ACME_EXIT_CODE}

        if [[ ${ACME_EXIT_CODE} != 2 ]] && [[ ${ACME_EXIT_CODE} != 0 ]]; then
          exit $ACME_EXIT_CODE;
        fi

    elif [[ ${ACME_ACCOUNT} == "clouddns" ]]; then
        local ACME_EXIT_CODE=0
        docker run --rm  -t  \
          -v "${ACME_DIR}":/acme.sh \
          -e CLOUDNS_AUTH_ID="${ACME_CLOUDNS_AUTH_ID}" \
          -e CLOUDNS_AUTH_PASSWORD="${ACME_CLOUDNS_AUTH_PASSWORD}" \
          neilpang/acme.sh:${ACME_DOCKER_VERSION:=latest} \
          --issue --domain "${DNS_DOMAIN}" \
          ${ACME_DOCKER_CLI_ARGS:=} \
          --dns dns_cloudns  || ACME_EXIT_CODE=$?
        echo ACME exit code: $ACME_EXIT_CODE

        if [[ ${ACME_EXIT_CODE} != 2 ]] && [[ ${ACME_EXIT_CODE} != 0 ]]; then
          exit $ACME_EXIT_CODE;
        fi

    else
      echo "ACME_ACCOUNT not supported: ${ACME_ACCOUNT}"
      exit 1
    fi
    docker run --rm  -t -v "${ACME_DIR}":/acme alpine /bin/sh -c "chown -R $(id -u):$(id -g) /acme"
    ${KUBECTL} -n ${KUBE_NAMESPACE} create secret tls ${SECRET_NAME} \
    --key=${ACME_DIR}/${DNS_DOMAIN}/${DNS_DOMAIN}.key \
    --cert=${ACME_DIR}/${DNS_DOMAIN}/fullchain.cer \
    -o yaml --dry-run=client | ${KUBECTL} -n ${KUBE_NAMESPACE} replace --force -f -
  else
    local DNS_SAFE_DOMAIN=$(echo "$2" | sed "s/*/./g")
    echo "Safe Domain: ${DNS_SAFE_DOMAIN}"
    local OPENSSL_RESULT=$(openssl verify -CAfile /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_ca.cer /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer 2>&1 || true)
    echo "OpenSSL cert:"
    echo $OPENSSL_RESULT
    echo "---"
    ( echo $OPENSSL_RESULT | grep -i -e error ) || true
    echo "---"
    if echo $OPENSSL_RESULT | grep -q -i -e error; then
      /opt/acme/home/acme_local.sh \
        --cert-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_cert.cer \
        --key-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_key.key \
        --ca-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_ca.cer \
        --fullchain-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer \
        --issue -d "${DNS_DOMAIN}"
    else
      echo "Domain verified - OK"
    fi
    ${KUBECTL} -n ${KUBE_NAMESPACE} create secret tls ${SECRET_NAME} \
      --key=/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_key.key \
      --cert=/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer \
      -o yaml --dry-run=client | ${KUBECTL} -n ${KUBE_NAMESPACE} replace --force -f -
  fi
}

function helm_init_namespace {
	$HELM repo add stable https://charts.helm.sh/stable
	$HELM repo add bitnami https://charts.bitnami.com/bitnami
	$HELM repo update
}

function helm_additional_repo {
	$HELM repo add $1 $2
	$HELM repo update
}

function helm_uninstall () {
	# do not prefix OUT vars with local or exit code will be wrong
	HELM_OUT=$($HELM uninstall --namespace $KUBE_NAMESPACE $1 2>&1) && HELM_EXIT_CODE=0 || HELM_EXIT_CODE=1
	echo Helm exit code: $HELM_EXIT_CODE
	echo $HELM_OUT
	if [[ $HELM_EXIT_CODE != 0 ]]; then
		if echo $HELM_OUT | grep -q "Error: uninstall: Release not loaded:.*: release: not found"; then
			echo Error: uninstall: Release not loaded: arised, probably there was no chart installed, and it is ok, ignoring
			true
		else
			false
		fi
	fi
}

function helm_deploy () {
	# do not prefix OUT vars with local or exit code will be wrong
	HELM_OUT=$($HELM upgrade --wait --wait-for-jobs --namespace $KUBE_NAMESPACE --install $1 --set image.tag=$2 .helm/$1 $3 2>&1) && HELM_EXIT_CODE=0 || HELM_EXIT_CODE=1
	echo Helm exit code: $HELM_EXIT_CODE
	echo $HELM_OUT
	if [[ $HELM_EXIT_CODE != 0 ]]; then
		if echo $HELM_OUT | grep -q "Error: release: already exists"; then
			echo Error: release: already exists arised, probably it was created by parallel job, and it is ok, ignoring
			true
		elif echo $HELM_OUT | grep -q "Error: UPGRADE FAILED: another operation.*is in progress"; then
			sleep 30
			helm_deploy "$1" "$2" "$3"
		else
			false
		fi
	fi
}

function helm_deploy_from_dir () {
	# do not prefix OUT vars with local or exit code will be wrong
	HELM_OUT=$($HELM upgrade --wait --wait-for-jobs --namespace $KUBE_NAMESPACE --install $2 --set image.tag=$3 $1/.helm/$2 $4 2>&1) && HELM_EXIT_CODE=0 || HELM_EXIT_CODE=1
	echo Helm exit code: $HELM_EXIT_CODE
	echo $HELM_OUT
	if [[ $HELM_EXIT_CODE != 0 ]]; then
		if echo $HELM_OUT | grep -q "Error: release: already exists"; then
			echo Error: release: already exists arised, probably it was created by parallel job, and it is ok, ignoring
			true
		elif echo $HELM_OUT | grep -q "Error: UPGRADE FAILED: another operation.*is in progress"; then
			sleep 30
			helm_deploy_from_dir "$1" "$2" "$3" "$4"
		else
			false
		fi
	fi
}

function helm_deploy_by_name_with_config () {
	# do not prefix OUT vars with local or exit code will be wrong
	HELM_OUT=$($HELM upgrade --wait --wait-for-jobs --namespace $KUBE_NAMESPACE --install $1 -f $3 $2 $4 2>&1) && HELM_EXIT_CODE=0 || HELM_EXIT_CODE=1
	echo Helm exit code: $HELM_EXIT_CODE
	echo $HELM_OUT
	if [[ $HELM_EXIT_CODE != 0 ]]; then
		if echo $HELM_OUT | grep -q "Error: release: already exists"; then
			echo Error: release: already exists arised, probably it was created by parallel job, and it is ok, ignoring
			true
		elif echo $HELM_OUT | grep -q "Error: UPGRADE FAILED: another operation.*is in progress"; then
			sleep 30
			helm_deploy_by_name_with_config "$1" "$2" "$3" "$4"
		else
			false
		fi
	fi
}

function kubectl_wait_for_deployment_and_exec_in_container_of_first_running_pod () {
	local RETRIES=1
	if [ $1 -le 2 ]; then
		local RETRIES_MAX=2
	else
		local RETRIES_MAX=$1
	fi
	local SLEEP_TIME=5
	local DEPLOYMENT="$2"
	local CONTAINER="$3"
	local COMMAND="$4"
	until $KUBECTL -n $KUBE_NAMESPACE rollout status deploy/${DEPLOYMENT} | grep -q "successfully rolled out" || (( RETRIES == RETRIES_MAX ))
	do
		echo .
		let "RETRIES++"
		sleep ${SLEEP_TIME}
	done
	if [ ${RETRIES} -eq ${RETRIES_MAX} ]; then
		echo "ERROR: Deployment rollout timeout"
		exit 1
	fi
	local POD=$(${KUBECTL} -n $KUBE_NAMESPACE get pods --selector=app.kubernetes.io/name=${DEPLOYMENT} | grep "Running"  | head -n 1 | awk '{print $1}')
	echo "POD: ${POD}"
	$KUBECTL -n $KUBE_NAMESPACE exec $POD -c $CONTAINER -- $COMMAND
}

function kubectl_wait_for_deployment_and_exec_base64_cmd_in_container_of_first_running_pod () {
	local RETRIES=1
	if [ $1 -le 2 ]; then
		local RETRIES_MAX=2
	else
		local RETRIES_MAX=$1
	fi
	local SLEEP_TIME=5
	local DEPLOYMENT="$2"
	local CONTAINER="$3"
	local COMMAND="$4"
	until $KUBECTL -n $KUBE_NAMESPACE rollout status deploy/${DEPLOYMENT} | grep -q "successfully rolled out" || (( RETRIES == RETRIES_MAX ))
	do
		echo .
		let "RETRIES++"
		sleep ${SLEEP_TIME}
	done
	if [ ${RETRIES} -eq ${RETRIES_MAX} ]; then
		echo "ERROR: Deployment rollout timeout"
		exit 1
	fi
	local POD=$($KUBECTL -n $KUBE_NAMESPACE get pods --selector=app.kubernetes.io/name=${DEPLOYMENT} | grep "Running"  | head -n 1 | awk '{print $1}')
	echo "POD: ${POD}"
	$KUBECTL -n $KUBE_NAMESPACE exec $POD -c $CONTAINER -- bash -c "echo "$COMMAND" | base64 -d | bash"
}

function kubectl_cp_container_of_first_running_pod () {
	local DEPLOYMENT="$1"
	local CONTAINER="$2"
	local DIR_FROM="$3"
	local DIR_TO="$4"
	local POD=$($KUBECTL -n $KUBE_NAMESPACE get pods --selector=app.kubernetes.io/name=${DEPLOYMENT} | grep "Running"  | head -n 1 | awk '{print $1}')
	$KUBECTL cp -c $CONTAINER $KUBE_NAMESPACE/$POD:$DIR_FROM $DIR_TO
}


function helm_lock {
	echo "NOTICE: Helm is parallel jobs safe now, you can safely remove helm_lock/helm_unlock calls"
}

function helm_unlock {
	echo "NOTICE: Helm is parallel jobs safe now, you can safely remove helm_lock/helm_unlock calls"
}

watching_pods_containers_logs_file=false
watching_pods_events_file=false

function kubectl_cleanup() {
  echo "kubectl cleanup"
  for PARENT in $(jobs -pr); do
    for PARENT_PARENT in $(ps -o pid= --ppid $PARENT); do
        for PARENT_PARENT_PARENT in $(ps -o pid= --ppid $PARENT_PARENT); do
          ps -o pid= --ppid $PARENT_PARENT_PARENT | xargs -r kill -9  || true
        done
      ps -o pid= --ppid $PARENT_PARENT | xargs -r kill -9  || true
    done
    ps -o pid= --ppid $PARENT | xargs -r kill -9  || true
  done
  jobs -pr | xargs -r kill || true
  rm -vf "${watching_pods_containers_logs_file}" "${watching_pods_events_file}" || true

}


function kubectl_watch_pods() {
  local release="$1"

  sleep 3 # Prevent flodding the logs with the initial output
  log_command kubectl get pods --namespace ${KUBE_NAMESPACE} --watch --selector "app.kubernetes.io/instance=${release}"
  log_prefix_output "pods" "1;32" ${KUBECTL} get pods \
    --namespace ${KUBE_NAMESPACE} \
    --watch \
    --selector "app.kubernetes.io/instance=${release}"

}

function kubectl_watch_pod_logs() {
  local pod="$1"
  local container=`echo $2 | tr -d '"'`

  if grep -q "^${pod}-${container}" "${watching_pods_containers_logs_file}"; then
    return
  fi

  echo "${pod}-${container}" >> "${watching_pods_containers_logs_file}"

  log_command kubectl logs --namespace ${KUBE_NAMESPACE} --container ${container} --follow "${pod}"
  # pod ${pod} logs
  log_prefix_output "logs ${pod} [${container}]" "0;34" ${KUBECTL} logs \
    --namespace ${KUBE_NAMESPACE} \
    --container ${container} \
    --follow \
    "${pod}" || true

  # remove from watch list (it may be added again)
  sed -i "/^${pod}-${container}$/d" "${watching_pods_containers_logs_file}"
}

function kubectl_watch_pod_events() {
  local pod="$1"

  if grep -q "^${pod}$" "${watching_pods_events_file}"; then
    return
  fi

  echo "${pod}" >>"${watching_pods_events_file}"

  log_command kubectl get events  --namespace ${KUBE_NAMESPACE} --watch-only --field-selector involvedObject.name="${pod}"
  log_prefix_output "pod ${pod} events" "0;35" ${KUBECTL} get events \
    --namespace ${KUBE_NAMESPACE} \
    --watch-only \
    --field-selector involvedObject.name="${pod}" || true

  # remove from watch list (it may be added again)
  sed -i "/^${pod}$/d" "${watching_pods_events_file}"
}

function kubectl_watch_pods_logs_and_events() {
  local release="$1"

  sleep 5 # Prevent flodding the logs with the initial output
  while [[ -f ${watching_pods_containers_logs_file} ]]; do
    local podFilters=(
      --selector "app.kubernetes.io/instance=${release}"
      --output jsonpath='{.items[*].metadata.name}'
    )

    for pod in $(
      ${KUBECTL} get pods --namespace ${KUBE_NAMESPACE} "${podFilters[@]}"
    ); do
      kubectl_watch_pod_events "${pod}" &
    done

    for pod in $(
      ${KUBECTL} get pods \
        --namespace ${KUBE_NAMESPACE} \
        "${podFilters[@]}"
    ); do
      for initContainer in $(
        ${KUBECTL} get pods \
          --namespace ${KUBE_NAMESPACE} \
          --output jsonpath='{.status.initContainerStatuses}' ${pod} |  jq '.[] | select(.state.running) | .name'
      ); do
        kubectl_watch_pod_logs "${pod}" "${initContainer}"  &
      done
      for container in $(
        ${KUBECTL} get pods \
          --namespace ${KUBE_NAMESPACE} \
          --output jsonpath='{.status.containerStatuses}' ${pod} |  jq '.[] | select(.state.running) | .name'
      ); do
        kubectl_watch_pod_logs "${pod}" "${container}"  &
      done
    done

    sleep 1

  done
}

function get_first_non_option() {
  for arg in "$@"; do
    if [[ "${arg}" != "-"* ]]; then
      echo "${arg}"
      return
    fi
  done
}


function helm_upgrade_watch_logs_events() {
  watching_pods_containers_logs_file=$(mktemp /dev/shm/helm-upgrade-logs.watching-pods-containers-logs.XXXXXX)
  watching_pods_events_file=$(mktemp /dev/shm/helm-upgrade-logs.watching-pods-events.XXXXXX)
  echo "Creating ${watching_pods_containers_logs_file}"
  echo "Creating ${watching_pods_events_file}"

  local HELM_RELEASE_NAME="$(get_first_non_option "$@")"
  local HELM_CMD=" upgrade --atomic --wait"
  if [[ ${HELM_DEBUG:-false} == "true" ]]; then
    HELM_CMD=${HELM_CMD}" --debug"
  fi
  if [[ ${HELM_DRY_RUN:-false} == "true" ]]; then
    HELM_CMD=${HELM_CMD}" --dry-run"
  fi

  stdbuf -oL -eL ${HELM} ${HELM_CMD} --namespace ${KUBE_NAMESPACE} "$@" &
  local pid="$!"
  kubectl_watch_pods "${HELM_RELEASE_NAME}" &
  kubectl_watch_pods_logs_and_events "${HELM_RELEASE_NAME}" &

  wait "${pid}"

  kubectl_cleanup
}
