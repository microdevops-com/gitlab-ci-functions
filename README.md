# About
Functions to create dynamic envs within Rancher project in a separate namespace (e.g. per $CI_COMMIT_REF_NAME).

# Usage
## Pipeline
Add the following to `.gitlab-ci.yml` depending on needs:
```

before_script:
  - KUBE_NAMESPACE=$(echo $RANCHER_PROJECT-$CI_COMMIT_REF_NAME | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")
  - RABBITMQ_VHOST=$(echo $RABBITMQ_VHOST_PREFIX-$CI_COMMIT_REF_NAME | tr "[:upper:]" "[:lower:]" | sed "s/[^a-zA-Z0-9-]/-/g")
  - rm -f kubernetes.sh && curl -L -s -o kubernetes.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/kubernetes.sh && . ./kubernetes.sh
  - rm -f docker.sh && curl -L -s -o docker.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/docker.sh && . ./docker.sh
  - rm -f rabbitmq.sh && curl -L -s -o rabbitmq.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/rabbitmq.sh && . ./rabbitmq.sh
  - registry_login
  - rancher_lock
  - rancher_login
  - helm_cluster_login

after_script:
  - . ./kubernetes.sh
  - rancher_logout
  - rancher_unlock
  - helm_cluster_logout

...

prepare_rabbitmq_vhost:
  stage: prerequisites
  script:
    - . ./rabbitmq.sh
    - rabbitmq_create_vhost $RABBITMQ_VHOST
    - rabbitmq_add_permission $RABBITMQ_VHOST $RABBITMQ_USER

prepare_rancher_namespace:
  stage: prerequisites
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
## Envs
Required envs for CI:
```
RANCHER_PROJECT=Project

RABBITMQ_HOST=rabbitmq.example.com
RABBITMQ_PORT=5672
RABBITMQ_MANAGEMENT_PORT=15672
RABBITMQ_USER=project-user
RABBITMQ_PASS=PASS1
RABBITMQ_MANAGEMENT_USER=project-admin
RABBITMQ_MANAGEMENT_PASS=PASS2
RABBITMQ_VHOST_PREFIX=project

KUBE_SERVER=https://rancher.example.com/k8s/clusters/local
KUBE_TOKEN=kubeconfig-u-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ADMIN_EMAIL=admin@example.com
```
