#!/bin/bash

function salt_call_deploy () {
	local DEPLOY_SERVER=$1
	local DEPLOY_IMAGE=$2
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" -p "'${CI_JOB_TOKEN}'" "'${CI_REGISTRY}'"'
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker pillar='\''{"app": {"docker": {"apps": {"proto": {"image": "'${DEPLOY_IMAGE}'"}}}}}'\'''
}
