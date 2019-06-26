#!/bin/bash

function gitlab_trigger_pipeline_and_wait_success () {
	# While CI_JOB_TOKEN or trigger token allow you to trigger pipeline, they do not allow to get status of the pipeline.
	# So you need to use private token with api instead - insecure but no other way yet:
	# https://gitlab.com/gitlab-org/gitlab-ce/issues/39640 .
	# It is better to add new user and use it's token, bot admin's. Add user to projects as Guest.
	# While private token or trigger token also can be used to trigger token, GitLab will not show Downstream if they are used. Only CI_JOB_TOKEN produces downstream graph.

	local GITLAB_URL="$1"
	local PROJECT_ID="$2"
	local REF="$3"
	local VARIABLES='$4'
	local PRIVATE_TOKEN="$5"
	
	# Echo curl command
	echo curl --request POST --form token=$CI_JOB_TOKEN --form ref=$REF $VARIABLES $GITLAB_URL/api/v4/projects/$PROJECT_ID/trigger/pipeline
	# Trigger pipeline and save output
	CURL_OUT=$(curl --request POST --form token=$CI_JOB_TOKEN --form ref=$REF $VARIABLES $GITLAB_URL/api/v4/projects/$PROJECT_ID/trigger/pipeline)
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
		# All other statuses or anything else - error
		echo "ERROR: status($PIPELINE_STATUS) is unknown to wait any longer"
		exit 1
	done
	echo "NOTICE: Successfully deployed"
}
