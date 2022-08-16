#!/bin/bash

source .env.test
if [ -f ".env.test.local" ]; then
    source .env.test.local
fi

set -exu

KUBE_MODE=kube-api
KUBE_NAMESPACE=fake
test_namespace_secret_acme_cert_with_acme_mode_docker_and_acme_account_cloudflare () {
  . ../kubernetes.sh

  local ACME_MODE=docker
  local ACME_ACCOUNT=cloudflare
  local ACME_DOCKER_CLI_ARGS="--debug"
 namespace_secret_acme_cert ingress-cert ${TEST_ACME_CLOUDFLARE_DOMAIN}

  local ACME_MODE=docker
  local ACME_ACCOUNT=clouddns
  local ACME_DOCKER_CLI_ARGS="--debug"
 namespace_secret_acme_cert ingress-cert ${TEST_ACME_CLOUDNS_DOMAIN}

}

test_namespace_secret_acme_cert_with_acme_mode_docker_and_acme_account_cloudflare
