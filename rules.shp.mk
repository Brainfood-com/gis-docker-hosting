#!/usr/bin/make -f

# This ruleset takes 2 variables:
#
#  1: shp_srid -> The SRID to use
#  2: shp_table_name -> The name of the table that stores the converted data
#  3: shp_data_file -> The SHP file

override shp_rules_needed = 1
#ifeq ($(strip $(shp_srid)),)
#override shp_rules_needed :=
#endif
ifeq ($(strip $(shp_table_name)),)
override shp_rules_needed =
endif
ifeq ($(strip $(shp_data_file)),)
override shp_rules_needed =
endif

# Always define the rules
shp-clean:
shp-convert:
shp-import:
.PHONY: shp-clean
.PHONY: shp-convert
.PHONY: shp-import
OGR2OGR_shp = ./gis.sh ogr2ogr

ifeq ($(shp_rules_needed),1)

shp-import tableimport: table-$(shp_table_name)
index-$(shp_table_name):
table-$(shp_table_name): $(TOP_LEVEL)/build/stamps/table-$(shp_table_name)

tabledrop: tabledrop-$(shp_table_name)
tabledropdeps-$(shp_table_name)::
tabledrop-$(shp_table_name):: PSQL_db := $(PSQL_db)
tabledrop-$(shp_table_name):: shp_table_name := $(shp_table_name)
tabledrop-$(shp_table_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(shp_table_name)
	$(MAKE) -s tabledropdeps-$(shp_table_name)
	$(PSQL) -c "DROP TABLE IF EXISTS $(shp_table_name) CASCADE"

$(TOP_LEVEL)/build/stamps/table-$(shp_table_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(shp_table_name): shp_data_file := $(shp_data_file)
$(TOP_LEVEL)/build/stamps/table-$(shp_table_name): shp_base_name := $(basename $(notdir $(shp_data_file)))
$(TOP_LEVEL)/build/stamps/table-$(shp_table_name): shp_table_name := $(shp_table_name)
$(TOP_LEVEL)/build/stamps/table-$(shp_table_name):: $(shp_data_file)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(shp_table_name)
	time $(OGR2OGR_shp) -f PostgreSQL PG:"host=postgresql dbname=${POSTGRES_${PSQL_db}_NAME} user=${POSTGRES_${PSQL_db}_USER} password=${POSTGRES_${PSQL_db}_PASS}" -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI "/vsizip/$(shp_data_file)" -nln $(shp_table_name) -overwrite -progress
	$(MAKE) -s index-$(shp_table_name)
	@touch -r "$<" "$@"
endif

shp_table_name =
shp_data_file =
PSQL_db = GIS
