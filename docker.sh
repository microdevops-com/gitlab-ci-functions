#!/bin/bash

# store docker login creds in job CWD, so parallel jobs can access registry with own job token
# better to use full path if cd changed
export DOCKER_CONFIG=$PWD/.docker

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p "$CI_JOB_TOKEN" "$CI_REGISTRY"
}

function registry_param_login {
	echo DOCKER: login into regisrty $1
	echo $3 | docker login --username $2 --password-stdin $1
}

function docker_build_dir () {
	if [ -z "$3" ]; then
		echo CMD: docker build --pull -t $1 .
		pushd $2 && docker build --pull -t $1 . && popd
	else
		echo CMD: docker build --pull -t $1 --build-arg CI_COMMIT_REF_SLUG=$3 .
		pushd $2 && docker build --pull -t $1 --build-arg CI_COMMIT_REF_SLUG=$3 . && popd
	fi
}

function docker_build_file () {
	if [ -z "$3" ]; then
		echo CMD: docker build --pull -t $1 -f $2 .
		docker build --pull -t $1 -f $2 .
	else
		echo CMD: docker build --pull -t $1 -f $2 --build-arg CI_COMMIT_REF_SLUG=$3 .
		docker build --pull -t $1 -f $2 --build-arg CI_COMMIT_REF_SLUG=$3 .
	fi
}

function docker_build_dir_args () {
	echo CMD: docker build --pull -t $1 $3 .
	pushd $2 && bash -c "docker build --pull -t $1 $3 ." && popd
}

function docker_build_file_args () {
	echo CMD: docker build --pull -t $1 -f $2 $3 .
	bash -c "docker build --pull -t $1 -f $2 $3 ."
}
