SHELL := /bin/bash


CUSTOMER_LIST=all pe payments oreo
ENV_LIST=platformtesting dev testing uat sandbox production
WORKLOAD_TYPE_LIST=all ecs-payments ecs-core ecs-tools
RELEASE_ANSWER_LIST=y n


.PHONY: update force_update ami
.PHONY: update_pip force_update_pip setup_local_deps

# install/update dependencies
.SILENT:
update: setup_local_deps
	$(MAKE) update_pip

# forcing pip to install latest version of dependencies
.SILENT:
force_update: setup_local_deps
	$(MAKE) force_update_pip

# creating a Tag release which will trigger the pipeline to build your AMI
.SILENT:
ami:
	echo "Updating the repo..."; \
	git pull; echo -e "\r"; \
	echo "Repo Current Branches List:"; \
	echo "---------------------------"; \
	git branch -a; echo -e "\r"; \
	read -p 'Enter the branch you want to create a tag on: ' BRANCH; \
	git checkout $${BRANCH} && EXIT_CODE=$$?; \
	[[ ! $$EXIT_CODE ]] && exit 1; \
	echo -e "\r"; \
	read -p 'Is it a release? y or n: ' IS_RELEASE; \
	if [[ ! " ${RELEASE_ANSWER_LIST} " =~ " $${IS_RELEASE} " ]]; then \
		echo "Response invalid!"; \
		exit 1; \
	fi; \
	echo -e "\r"; \
	read -p 'Enter the customer you want to build the AMIs for [ ${CUSTOMER_LIST} ]: ' CUSTOMER; \
	if [[ ! " ${CUSTOMER_LIST} " =~ " $${CUSTOMER} " ]]; then \
		echo "This customer is not part of the authorized list!"; \
		exit 1; \
	fi; \
	echo -e "\r"; \
	read -p 'Enter the environment you want to build the AMIs for [ ${ENV_LIST} ]: ' ENV; \
	if [[ ! " ${ENV_LIST} " =~ " $${ENV} " ]]; then \
		echo "This environment is not part of the authorized list!"; \
		exit 1; \
	fi; \
	echo -e "\r"; \
	read -p 'Enter the workload type you want to build the AMIs for [ ${WORKLOAD_TYPE_LIST} ]: ' WORKLOAD_TYPE; \
	if [[ ! " ${WORKLOAD_TYPE_LIST} " =~ " $${WORKLOAD_TYPE} " ]]; then \
		echo "This workload is not part of the authorized list!"; \
		exit 1; \
	fi; \
	echo -e "\r"; \
	if [[ " $${IS_RELEASE} " = " y " ]]; then \
		git tag "release/$${CUSTOMER}/$${ENV}/$${WORKLOAD_TYPE}/$$(TZ=GMT date +%Y%m%dT%H%M%SZ)" -a; \
	else \
		git tag "test/$${CUSTOMER}/$${ENV}/$${WORKLOAD_TYPE}/$$(TZ=GMT date +%Y%m%dT%H%M%SZ)" -a; \
	fi; \
	git push origin --tags; \



# component methods

## common local setup
setup_local_deps:
	python -m venv .venv

## update pip from requirements and lock installed version
update_pip:
	( \
		. .venv/bin/activate; \
		pip install --no-cache-dir --upgrade -r requirements.txt; \
		pip freeze > requirements-locked.txt; \
    )

## update pip from requirements and lock installed version, forcing latest version of
## all dependencies, instead of min version that satisfies requirements
force_update_pip:
	( \
		. .venv/bin/activate; \
		pip install --no-cache-dir --upgrade --upgrade-strategy eager -r requirements.txt; \
		pip freeze > requirements-locked.txt; \
    )
