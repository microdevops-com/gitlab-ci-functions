#!/bin/bash

function gitlab_trigger_pipeline_and_wait_success() {
    # While CI_JOB_TOKEN or trigger token allow you to trigger pipeline, they do not allow to get status of the pipeline.
    # So you need to use private token with api instead - insecure but no other way yet:
    # https://gitlab.com/gitlab-org/gitlab-ce/issues/39640 .
    # It is better to add new user and use it's token, bot admin's. Add user to projects as Guest.
    # While private token or trigger token also can be used to trigger token, GitLab will not show Downstream if they are used. Only CI_JOB_TOKEN produces downstream graph.

    #GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL = 1 display run pipeline command with args
    #GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL = 2 -> 1 + display check status command
    #GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL = 3 -> 2 + display curl output
    #GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL = 4 -> 3 + curl verbose
    local GITLAB_URL="$1"
    # Substitute / in project id if namespace used with url safe symbols
    local PROJECT_ID="$(echo $2 | sed -e 's#/#%2F#g')"
    local REF="$3"
    local VARIABLES="$4"
    local PRIVATE_TOKEN="$5"

    local CURL_ARGS=''
    if [[ ${GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL:-'0'} -ge 4 ]]; then
        # Echo curl command
        CURL_ARGS="--verbose"
    else
        CURL_ARGS="--silent"
    fi

    local CURL_CMD="curl ${CURL_ARGS} --request POST --form token=${CI_JOB_TOKEN} --form ref=$REF ${VARIABLES} ${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/trigger/pipeline"

    echo "[gitlab-trigger-pipeline][$(date)] Trigger new downstream pipeline on repo: $2"
    if [[ ${GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL:-'0'} -ge 1 ]]; then
        # Echo curl command
        echo "[gitlab-trigger-pipeline][$(date)][DEBUG] ${CURL_CMD}"
    fi

    # Trigger pipeline and save output
    local CURL_OUT=$($CURL_CMD)
    if [[ ${GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL:-'0'} -ge 2 ]]; then
        # Echo curl command
        echo "[gitlab-trigger-pipeline][$(date)][DEBUG] ${CURL_OUT}"
    fi
    # Check typical errors in output and fail job if any
    #(echo ${CURL_OUT} | grep -q "Insufficient permissions") && exit 1 || true

    local RUN_PIPELINE_MESSAGE=$(echo ${CURL_OUT} | jq -r .message)
    if [[ "$RUN_PIPELINE_MESSAGE" != "null" ]]; then
        echo "[gitlab-trigger-pipeline][$(date)][ERROR] Unsuccessful response: ${RUN_PIPELINE_MESSAGE}"
        exit 1
    fi


    # Get pipeline id
    local PIPELINE_ID=$(echo ${CURL_OUT} | jq -r .id)
    local PIPELINE_URL=$(echo ${CURL_OUT} | jq -r .web_url)
    # Check if pipeline id is int
    if [[ ! $PIPELINE_ID =~ ^-?[0-9]+$ ]]; then
        echo "[gitlab-trigger-pipeline][$(date)][ERROR] id(${PIPELINE_ID}) is not int"
        exit 1
    fi
    echo "[gitlab-trigger-pipeline][$(date)][NOTICE] Started pipeline with url: ${PIPELINE_URL}"
    echo "[gitlab-trigger-pipeline][$(date)][NOTICE] Waiting finish pipeline"
    # Get pipeline status

    local PIPELINE_STATUS="created"
    while true; do
        echo -n "."
        sleep 2
        CURL_OUT=$(curl ${CURL_ARGS} --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" ${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID})
        if [[ ${GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL:-'0'} -ge 3 ]]; then
            # Echo curl command
            echo "[gitlab-trigger-pipeline][$(date)][DEBUG] ${CURL_OUT}"
        fi

         # Check error in response
        local ERROR_MSG=$(echo ${CURL_OUT} | jq -r .message)        
        if [[ "$ERROR_MSG" != "null" ]]; then
          echo "[gitlab-trigger-pipeline][$(date)][ERROR] Can not get status of downstream pipeline: ${ERROR_MSG}"
          return 1
        fi

        # Get the status of the pipeline
        local PIPELINE_STATUS_CURRENT=$(echo ${CURL_OUT} | jq -r .status)
        if [[ "$PIPELINE_STATUS" != "$PIPELINE_STATUS_CURRENT" ]]; then
            echo ""
            echo "[gitlab-trigger-pipeline][$(date)][NOTICE] Pipeline change status from \"${PIPELINE_STATUS}\" to \"${PIPELINE_STATUS_CURRENT}\""
            PIPELINE_STATUS=${PIPELINE_STATUS_CURRENT}
        fi

        if [[ ${GITLAB_TRIGGER_PIPELINE_VERBOSITY_LEVEL:-'0'} -ge 3 ]]; then
            # Echo curl command
            echo ""
            echo "[gitlab-trigger-pipeline][$(date)][DEBUG] Current Status: ${PIPELINE_STATUS_CURRENT}"
        fi

        # Exit with OK on success
        if [[ "_${PIPELINE_STATUS_CURRENT}" = "_success" ]]; then
            break
        fi
        # Wait on pending or running
        if [[ "_${PIPELINE_STATUS_CURRENT}" = "_pending" ]]; then
            continue
        fi
        if [[ "_${PIPELINE_STATUS_CURRENT}" = "_running" ]]; then
            continue
        fi
        if [[ "_${PIPELINE_STATUS_CURRENT}" = "_created" ]]; then
            continue
        fi

        # All other statuses or anything else - error
        echo ""
        echo "[gitlab-trigger-pipeline][$(date)][ERROR]: status($PIPELINE_STATUS) is unknown to wait any longer"
        return 1
    done
    echo ""
    echo "[gitlab-trigger-pipeline][$(date)][NOTICE] Successfully finished pipeline"
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
