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
PSQL = ./gis.sh psql gis ${POSTGRES_DB_USER}

ifeq ($(csv_rules_needed),1)

csvimport tableimport: table-$(csv_table_name)
table-$(csv_table_name): $(TOP_LEVEL)/build/stamps/table-$(csv_table_name)
tabledropdeps-$(csv_table_name)::
tabledrop: tabledrop-$(csv_table_name)
tabledrop-$(csv_table_name):: csv_table_name := $(csv_table_name)
tabledrop-$(csv_table_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(csv_table_name)
	$(MAKE) -s tabledropdeps-$(csv_table_name)
	$(PSQL) -c "DROP TABLE IF EXISTS $(csv_table_name)"

$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): csv_table_name := $(csv_table_name)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name): export csv_schema := $(csv_schema)
$(TOP_LEVEL)/build/stamps/table-$(csv_table_name):: $(csv_file)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(csv_table_name)
	$(PSQL) -c "CREATE TABLE $(csv_table_name) $$csv_schema"
	zcat $< | buffer -z 262144 | docker exec -i gis_postgresql_1 psql gis ${POSTGRES_DB_USER} -c "COPY $(csv_table_name) FROM STDIN CSV HEADER"
	@touch "$@"
endif

csv_table_name =
csv_schema =
csv_file =
