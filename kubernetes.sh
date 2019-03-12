#!/bin/bash

KUBECTL="kubectl --server=$KUBE_SERVER --token=$KUBE_TOKEN"
RANCHER="rancher"
RANCHER_DIR="$HOME/.rancher"
RANCHER_LOCK_DIR="$HOME/.rancher/.lock"
RANCHER_LOCK_RETRIES=1
RANCHER_LOCK_RETRIES_MAX=60
RANCHER_LOCK_SLEEP_TIME=5
HELM="helm --kubeconfig ./.helm/cluster.yml --home ./.helm"

function kubernetes_namespace_sanitize () {
	echo $1 | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g" | head -c 62
}

function kubectl_namespace {
	$KUBECTL describe namespace "$KUBE_NAMESPACE" || $KUBECTL create namespace "$KUBE_NAMESPACE"
}

function rancher_login {
	mkdir -p $RANCHER_DIR
	$RANCHER login "$KUBE_SERVER" --token "$KUBE_TOKEN"
}

# Rancher CLI is not concurrant, lock usage
function rancher_lock {
	mkdir -p $RANCHER_DIR
	until mkdir "$RANCHER_LOCK_DIR" || (( RANCHER_LOCK_RETRIES == RANCHER_LOCK_RETRIES_MAX ))
	do
		echo "NOTICE: Acquiring lock failed on $RANCHER_LOCK_DIR, sleeping for ${RANCHER_LOCK_SLEEP_TIME}s"
		let "RANCHER_LOCK_RETRIES++"
		sleep ${RANCHER_LOCK_SLEEP_TIME}
	done
	if [ ${RANCHER_LOCK_RETRIES} -eq ${RANCHER_LOCK_RETRIES_MAX} ]; then
		echo "ERROR: Cannot acquire lock after ${RANCHER_LOCK_RETRIES} retries, giving up on $RANCHER_LOCK_DIR"
		exit 1
	else
		echo "NOTICE: Successfully acquired lock on $RANCHER_LOCK_DIR"
	fi	
}

function rancher_unlock {
	rm -rf "$RANCHER_LOCK_DIR"
	echo "NOTICE: Successfully removed lock on $RANCHER_LOCK_DIR"
}

function rancher_logout {
	rm -f $RANCHER_DIR/*
}

function rancher_namespace {
	echo "KUBE_NAMESPACE: $KUBE_NAMESPACE"
	$RANCHER namespace | grep -q "$KUBE_NAMESPACE\s*$KUBE_NAMESPACE" || $RANCHER namespace create "$KUBE_NAMESPACE"
}

function namespace_secret_project_registry {
	$KUBECTL -n $KUBE_NAMESPACE create secret docker-registry docker-registry-${CI_PROJECT_PATH_SLUG} \
		--docker-server=${CI_REGISTRY} --docker-username=${CI_DEPLOY_USER} --docker-password=${CI_DEPLOY_PASSWORD} --docker-email=${ADMIN_EMAIL} \
		-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_additional_project_registry () {
	$KUBECTL -n $KUBE_NAMESPACE create secret docker-registry docker-registry-$1 \
		--docker-server=${CI_REGISTRY} --docker-username=$2 --docker-password=$3 --docker-email=${ADMIN_EMAIL} \
		-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_rabbitmq () {
	$KUBECTL -n $KUBE_NAMESPACE create secret generic $1 \
		--from-literal=RABBITMQ_HOST="$RABBITMQ_HOST" --from-literal=RABBITMQ_PORT="$RABBITMQ_PORT" --from-literal=RABBITMQ_USER="$RABBITMQ_USER" --from-literal=RABBITMQ_PASS="$RABBITMQ_PASS" --from-literal=RABBITMQ_VHOST="$RABBITMQ_VHOST" \
		-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_acme_cert () {
	local SECRET_NAME="$1"
	local DNS_DOMAIN="$2"
	local DNS_SAFE_DOMAIN=$(echo "$2" | sed "s/*/./g")
	openssl verify -CAfile \
		/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_ca.cer \
		/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer 2>&1 \
		| grep -q -i -e error; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh \
		--cert-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_cert.cer \
		--key-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_key.key \
		--ca-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_ca.cer \
		--fullchain-file /opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer \
		--issue -d "${DNS_DOMAIN}" || true
	$KUBECTL -n $KUBE_NAMESPACE create secret generic $1 \
		--from-file=/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_key.key \
		--from-file=/opt/acme/cert/domain_${DNS_SAFE_DOMAIN}_fullchain.cer \
		-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function helm_cluster_login {
	mkdir -p ./.helm
	cat <<- EOF > ./.helm/cluster.yml
	apiVersion: v1
	kind: Config
	clusters:
	- name: "remote-cluster"
	  cluster:
	    server: "$KUBE_SERVER"
	    api-version: v1

	users:
	- name: "user-gvnrn"
	  user:
	    token: "$KUBE_TOKEN"

	contexts:
	- name: "remote-cluster"
	  context:
	    user: "user-gvnrn"
	    cluster: "remote-cluster"

	current-context: "remote-cluster"	
	EOF
}

# We shouldn't leave credentials in the workspace as they may change
function helm_cluster_logout {
	rm -f ./.helm/cluster.yml
}

function helm_init_namespace {
	if ! $HELM ls --namespace $KUBE_NAMESPACE --tiller-namespace $KUBE_NAMESPACE; then
		$KUBECTL -n $KUBE_NAMESPACE delete deployment tiller-deploy || true
		$KUBECTL -n $KUBE_NAMESPACE create serviceaccount tiller \
			-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
		$KUBECTL -n $KUBE_NAMESPACE create rolebinding tiller-namespace-admin --clusterrole=admin --serviceaccount=${KUBE_NAMESPACE}:tiller \
			-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
		$HELM init --upgrade --tiller-namespace $KUBE_NAMESPACE --service-account tiller
		until $KUBECTL -n $KUBE_NAMESPACE rollout status deploy/tiller-deploy | grep -q "successfully rolled out"; do echo .; done
	fi
}

function helm_deploy () {
	$HELM upgrade --tiller-namespace $KUBE_NAMESPACE --namespace $KUBE_NAMESPACE --recreate-pods --install $1 --set image.tag=$2 .helm/$1 $3
}

function helm_deploy_from_dir () {
	$HELM upgrade --tiller-namespace $KUBE_NAMESPACE --namespace $KUBE_NAMESPACE --recreate-pods --install $2 --set image.tag=$3 $1/.helm/$2 $4
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
	local POD=$($KUBECTL -n $KUBE_NAMESPACE get pods --selector=app.kubernetes.io/name=${DEPLOYMENT} | grep "Running"  | head -n 1 | awk '{print $1}')
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
