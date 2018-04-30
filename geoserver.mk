#!/usr/bin/make -f

geoserver-shell-clean-tmp:
	rm -f $(TOP_LEVEL)/build/gs-shell.jar.tmp
geoserver-shell-clean-build:
	rm -f $(TOP_LEVEL)/build/gs-shell.jar
build: geoserver-shell-build
geoserver-shell-build: $(TOP_LEVEL)/build/gs-shell.jar
$(TOP_LEVEL)/build/gs-shell.jar: $(TOP_LEVEL)/build/docker/maven-tag
	@rm -rf $@.tmp
	@mkdir -p $@.tmp
	@mkdir -p $(TOP_LEVEL)/geoserver-shell/target
	@mkdir -p $(TOP_LEVEL)/var/cache/maven-repository
	$(docker_run) \
		-v $(TOP_LEVEL)/geoserver-shell:/srv/app/geoserver-shell:rw \
		-v $@.tmp:/srv/app/geoserver-shell/target:rw \
		--workdir /srv/app/geoserver-shell \
		maven mvn -Djava.io.tmpdir=/tmp package
	cp -a $@.tmp/gs-shell-*.jar $@
	rm -rf $@.tmp

.PHONY: geoserver-shell-clean-tmp
.PHONY: geoserver-shell-clean-build
.PHONY: geoserver-shell-build

