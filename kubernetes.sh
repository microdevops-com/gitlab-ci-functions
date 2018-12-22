#!/bin/bash

function registry_login {
	# make docker config per workspace (instead of gitlab-runner home)
	echo "$CI_JOB_TOKEN" | docker --config=./docker-config login -u "$CI_REGISTRY_USER" "$CI_REGISTRY" --password-stdin
}
