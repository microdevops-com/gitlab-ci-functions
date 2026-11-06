#!/bin/bash

function check_var () {
	(
		set +u
		if [ -z "${!1}" ]; then
			echo "ERROR: var $1 is empty"
			exit 1
		fi
	)
}

# Salt 3001.1 minion on focal has bug in salt-call, should be fixed in magnesium
# https://github.com/saltstack/salt/pull/58364
# https://github.com/saltstack/salt/issues/57456
# https://github.com/saltstack/salt/issues/57856
# Workaround:
# pip3 install --no-binary=:all: pyzmq==18.0.1

# Deploy one app of the Salt app.docker formula with a new image.
# Usage: ssh_salt_call_app_docker SERVER IMAGE APP [EXEC_AFTER_DEPLOY]
# Optional env:
#   DOCKER_SERVER_SSH_PORT  ssh port (default 22)
#   DEPLOY_PRE_START=true   also run the app's pre_start (e.g. migrations) with the same IMAGE;
#                           pillar must define pre_start.command for the app
#   SALT_CALL_EXTRA_ARGS    extra salt-call args, e.g. "--retcode-passthrough --state-output=mixed"
#                           (without --retcode-passthrough failed states do not fail the job)
function ssh_salt_call_app_docker () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_APP="$3"
	local DEPLOY_EXEC="${4:-}"
	local APP_PILLAR="\"image\": \"${DEPLOY_IMAGE}\""

	if [ -n "${DEPLOY_EXEC}" ]; then
		APP_PILLAR="${APP_PILLAR}, \"exec_after_deploy\": \"${DEPLOY_EXEC}\""
	fi
	if [ "${DEPLOY_PRE_START:-false}" = "true" ]; then
		APP_PILLAR="${APP_PILLAR}, \"pre_start\": {\"image\": \"${DEPLOY_IMAGE}\"}"
	fi

	printf '%s' "${CI_JOB_TOKEN}" | ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" --password-stdin "'${CI_REGISTRY}'"'
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'salt-call state.apply app.docker queue=True '"${SALT_CALL_EXTRA_ARGS:-}"' pillar='\''{"app": {"docker": {"deploy_only": "'${DEPLOY_APP}'", "apps": {"'${DEPLOY_APP}'": {'"${APP_PILLAR}"'}}}}}'\'''
}

function ssh_copy_from_docker () {
	local SSH_PORT=${NGINX_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local DEPLOY_IMAGE="$2"
	local DEPLOY_SOURCE="$3"
	local DEPLOY_TARGET="$4"
	local DEPLOY_STRIP="$5"
	local DEPLOY_EXCLUDE="${6:-}"

	printf '%s' "${CI_JOB_TOKEN}" | ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker login -u "'${CI_REGISTRY_USER}'" --password-stdin "'${CI_REGISTRY}'"'
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker pull '${DEPLOY_IMAGE}''

	local RSYNC_EXCLUDE=""
	if [ -n "$DEPLOY_EXCLUDE" ]; then
		printf -v RSYNC_EXCLUDE '\x2D\x2Dexclude %s ' ${DEPLOY_EXCLUDE[@]}
	fi

	# set -e: a failed create/extract/rsync fails the job; the EXIT trap always removes temp container and dir.
	# TARGET is created if missing.
	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'set -e; DEPLOY_TMP_CONTAINER=; DOCKER_TMP_DIR=$(mktemp -d -t docker.XXXXXXXXXX); trap "rm -rf \"\$DOCKER_TMP_DIR\"; [ -z \"\$DEPLOY_TMP_CONTAINER\" ] || docker rm \"\$DEPLOY_TMP_CONTAINER\" > /dev/null" EXIT; DEPLOY_TMP_CONTAINER=$(docker create '${DEPLOY_IMAGE}'); docker export ${DEPLOY_TMP_CONTAINER} | tar -C ${DOCKER_TMP_DIR} --strip-components='${DEPLOY_STRIP}' -xf - '${DEPLOY_SOURCE}'; mkdir -p '${DEPLOY_TARGET}'; rsync -a --delete '${RSYNC_EXCLUDE}' ${DOCKER_TMP_DIR}/ '${DEPLOY_TARGET}'/; chmod 755 '${DEPLOY_TARGET}''
}

# Upload a local file to SERVER only if its content differs (e.g. app env file from a GitLab File variable).
# Prints "changed" or "unchanged" to stdout; OWNER and MODE are applied in both cases.
# Usage: ssh_install_file SERVER SOURCE TARGET [OWNER] [MODE]
# Optional env: DOCKER_SERVER_SSH_PORT
function ssh_install_file () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local SOURCE="$2"
	local TARGET="$3"
	local OWNER="${4:-root:root}"
	local MODE="${5:-0600}"

	ssh -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'set -e
		f="'${TARGET}'"
		mkdir -p "$(dirname "$f")"
		umask 077
		cat > "$f.tmp"
		if [ -f "$f" ] && cmp -s "$f.tmp" "$f"; then rm -f "$f.tmp"; state=unchanged; else mv "$f.tmp" "$f"; state=changed; fi
		chown "'${OWNER}'" "$f"
		chmod "'${MODE}'" "$f"
		echo "$state"' < "${SOURCE}"
}

# Print container ID on SERVER, empty if the container does not exist.
# Usage: ssh_docker_container_id SERVER CONTAINER
# Optional env: DOCKER_SERVER_SSH_PORT
function ssh_docker_container_id () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local CONTAINER="$2"

	ssh -n -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker inspect -f "{{.Id}}" "'${CONTAINER}'" 2>/dev/null || true'
}

# Restart container on SERVER, waiting up to STOP_TIMEOUT seconds for a graceful stop.
# Usage: ssh_docker_restart SERVER CONTAINER [STOP_TIMEOUT]
# Optional env: DOCKER_SERVER_SSH_PORT
function ssh_docker_restart () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local CONTAINER="$2"
	local STOP_TIMEOUT="${3:-10}"

	echo DOCKER: restart ${CONTAINER} on ${DEPLOY_SERVER}
	ssh -n -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'docker restart --time '${STOP_TIMEOUT}' "'${CONTAINER}'" > /dev/null'
}

# Wait until container on SERVER reports healthy; images without HEALTHCHECK pass immediately.
# On timeout prints the container log tail and fails.
# Usage: ssh_docker_wait_healthy SERVER CONTAINER [TIMEOUT_SECONDS]
# Optional env: DOCKER_SERVER_SSH_PORT
function ssh_docker_wait_healthy () {
	local SSH_PORT=${DOCKER_SERVER_SSH_PORT:=22}
	local DEPLOY_SERVER="$1"
	local CONTAINER="$2"
	local TIMEOUT="${3:-120}"

	ssh -n -o Port=${SSH_PORT} -o BatchMode=yes -o StrictHostKeyChecking=no root@${DEPLOY_SERVER} 'c="'${CONTAINER}'"
		deadline=$(( $(date +%s) + '${TIMEOUT}' ))
		while :; do
			status=$(docker inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" "$c") || exit 1
			case "$status" in healthy|none) echo "DOCKER: $c is $status"; exit 0 ;; esac
			if [ "$(date +%s)" -ge "$deadline" ]; then
				echo "ERROR: $c is not healthy after '${TIMEOUT}'s (status: $status)" >&2
				docker logs --tail 100 "$c" >&2
				exit 1
			fi
			sleep 2
		done'
}
