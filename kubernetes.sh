#!/bin/bash

function registry_login {
	docker login -u "$CI_REGISTRY_USER" -p $CI_JOB_TOKEN $CI_REGISTRY
}
