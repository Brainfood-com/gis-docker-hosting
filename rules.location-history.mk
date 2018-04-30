#!/usr/bin/make -f

# This ruleset takes 2 variables:
#
#  1: location_history_table_name -> The name of the table that stores the converted data
#  2: location_history_data_file -> The file from Google Takeout that contains location data

override location_history_rules_needed := 1
ifeq ($(strip $(location_history_table_name)),)
override location_history_rules_needed :=
endif
ifeq ($(strip $(location_history_zip_file)),)
override location_history_rules_needed :=
endif

# Always define the rules
location-history-prune:
location-history-convert:
location-history-import:
.PHONY: location-history-prune
.PHONY: location-history-convert
.PHONY: location-history-import

ifeq ($(location_history_rules_needed),1)
prune location-history-prune: location-history-prune-$(location_history_table_name)
location-history-prune-$(location_history_table_name):
	rm -f $(TOP_LEVEL)/build/location-history-$(location_history_table_name).kml

location-history-convert: location-history-convert-$(location_history_table_name)
location-history-convert: location-history-convert-$(location_history_table_name)
location-history-convert-$(location_history_table_name): $(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson

$(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson: location_history_table_name := $(location_history_table_name)
$(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson: location_history_zip_file := $(location_history_zip_file)
$(TOP_LEVEL)/build/location-history-$(location_history_table_name).json: $(location_history_zip_file)
	@mkdir -p "$(@D)"
	unzip -p "$(location_history_zip_file)" "Takeout/Location History/Location History.json" > "$@.tmp"
	mv "$@.tmp" "$@"

$(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson: location_history_table_name := $(location_history_table_name)
$(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson: location_history_zip_file := $(location_history_zip_file)
$(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson: $(TOP_LEVEL)/build/location-history-$(location_history_table_name).json
	./gis.sh python android_location_converter/read_location_data.py "$(<:$(TOP_LEVEL)/%=%)" "$(@D:$(TOP_LEVEL)/%=%)" "$(@F:%.geojson=%-tmp)" GeoJSON
	touch -r "$<" "$(@D)/$(@F:%.geojson=%-tmp).geojson"
	mv "$(@D)/$(@F:%.geojson=%-tmp).geojson" "$@"

import location-history-import tableimport: table-$(location_history_table_name)
table-$(location_history_table_name): $(TOP_LEVEL)/build/stamps/table-$(location_history_table_name)
$(TOP_LEVEL)/build/stamps/table-$(location_history_table_name): location_history_table_name := $(location_history_table_name)
$(TOP_LEVEL)/build/stamps/table-$(location_history_table_name):: $(TOP_LEVEL)/build/location-history-$(location_history_table_name).geojson
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(location_history_table_name)
	./gis.sh ogr2ogr -f PostgreSQL PG:"host=postgresql dbname=${POSTGRES_DB_NAME} user=${POSTGRES_DB_USER} password=${POSTGRES_DB_PASS}" "$(<:$(TOP_LEVEL)/%=%)" -nln $(location_history_table_name) -overwrite -progress
	touch -r "$<" "$@"
endif

override location_history_table_name :=
override location_history_data_file :=
