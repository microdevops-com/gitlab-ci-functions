#!/bin/bash

KUBECTL="kubectl --server=$KUBE_SERVER --token=$KUBE_TOKEN"
KUBE_NAMESPACE=$(echo $KUBE_NAMESPACE| tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p $CI_JOB_TOKEN $CI_REGISTRY
}

function ensure_namespace {
	$KUBECTL describe namespace "$KUBE_NAMESPACE" || $KUBECTL create namespace "$KUBE_NAMESPACE"
}
