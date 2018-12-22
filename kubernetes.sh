#!/bin/bash

KUBECTL="kubectl --server=$KUBE_SERVER --token=$KUBE_TOKEN"

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p $CI_JOB_TOKEN $CI_REGISTRY
}

function ensure_namespace {
	$KUBECTL describe namespace "$KUBE_NAMESPACE" || $KUBECTL create namespace "$KUBE_NAMESPACE"
}
