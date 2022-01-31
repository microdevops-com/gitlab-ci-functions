#!/bin/bash

# rancher cli v.2.4.10+ that has --config for parallel jobs, previous could be used with HOME var substitution
RANCHER_CLI_CHECK_OUT=$(rancher --config 2>&1 || true)
if echo $RANCHER_CLI_CHECK_OUT | grep -q "flag needs an argument"; then
	RANCHER="rancher --config $PWD/.rancher"
else
	# eval is needed because running VAR=val cmd within pipelines tries to run VAR=val as separate command
	RANCHER="eval HOME=$PWD rancher"
fi
KUBECTL="$RANCHER kubectl"
# make cluster.yml parallel jobs safe
HELM="helm --kubeconfig $PWD/.helm/cluster.yml"


function rancher_login {
  if [ -z "$RANCHER_SERVER" ] && [ -z "$RANCHER_TOKEN" ] ; then
    $RANCHER login --token "$KUBE_TOKEN" "$KUBE_SERVER"
  else
    $RANCHER login --token "$RANCHER_TOKEN" "$RANCHER_SERVER"
  fi
}

function rancher_login_project {
  if [ -z "$RANCHER_SERVER" ] && [ -z "$RANCHER_TOKEN" ] ; then
    # Deprecated logic
    local RANCHER_PROJECT_NAME="$RANCHER_PROJECT"
    local RANCHER_PROJECT_ID=$(echo "" | $RANCHER login --token "$KUBE_TOKEN" "$KUBE_SERVER" 2>/dev/null | grep -E "local\:p-[[:alnum:]]+[[:space:]]+${RANCHER_PROJECT_NAME}" | awk '{print $3}')
    $RANCHER login --token "$KUBE_TOKEN" --context "$RANCHER_PROJECT_ID" "$KUBE_SERVER"
  else
    $RANCHER login "$RANCHER_SERVER" --token "$RANCHER_TOKEN" --context "$RANCHER_CLUSTER_ID:$RANCHER_PROJECT_ID"
  fi
}

function rancher_logout {
	rm -f $PWD/.rancher/cli2.json
}

function rancher_namespace {
	echo "KUBE_NAMESPACE: $KUBE_NAMESPACE"
	# do not prefix OUT vars with local or exit code will be wrong
	$RANCHER namespace | grep -q "$KUBE_NAMESPACE\s*$KUBE_NAMESPACE" || {
		RANCHER_OUT=$($RANCHER namespace create "$KUBE_NAMESPACE" 2>&1) && RANCHER_EXIT_CODE=0 || RANCHER_EXIT_CODE=1
		echo Rancher exit code: $RANCHER_EXIT_CODE
		echo $RANCHER_OUT
		if [[ $RANCHER_EXIT_CODE != 0 ]]; then
			if echo $RANCHER_OUT | grep -q "code=AlreadyExists"; then
				echo Error code=AlreadyExists arised, probably it was created by parallel job, and it is ok, ignoring
				true
			else
				false
			fi
		fi
	}
}

function helm_cluster_login {
  mkdir -p $PWD/.helm
  if [ -z "$RANCHER_SERVER" ] && [ -z "$RANCHER_TOKEN" ] ; then
    KUBECONFIG=$PWD/.helm/cluster.yml kubectl config set-cluster remote-cluster --server=$KUBE_SERVER
    KUBECONFIG=$PWD/.helm/cluster.yml kubectl config set-credentials user-gvnrn --token=$KUBE_TOKEN
    KUBECONFIG=$PWD/.helm/cluster.yml kubectl config set-context remote-cluster --user=user-gvnrn --cluster=remote-cluster
    KUBECONFIG=$PWD/.helm/cluster.yml kubectl config use-context remote-cluster
  else
    $RANCHER cluster kubeconfig ${RANCHER_CLUSTER_ID}> $PWD/.helm/cluster.yml
  fi
  chmod 600 $PWD/.helm/cluster.yml
}

# We shouldn't leave credentials in the workspace as they may change
function helm_cluster_logout {
	rm -f $PWD/.helm/cluster.yml
}

# Deprecated
function rancher_lock {
	echo "NOTICE: rancher cli is parallel jobs safe now, you can safely remove rancher_lock/rancher_unlock calls"
}

function rancher_unlock {
	echo "NOTICE: rancher cli is parallel jobs safe now, you can safely remove rancher_lock/rancher_unlock calls"
}
