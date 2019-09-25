#!/bin/bash

function salt_call_app_docker () {
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
