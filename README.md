# About
Functions to create dynamic envs within Rancher project in a separate namespace (e.g. per $CI_COMMIT_REF_NAME).

# Usage
Add the following to `.gitlab-ci.yml` depending on needs:
```
before_script:
  # Sanitize namespaces constructed from $CI_COMMIT_REF_NAME
  - KUBE_NAMESPACE=$(echo $RANCHER_PROJECT-$CI_COMMIT_REF_NAME | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")
  - RABBITMQ_VHOST=$(echo $RABBITMQ_VHOST_PREFIX-$CI_COMMIT_REF_NAME | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")
  # Download shared functions
  - rm -f kubernetes.sh && curl -L -s -o kubernetes.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/kubernetes.sh && . ./kubernetes.sh
  - rm -f docker.sh && curl -L -s -o docker.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/docker.sh && . ./docker.sh
  - registry_login
  - rancher_lock
  - rancher_login
  - helm_cluster_login

after_script:
  - . ./kubernetes.sh
  - rancher_unlock
  - rancher_logout
  - helm_cluster_logout

...

prepare_rancher_namespace:
  stage: prepare_rancher_namespace
  script:
    - . ./kubernetes.sh
    - rancher_namespace
    - namespace_secret_project_registry
    - namespace_secret_rabbitmq rabbitmq
    - helm_init_namespace

my-app:
  stage: app_deploy
  script:
    - . ./kubernetes.sh
    - helm_deploy my-app $CI_COMMIT_REF_NAME
```
