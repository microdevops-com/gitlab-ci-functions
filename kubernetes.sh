#!/bin/bash

export DOCKER="docker --config=./docker-config"

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	echo "$CI_JOB_TOKEN" | $DOCKER login -u "$CI_REGISTRY_USER" "$CI_REGISTRY" --password-stdin
}
