#!/bin/bash

function downstream_repo_lock () {
	local DOWNSTREAM=$1

	local DOWNSTREAM_REPO_DIR="${HOME}/.downstream_repo"
	local DOWNSTREAM_SAFE=$(echo ${DOWNSTREAM} | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g)
	local DOWNSTREAM_REPO_LOCK_DIR="${DOWNSTREAM_REPO_DIR}/${DOWNSTREAM_SAFE}.${CI_COMMIT_REF_SLUG}.lock"
	local DOWNSTREAM_REPO_LOCK_RETRIES=1
	local DOWNSTREAM_REPO_LOCK_RETRIES_MAX=60
	local DOWNSTREAM_REPO_LOCK_SLEEP_TIME=5

	mkdir -p ${DOWNSTREAM_REPO_DIR}
	until mkdir "${DOWNSTREAM_REPO_LOCK_DIR}" || (( DOWNSTREAM_REPO_LOCK_RETRIES == DOWNSTREAM_REPO_LOCK_RETRIES_MAX )); do
		echo "NOTICE: Acquiring lock failed on ${DOWNSTREAM_REPO_LOCK_DIR}, sleeping for ${DOWNSTREAM_REPO_LOCK_SLEEP_TIME}s"
		let "DOWNSTREAM_REPO_LOCK_RETRIES++"
		sleep ${DOWNSTREAM_REPO_LOCK_SLEEP_TIME}
	done
	if [ ${DOWNSTREAM_REPO_LOCK_RETRIES} -eq ${DOWNSTREAM_REPO_LOCK_RETRIES_MAX} ]; then
		echo "ERROR: Cannot acquire lock after ${DOWNSTREAM_REPO_LOCK_RETRIES} retries, giving up on ${DOWNSTREAM_REPO_LOCK_DIR}"
		exit 1
	else
		echo "NOTICE: Successfully acquired lock on ${DOWNSTREAM_REPO_LOCK_DIR}"
	fi
}

function downstream_repo_unlock () {
	local DOWNSTREAM=$1

	local DOWNSTREAM_REPO_DIR="${HOME}/.downstream_repo"
	local DOWNSTREAM_SAFE=$(echo ${DOWNSTREAM} | sed -r s/[^a-zA-Z0-9]+/-/g | sed -r s/^-+\|-+$//g)
	local DOWNSTREAM_REPO_LOCK_DIR="${DOWNSTREAM_REPO_DIR}/${DOWNSTREAM_SAFE}.${CI_COMMIT_REF_SLUG}.lock"

	rm -rf "${DOWNSTREAM_REPO_LOCK_DIR}"
	echo "NOTICE: Successfully removed lock on ${DOWNSTREAM_REPO_LOCK_DIR}"
}

function get_tmp_git_repo_dir () {
	export GIT_REPO_DIR=$(mktemp -d -t git.XXXXXXXXXX)
}

function git_init_and_set_remote_to_downstream_repo () {
	local DOWNSTREAM=$1

	if [ -z "${GIT_REPO_DIR}" ]; then echo "ERROR: GIT_REPO_DIR var not set"; exit 1; fi

	pushd ${GIT_REPO_DIR}
	git init
	git remote add downstream ${DOWNSTREAM}
	git checkout -b ${CI_COMMIT_REF_NAME}
	popd
}

function copy_to_repo_as_root_dir () {
	local ADD="$1"

	if [ -z "${GIT_REPO_DIR}" ]; then echo "ERROR: GIT_REPO_DIR var not set"; exit 1; fi

	rsync -a ${ADD}/ ${GIT_REPO_DIR}/
}

function git_add_submodule () {
	local SUBM_NAME="$1"
	local SUBM_BRANCH="$2"
	local SUBM_URL="$3"
	local SUBM_PATH="$4"

	if [ -z "${GIT_REPO_DIR}" ]; then echo "ERROR: GIT_REPO_DIR var not set"; exit 1; fi

	pushd ${GIT_REPO_DIR}
	git submodule add --name ${SUBM_NAME} -b ${SUBM_BRANCH} -- ${SUBM_URL} ${SUBM_PATH}
	popd
}

function git_force_push_and_rm_tmp_git_repo () {
	local COMMIT_NAME="$1"
	local COMMIT_EMAIL="$2"

	if [ -z "${GIT_REPO_DIR}" ]; then echo "ERROR: GIT_REPO_DIR var not set"; exit 1; fi

	pushd ${GIT_REPO_DIR}
	git add -A
	git -c "user.name=${COMMIT_NAME}" -c "user.email=${COMMIT_EMAIL}" commit -m "Force push from upstream repo"
	git push --set-upstream downstream ${CI_COMMIT_REF_NAME} -f
	popd
	rm -rf ${GIT_REPO_DIR}
}
