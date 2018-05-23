#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: view_table_name -> The name of the table that stores the converted data
#  2: view_sql -> The SQL that defines the view
#  3: view_dep_tables -> The tables the view depends on

override csv_rules_needed = 1
ifeq ($(strip $(csv_table_name)),)
override csv_rules_needed =
endif
ifeq ($(strip $(csv_schema)),)
override csv_rules_needed =
endif
ifeq ($(strip $(csv_file)),)
override csv_rules_needed =
endif

# Always define the rules
csv-import:

ifeq ($(csv_rules_needed),1)

csvimport tableimport: table-$(csv_table_name)
index-$(csv_table_name):
table-$(csv_table_name): $(TOP_LEVEL)/build/stamps/table-$(csv_table_name)
tabledrop: tabledrop-$(csv_table_name)
tabledrop-$(csv_table_name):: PSQL_db := $(PSQL_db)
tabledrop-$(csv_table_name):: csv_table_name := $(csv_table_name)
tabledrop-$(csv_table_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(csv_table_name)
	rm -f $(TOP_LEVEL)/build/stamps/index-$(csv_table_name)-*
	$(MAKE) -s tabledropdeps-$(csv_table_name)
	$(PSQL) -c "DROP TABLE IF EXISTS $(csv_table_name) CASCADE"

$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): csv_table_name := $(csv_table_name)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): export csv_extra_index := $(csv_extra_index)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): export csv_schema := $(csv_schema)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name):: $(csv_file)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(csv_table_name)
	$(PSQL) -c "CREATE TABLE $(csv_table_name) $$csv_schema"
	zcat $< | buffer -z 262144 | docker exec -i gis_postgresql_1 psql ${POSTGRES_${PSQL_db}_NAME} ${POSTGRES_${PSQL_db}_USER} -c "COPY $(csv_table_name) FROM STDIN CSV HEADER"
	$(MAKE) -s index-$(csv_table_name)
ifneq ($(csv_extra_index),)
	$(PSQL) -c "$$csv_extra_index"
endif
	@touch "$@"
endif

csv_table_name =
csv_schema =
csv_file =
csv_extra_index =
PSQL_db = GIS
