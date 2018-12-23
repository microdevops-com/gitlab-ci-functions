# Usage
Add the following to `.gitlab-ci.yml` depending on needs:
```
before_script:
  - rm -f kubernetes.sh && curl -L -s -o kubernetes.sh https://raw.githubusercontent.com/sysadmws/gitlab-ci-functions/master/kubernetes.sh && . ./kubernetes.sh
  - registry_login
  - rancher_lock

after_script:
  - . ./kubernetes.sh
  - rancher_unlock
```
