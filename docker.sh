#!/bin/bash

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p "$CI_JOB_TOKEN" "$CI_REGISTRY"
}

function docker_build_dir () {
	if [ -z "$3" ]; then
		cd $2 && docker build --pull -t $1 .
	else
		cd $2 && docker build --pull -t $1 --build-arg CI_COMMIT_REF_NAME=$3 .
	fi
}

function docker_build_file () {
	if [ -z "$3" ]; then
		docker build --pull -t $1 -f $2 .
	else
		docker build --pull -t $1 -f $2 --build-arg CI_COMMIT_REF_NAME=$3 .
	fi
}
