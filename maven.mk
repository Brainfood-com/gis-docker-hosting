#!/usr/bin/make -f

pull: maven-pull
maven-pull: $(TOP_LEVEL)/build/docker/maven-tag
$(TOP_LEVEL)/var/cache/maven-repository:
	@mkdir -p $(TOP_LEVEL)/var/cache/maven-repository
	
$(TOP_LEVEL)/build/docker/maven-tag: $(TOP_LEVEL)/var/cache/maven-repository
	@mkdir -p $(@D)
	docker pull maven
	docker inspect maven > $@.tmp
	mv $@.tmp $@

prune: maven-prune
maven-prune:
	rm -rf $(TOP_LEVEL)/var/cache/maven-repository

.PHONY: maven-pull maven-prune
ifneq ($(strip $(DOCKER_REPULL)),)
.PHONY: $(TOP_LEVEL)/build/docker/maven-tag
endif

docker_run += -v $(TOP_LEVEL)/var/cache/maven-repository:/srv/maven-repository:rw
