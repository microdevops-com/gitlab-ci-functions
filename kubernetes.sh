#!/bin/bash

export DOCKER="docker --config=./docker-config"
export CI_JOB_TOKEN
export CI_REGISTRY_USER
export CI_REGISTRY

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	rm -rf ./docker-config
	echo "$CI_JOB_TOKEN" | $DOCKER login -u "$CI_REGISTRY_USER" "$CI_REGISTRY" --password-stdin
}
