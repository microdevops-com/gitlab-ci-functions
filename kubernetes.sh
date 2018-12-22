#!/bin/bash

DOCKER="docker --config=./docker-config"

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	rm -rf ./docker-config
	echo "$CI_JOB_TOKEN" | $DOCKER login --username "$CI_REGISTRY_USER" "$CI_REGISTRY" --password-stdin
}
