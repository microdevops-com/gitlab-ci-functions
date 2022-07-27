#!/bin/bash

function gitlab_trigger_pipeline_and_wait_success () {
	# !!!
	# This func is not needed anymore. Use parent-child pipelines with "strategy: depend".

	# While CI_JOB_TOKEN or trigger token allow you to trigger pipeline, they do not allow to get status of the pipeline.
	# So you need to use private token with api instead - insecure but no other way yet:
	# https://gitlab.com/gitlab-org/gitlab-ce/issues/39640 .
	# It is better to add new user and use it's token, bot admin's. Add user to projects as Guest.
	# While private token or trigger token also can be used to trigger token, GitLab will not show Downstream if they are used. Only CI_JOB_TOKEN produces downstream graph.

	local GITLAB_URL="$1"
	# Substitute / in project id if namespace used with url safe symbols
	local PROJECT_ID="$(echo $2 | sed -e 's#/#%2F#g')"
	local REF="$3"
	local VARIABLES="$4"
	local PRIVATE_TOKEN="$5"
	
	local CURL_CMD="curl --request POST --form token=$CI_JOB_TOKEN --form ref=$REF $VARIABLES $GITLAB_URL/api/v4/projects/$PROJECT_ID/trigger/pipeline"
	
	# Echo curl command
	echo $CURL_CMD
	# Trigger pipeline and save output
	CURL_OUT=$($CURL_CMD)
	# Debug output
	echo $CURL_OUT
	# Check typical errors in output and fail job if any
	(echo $CURL_OUT | grep -q "Insufficient permissions") && exit 1 || true
	# Get pipline id
	PIPELINE_ID=$(echo $CURL_OUT | jq -r .id)
	# Check if pipeline id is int
	if [[ ! $PIPELINE_ID =~ ^-?[0-9]+$ ]]; then
		echo "ERROR: id($PIPELINE_ID) is not int"
		exit 1
	fi
	# Get pipeline status
	while true; do
		sleep 2
		CURL_OUT=$(curl --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" $GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID)
		# Debug output
		echo $CURL_OUT
		# Get status of pipeline
		PIPELINE_STATUS=$(echo $CURL_OUT | jq -r .status)
		echo "Status: $PIPELINE_STATUS"
		# Exit with OK on success
		if [[ "_${PIPELINE_STATUS}" = "_success" ]]; then
			break
		fi
		# Wait on pending or running
		if [[ "_${PIPELINE_STATUS}" = "_pending" ]]; then
			continue
		fi
		if [[ "_${PIPELINE_STATUS}" = "_running" ]]; then
			continue
		fi
		if [[ "_${PIPELINE_STATUS}" = "_created" ]]; then
			continue
		fi
		
		# All other statuses or anything else - error
		echo "ERROR: status($PIPELINE_STATUS) is unknown to wait any longer"
		exit 1
	done
	echo "NOTICE: Successfully finished pipeline"
}

function clean_build_dir () {
	if [ -n "$1" ]; then
		if [ -n "${CI_PROJECT_DIR}" ]; then
			find "${CI_PROJECT_DIR}" -mindepth 1 -maxdepth 1 -not -path "$1" -print0 | xargs -0 rm -rf
		fi
	else
		if [ -n "${CI_PROJECT_DIR}" ]; then
			find "${CI_PROJECT_DIR}" -mindepth 1 -maxdepth 1 -print0 | xargs -0 rm -rf
		fi
	fi
}

function runner_resource_lock () {
	# Resource Groups work only within one project. When using multiple projects with the same non-concurrant resource additional locks needed.
	# https://docs.gitlab.com/ee/ci/yaml/#resource_group
	# https://gitlab.com/gitlab-org/gitlab/-/issues/122010
	# https://gitlab.com/gitlab-org/gitlab/-/issues/39057 (13.9 milestone expected)
	# For better cross project cross runner locks something like https://github.com/joanvila/aioredlock should be used.

	# In case of job cancellation lock will not be removed. after_job will help as well - it is not runned on cancellation.
	# So wait for timeout and remove lock with no error. Let the non-concurrant code report the error.

	local RESOURCE_NAME="$1"
	local RESOURCE_LOCK_DIR="${HOME}/.resource_lock"
	local RESOURCE_LOCK_LOCK_DIR="${RESOURCE_LOCK_DIR}/${RESOURCE_NAME}.lock"
	local RESOURCE_LOCK_LOCK_RETRIES=1
	local RESOURCE_LOCK_LOCK_RETRIES_MAX=$2

	mkdir -p ${RESOURCE_LOCK_DIR}
	echo "NOTICE: Waiting for lock ${RESOURCE_LOCK_LOCK_DIR}: "
	until mkdir "${RESOURCE_LOCK_LOCK_DIR}" > /dev/null 2>&1 || (( RESOURCE_LOCK_LOCK_RETRIES == RESOURCE_LOCK_LOCK_RETRIES_MAX )); do
		echo -n "."
		let "RESOURCE_LOCK_LOCK_RETRIES++"
		sleep 1
	done
	echo
	if [ ${RESOURCE_LOCK_LOCK_RETRIES} -eq ${RESOURCE_LOCK_LOCK_RETRIES_MAX} ]; then
		echo "WARNING: Cannot acquire lock after ${RESOURCE_LOCK_LOCK_RETRIES}s, ignoring lock on ${RESOURCE_LOCK_LOCK_DIR} by timeout"
	else
		echo "NOTICE: Successfully acquired lock on ${RESOURCE_LOCK_LOCK_DIR}"
	fi
}

function runner_resource_unlock () {
	local RESOURCE_NAME="$1"
	local RESOURCE_LOCK_DIR="${HOME}/.resource_lock"
	local RESOURCE_LOCK_LOCK_DIR="${RESOURCE_LOCK_DIR}/${RESOURCE_NAME}.lock"

	rm -rf "${RESOURCE_LOCK_LOCK_DIR}"
	echo "NOTICE: Successfully removed lock on ${RESOURCE_LOCK_LOCK_DIR}"
}
