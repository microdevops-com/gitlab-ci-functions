#!/bin/bash

KUBE_NAMESPACE=$(echo $KUBE_NAMESPACE| tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")
KUBECTL="kubectl --server=$KUBE_SERVER --token=$KUBE_TOKEN"
RANCHER="rancher"
RANCHER_DIR="$HOME/.rancher"
RANCHER_LOCK_DIR="$HOME/.rancher/.lock"
RANCHER_LOCK_RETRIES=1
RANCHER_LOCK_RETRIES_MAX=60
RANCHER_LOCK_SLEEP_TIME=5

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p "$CI_JOB_TOKEN" "$CI_REGISTRY"
}

function ensure_namespace {
	$KUBECTL describe namespace "$KUBE_NAMESPACE" || $KUBECTL create namespace "$KUBE_NAMESPACE"
}

function rancher_login {
	rancher login "$KUBE_SERVER" --token "$KUBE_TOKEN"
}

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
		trap 'rm -rf "$RANCHER_LOCK_DIR"' 0
	fi	
}
