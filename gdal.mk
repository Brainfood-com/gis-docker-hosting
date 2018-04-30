#!/usr/bin/make -f

pull: gdal-pull
gdal-pull: $(TOP_LEVEL)/build/docker/gdal-tag
	
$(TOP_LEVEL)/build/docker/gdal-tag:
	@mkdir -p $(@D)
	docker pull geodata/gdal
	docker inspect geodata/gdal > $@.tmp
	mv $@.tmp $@

.PHONY: gdal-pull
ifneq ($(strip $(DOCKER_REPULL)),)
.PHONY: $(TOP_LEVEL)/build/docker/gdal-tag
endif
