SHELL := /bin/bash
.ONESHELL:

PROJECT="poc_k8s_cluster"
REPO_NAME=$(shell basename `git rev-parse --show-toplevel`)

.PHONY: update new_pulumi_token codefresh_local_context codefresh_aws_account prog run
.PHONY: setup_local_deps update_dev codefresh_shared_secret



### Functions
define setup_local_deps
	LOCAL_DEPS=nodejs; \
	set -e; \
	unameOut=$(uname -s); \
	case ${unameOut} in \
		Linux*)     machine=linux;; \
		Darwin*)    machine=mac;; \
		*)          machine="UNKNOWN:${unameOut}";; \
	esac; \
	if [[ ${machine} == "mac" ]]; then \
		brew update && brew install -f ${LOCAL_DEPS}; \
	else \
		YUM_CMD=$(which yum); \
		APT_GET_CMD=$(which apt-get); \
		if [[ ! -z ${YUM_CMD} ]]; then \
			yum update -y && yum install -y ${LOCAL_DEPS}; \
		elif [[ ! -z ${APT_GET_CMD} ]]; then \
			apt-get update -y && apt-get install -y ${LOCAL_DEPS}; \
		else \
			echo "error can't install packages ${LOCAL_DEPS}"; \
			exit 1; \
		fi; \
	fi; \
	if [[ $(jq --version | sed "s/^.*jq-\([^;]*\).*/\1/") < 1.6 ]]; then \
		sudo wget --no-check-certificate https://raw.githubusercontent.com/stedolan/jq/master/sig/jq-release.key -O /tmp/jq-release.key && \
		sudo wget --no-check-certificate https://raw.githubusercontent.com/stedolan/jq/master/sig/v1.6/jq-linux64.asc -O /tmp/jq-linux64.asc && \
		sudo wget --no-check-certificate https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O /tmp/jq-linux64 && \
		sudo gpg --import /tmp/jq-release.key && \
		sudo gpg --verify /tmp/jq-linux64.asc /tmp/jq-linux64 && \
		sudo cp /tmp/jq-linux64 /usr/local/bin/jq && \
		sudo chmod +x /usr/local/bin/jq && \
		sudo rm -f /tmp/jq-release.key && \
		sudo rm -f /tmp/jq-linux64.asc && \
		sudo rm -f /tmp/jq-linux64; \
	fi;
endef



###
### Main targets
###
update: setup_local_deps
	$(MAKE) update_d ev

# Create and also updates a local context. Account/team specific
.SILENT:
codefresh_local_context: setup_local_deps
	$(eval CODEFRESH_API_AUTH_TOKEN := $(shell 1p get item \"Codefresh PE_API_Auth\" | jq -r '.details.password'))
	codefresh auth create-context platform-engineering --api-key ${CODEFRESH_API_AUTH_TOKEN}
	cat ~/.cfconfig



# Register an AWS account access key in Codefresh shared configuration secrets
# example: codefresh_aws_account_creds customer="payments" env="uat" aws_access_key_id="your access key" aws_secret_access_key="your secret key"
.SILENT:
codefresh_aws_account_creds: codefresh_local_context
	codefresh create context secret \"aws_${customer}_${env}\" -v AWS_ACCESS_KEY_ID=\"${aws_access_key_id}\" -v AWS_SECRET_ACCESS_KEY=\"${aws_secret_access_key}\"

# Create a Pulumi project deploying some templates locally. Keep in mind the '-y' attribute will destroy your stack resources after completion.
# example: pulumi_stack env="dev"
.SILENT:
pulumi_stack: new_pulumi_token
	pulumi new --name ${REPO_NAME} --stack ${env} --description "EKS cluster + namespace + Nginx" -y

# Create a Pulumi project. Keep in mind the '-y' attribute will destroy your stack resources after completion.
# example: force_pulumi_stack env="dev"
.SILENT:
force_pulumi_stack: new_pulumi_token
	mkdir -p quickstart
	pulumi new --name ${REPO_NAME} --stack ${env} --description "EKS cluster + namespace + Nginx" -y --dir ./quickstart
	rm -rf quickstart

# Generate each time a new token which will be set up on your pipeline as a environment variable.
# Make sure to cleanup via the Pulumi console before to run it again. 
.SILENT:
new_pulumi_token: codefresh_local_context
	REPO_NAME=$(basename `git rev-parse --show-toplevel`)
	$(eval PULUMI_API_AUTH_TOKEN := $(shell 1p get item \"Pulumi PE_API_Auth\" | jq -r '.details.password'))
	$(eval NEW_PULUMI_TOKEN := $(shell curl -s -X POST -H "Content-Type: application/json" -H "Authorization: token ${PULUMI_API_AUTH_TOKEN}" -d '{"description":'\"${REPO_NAME}\"'}' https://api.pulumi.com/api/user/tokens?reason=console | jq -r '.tokenValue'))
	echo -e '\n' && echo ${NEW_PULUMI_TOKEN} && echo -e '\n'
	export PULUMI_ACCESS_TOKEN=${NEW_PULUMI_TOKEN}
	codefresh create context secret "pulumi_token_${REPO_NAME}" -v PULUMI_ACCESS_TOKEN=${NEW_PULUMI_TOKEN}



###
### Sub-targets: for makefile internal calls only
###
# Invoke a defined function
setup_local_deps: ; @$(value setup_local_deps)

update_dev:
	npm install
