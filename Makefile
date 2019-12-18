SHELL := /bin/bash
.ONESHELL:

PROJECT="poc_k8s_cluster"
REPO_NAME=$(shell basename `git rev-parse --show-toplevel`)

.PHONY: update codefresh_local_context codefresh_aws_account_creds pulumi_stack force_pulumi_stack new_pulumi_token
.PHONY: setup_local_deps update_dev cleanup



### Functions
define setup_local_deps
	PACKAGED_LOCAL_DEPS="nodejs kubectl"; \
	set -e; \
	unameOut=$(uname -s); \
	case ${unameOut} in \
		Linux*)     machine=linux;; \
		Darwin*)    machine=darwin;; \
		*)          machine="UNKNOWN:${unameOut}";; \
	esac; \
	if [[ ${machine} == "darwin" ]]; then \
		brew update && brew install -f ${PACKAGED_LOCAL_DEPS}; \
	else \
		YUM_CMD=$(which yum); \
		APT_GET_CMD=$(which apt-get); \
		if [[ ! -z ${YUM_CMD} ]]; then \
			cat <<EOF > /etc/yum.repos.d/kubernetes.repo \
			[kubernetes] \
			name=Kubernetes \
			baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64 \
			enabled=1 \
			gpgcheck=1 \
			repo_gpgcheck=1 \
			gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg \
			EOF; \
			yum update -y && yum install -y ${PACKAGED_LOCAL_DEPS}; \
		elif [[ ! -z ${APT_GET_CMD} ]]; then \
			curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -; \
			echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list; \
			apt-get update -y && apt-get install -y ${PACKAGED_LOCAL_DEPS}; \
		else \
			echo "ERROR - can't install packages ${PACKAGED_LOCAL_DEPS}"; \
			exit 1; \
		fi; \
	fi; \
	curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/${machine}/amd64/aws-iam-authenticator; \
	chmod +x ./aws-iam-authenticator; \
	mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH="$HOME/bin${PATH:+:${PATH}}" && rm -rf ./aws-iam-authenticator; \
	echo 'PATH="$HOME/bin${PATH:+:${PATH}}"' >> ~/.bash_profile; \
	echo "aws-iam-authenticator: $(aws-iam-authenticator version)"; \
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

define cleanup_local
	set -e; \
	unameOut=$(uname -s); \
	case ${unameOut} in \
		Linux*)     machine=linux;; \
		Darwin*)    machine=darwin;; \
		*)          machine="UNKNOWN:${unameOut}";; \
	esac; \
	if [[ ${machine} == "darwin" ]]; then \
		brew cleanup; \
	else \
		YUM_CMD=$(which yum); \
		APT_GET_CMD=$(which apt-get); \
		if [[ ! -z ${YUM_CMD} ]]; then \
			yum clean all; \
		elif [[ ! -z ${APT_GET_CMD} ]]; then \
			apt-get clean; \
		else \
			echo "ERROR - can't cleanup"; \
			exit 1; \
		fi; \
	fi; \
	rm -rf node_modules;
endef



###
### Main targets
###
.SILENT:
update: cleanup setup_local_deps
	$(MAKE) update_dev

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
# Invoke the related defined function; function being used here for easier bash scripting
setup_local_deps: ; @$(value setup_local_deps)

update_dev:
	npm install

# Invoke the related defined function; function being used here for easier bash scripting
cleanup: ; @$(value cleanup_local)
