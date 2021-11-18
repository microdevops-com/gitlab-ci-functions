#!/bin/bash

function check_var () {
	if [ -z "${!1}" ]; then
		echo "ERROR: var $1 is empty"
		exit 1
	fi
}

# Salt 3001.1 minion on focal has bug in salt-call, should be fixed in magnesium
# https://github.com/saltstack/salt/pull/58364
# https://github.com/saltstack/salt/issues/57456
# https://github.com/saltstack/salt/issues/57856
# Workaround:
# pip3 install --no-binary=:all: pyzmq==18.0.1

function ssh_salt_call_app_docker () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_APP="$3"

	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" -p "'${CI_JOB_TOKEN}'" "'${CI_REGISTRY}'"'
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''
	if [ -z "$4" ]; then
		ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker queue=True pillar='\''{"app": {"docker": {"deploy_only": ["'${DEPLOY_APP}'"], "apps": {"'${DEPLOY_APP}'": {"image": "'${DEPLOY_IMAGE}'"}}}}}'\'''
	else
		local DEPLOY_EXEC="$4"
		ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker queue=True pillar='\''{"app": {"docker": {"deploy_only": ["'${DEPLOY_APP}'"], "apps": {"'${DEPLOY_APP}'": {"image": "'${DEPLOY_IMAGE}'", "exec_after_deploy": "'${DEPLOY_EXEC}'"}}}}}'\'''
	fi
}

function ssh_copy_from_docker () {
	local SSH_PORT=${NGINX_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_SOURCE="$3"
	local DEPLOY_TARGET="$4"
	local DEPLOY_STRIP="$5"
	local DEPLOY_EXCLUDE="$6"

	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" -p "'${CI_JOB_TOKEN}'" "'${CI_REGISTRY}'"'
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''

	if [ -z "$DEPLOY_EXCLUDE" ]; then
		ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'DOCKER_TMP_DIR=$(mktemp -d -t docker.XXXXXXXXXX); DEPLOY_TMP_CONTAINER=$(docker create '${DEPLOY_IMAGE}'); docker export ${DEPLOY_TMP_CONTAINER} | tar -C ${DOCKER_TMP_DIR} --strip-components='${DEPLOY_STRIP}' -xf - '${DEPLOY_SOURCE}'; rsync -a --delete ${DOCKER_TMP_DIR}/ '${DEPLOY_TARGET}'/; chmod 755 '${DEPLOY_TARGET}'; docker rm ${DEPLOY_TMP_CONTAINER}; rm -rf ${DOCKER_TMP_DIR}'
	else
		ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'DOCKER_TMP_DIR=$(mktemp -d -t docker.XXXXXXXXXX); DEPLOY_TMP_CONTAINER=$(docker create '${DEPLOY_IMAGE}'); docker export ${DEPLOY_TMP_CONTAINER} | tar -C ${DOCKER_TMP_DIR} --strip-components='${DEPLOY_STRIP}' -xf - '${DEPLOY_SOURCE}'; rsync -a --delete --exclude '${DEPLOY_EXCLUDE}' ${DOCKER_TMP_DIR}/ '${DEPLOY_TARGET}'/; chmod 755 '${DEPLOY_TARGET}'; docker rm ${DEPLOY_TMP_CONTAINER}; rm -rf ${DOCKER_TMP_DIR}'
	fi
}
