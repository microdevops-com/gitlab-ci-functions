#!/bin/bash

function ssh_salt_call_app_docker () {
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_APP="$3"

	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" -p "'${CI_JOB_TOKEN}'" "'${CI_REGISTRY}'"'
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''
	if [ -z "$4" ]; then
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker pillar='\''{"app": {"docker": {"deploy_only": ["'${DEPLOY_APP}'"], "apps": {"'${DEPLOY_APP}'": {"image": "'${DEPLOY_IMAGE}'"}}}}}'\'''
	else
		local DEPLOY_EXEC="$4"
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker pillar='\''{"app": {"docker": {"deploy_only": ["'${DEPLOY_APP}'"], "apps": {"'${DEPLOY_APP}'": {"image": "'${DEPLOY_IMAGE}'", "exec_after_deploy": "'${DEPLOY_EXEC}'"}}}}}'\'''
	fi
}

function ssh_copy_from_docker () {
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_SOURCE="$3"
	local DEPLOY_TARGET="$4"
	local DEPLOY_STRIP="$5"

	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" -p "'${CI_JOB_TOKEN}'" "'${CI_REGISTRY}'"'
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'DOCKER_TMP_DIR=$(mktemp -d -t docker.XXXXXXXXXX); DEPLOY_TMP_CONTAINER=$(docker create '${DEPLOY_IMAGE}'); docker export ${DEPLOY_TMP_CONTAINER} | tar -C ${DOCKER_TMP_DIR} --strip-components='${DEPLOY_STRIP}' -xf - '${DEPLOY_SOURCE}'; rsync -a --delete ${DOCKER_TMP_DIR}/ '${DEPLOY_TARGET}'/; docker rm ${DEPLOY_TMP_CONTAINER}; rm -rf ${DOCKER_TMP_DIR}'
}
