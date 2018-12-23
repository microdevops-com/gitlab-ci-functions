#!/bin/bash

KUBECTL="kubectl --server=$KUBE_SERVER --token=$KUBE_TOKEN"
RANCHER="rancher"
RANCHER_DIR="$HOME/.rancher"
RANCHER_LOCK_DIR="$HOME/.rancher/.lock"
RANCHER_LOCK_RETRIES=1
RANCHER_LOCK_RETRIES_MAX=60
RANCHER_LOCK_SLEEP_TIME=5
HELM="helm --kubeconfig ./.helm/cluster.yml --home ./.helm"

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p "$CI_JOB_TOKEN" "$CI_REGISTRY"
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
	$RANCHER namespace | grep -q "$KUBE_NAMESPACE\s*$KUBE_NAMESPACE" || $RANCHER namespace create "$KUBE_NAMESPACE"
}

function namespace_secret_project_registry {
	$KUBECTL -n $KUBE_NAMESPACE create secret docker-registry docker-registry-${CI_PROJECT_PATH_SLUG} \
		--docker-server=${CI_REGISTRY} --docker-username=${CI_DEPLOY_USER} --docker-password=${CI_DEPLOY_PASSWORD} --docker-email=${ADMIN_EMAIL} \
		-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
}

function namespace_secret_rabbitmq () {
	$KUBECTL -n $KUBE_NAMESPACE create secret generic $1 \
		--from-literal=RABBITMQ_HOST="$RABBITMQ_HOST" --from-literal=RABBITMQ_PORT="$RABBITMQ_PORT" --from-literal=RABBITMQ_USER="$RABBITMQ_USER" --from-literal=RABBITMQ_PASS="$RABBITMQ_PASS" --from-literal=RABBITMQ_VHOST="$RABBITMQ_VHOST" \
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
		$KUBECTL -n $KUBE_NAMESPACE delete deployment tiller-deploy
		$KUBECTL -n $KUBE_NAMESPACE create serviceaccount tiller \
			-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
		$KUBECTL -n $KUBE_NAMESPACE create rolebinding tiller-namespace-admin --clusterrole=admin --serviceaccount=tc-deploy:tiller \
			-o yaml --dry-run | $KUBECTL -n $KUBE_NAMESPACE replace --force -f -
		$HELM init --upgrade --tiller-namespace $KUBE_NAMESPACE --service-account tiller
		until $KUBECTL -n $KUBE_NAMESPACE rollout status deploy/tiller-deploy | grep -q "successfully rolled out"; do echo .; done
	fi
}

function helm_deploy () {
	$HELM upgrade --tiller-namespace $KUBE_NAMESPACE --namespace $KUBE_NAMESPACE --recreate-pods --install $1 --set image.tag=$2 .helm/$1
}
