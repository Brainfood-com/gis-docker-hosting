#!/usr/bin/make -f

# This ruleset takes 1 variable:
#
#  1: shp_data_file -> The OSM compatible files

override osm_rules_needed := 1
ifeq ($(strip $(osm_data_files)),)
override osm_rules_needed :=
endif

# Always define the rules
osm-import:
.PHONY: osm-import

ifeq ($(osm_rules_needed),1)

build: osm-import
osm-import: $(TOP_LEVEL)/build/stamps/osm-import
$(TOP_LEVEL)/build/stamps/osm-import: $(osm_data_files)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$*
	PGPASS=${POSTGRES_DB_PASS} docker exec -e PGPASS -i gis_gdal_1 osm2pgsql -C 10000 -cH postgresql -d "${POSTGRES_DB_NAME}" -U "${POSTGRES_DB_USER}" $<
	@touch -r "$<" "$@"
endif

override osm_data_files :=
