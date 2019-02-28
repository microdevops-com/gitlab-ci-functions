# About
Functions to create dynamic envs per $CI_COMMIT_REF_SLUG.
- Rancher project namespaces
- RabbitMQ virtual hosts
- Docker Registry parallel logins
- PostgreSQL databases

# Usage
## Add this repo as Git Submodule to a project

```
git submodule add --name .gitlab-ci-functions -b master -- https://github.com/sysadmws/gitlab-ci-functions .gitlab-ci-functions
```

P.S. You can directly fetch code from https://raw.githubusercontent.com each time pipeline runs, it is a quick way to start, but not a smart way to use permanently.
```
before_script:
  - rm -f kubernetes.sh && curl -L -s -o kubernetes.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/kubernetes.sh && . ./kubernetes.sh
  - ...

...

after_script:
  - . ./kubernetes.sh
  - rancher_logout
  - ...
```
## Pipeline
Add the following to `.gitlab-ci.yml` depending on needs:
```
variables:
  GIT_SUBMODULE_STRATEGY: normal

before_script:
  - . .gitlab-ci-functions/kubernetes.sh
  - . .gitlab-ci-functions/docker.sh
  - . .gitlab-ci-functions/rabbitmq.sh
  # this vars are available to script but not available to yml
  - KUBE_NAMESPACE=$(kubernetes_namespace_sanitize $RANCHER_PROJECT-$CI_COMMIT_REF_SLUG)
  - RABBITMQ_VHOST=$(rabbitmq_vhost_sanitize $RABBITMQ_VHOST_PREFIX-$CI_COMMIT_REF_SLUG)
  - registry_login
  - rancher_lock
  - rancher_login
  - helm_cluster_login

after_script:
  - . .gitlab-ci-functions/kubernetes.sh
  - rancher_logout
  - rancher_unlock
  - helm_cluster_logout

...

prepare_rabbitmq_vhost:
  stage: prerequisites
  script:
    - . .gitlab-ci-functions/rabbitmq.sh
    - rabbitmq_create_vhost $RABBITMQ_VHOST
    - rabbitmq_add_permission $RABBITMQ_VHOST $RABBITMQ_USER

prepare_postgresql_db:
  stage: prerequisites
  script:
    - . .gitlab-ci-functions/postgresql.sh
    - postgresql_create_db $PGHOST $PGPORT $PGUSER $PGPASSWORD $POSTGRESQL_DB_PREFIX-$CI_COMMIT_REF_SLUG
  

prepare_rancher_namespace:
  stage: prerequisites
  script:
    - . .gitlab-ci-functions/kubernetes.sh
    - rancher_namespace
    - namespace_secret_project_registry
    - namespace_secret_rabbitmq rabbitmq
    - helm_init_namespace

my-app:
  stage: app_deploy
  script:
    - . .gitlab-ci-functions/kubernetes.sh
    - helm_deploy my-app $CI_COMMIT_REF_SLUG
    #- helm_deploy my-app $CI_COMMIT_REF_SLUG "--set env=dev"
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
POSTGRESQL_DB_PREFIX=project

KUBE_SERVER=https://rancher.example.com/k8s/clusters/local
KUBE_TOKEN=kubeconfig-u-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ADMIN_EMAIL=admin@example.com
```
