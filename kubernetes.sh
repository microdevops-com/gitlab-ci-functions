#!/bin/bash

DOCKER="docker --config=./docker-config"

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	rm -rf ./docker-config
	$DOCKER login -u gitlab-ci-token -p $CI_JOB_TOKEN $CI_REGISTRY
}
