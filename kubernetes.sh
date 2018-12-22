#!/bin/bash

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	docker --config=./docker-config login -u gitlab-ci-token -p $CI_JOB_TOKEN $CI_REGISTRY
}
