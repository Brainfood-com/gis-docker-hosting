#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: view_table_name -> The name of the table that stores the converted data
#  2: view_sql -> The SQL that defines the view
#  3: view_dep_tables -> The tables the view depends on

override view_rules_needed = 1
ifeq ($(strip $(view_table_name)),)
override view_rules_needed =
endif
ifeq ($(strip $(view_sql)),)
override view_rules_needed =
endif
ifeq ($(strip $(view_dep_tables)),)
override view_rules_needed =
endif

# Always define the rules
view-import:
PSQL = ./gis.sh psql gis ${POSTGRES_DB_USER} < /dev/null

ifeq ($(view_rules_needed),1)

override view_def_md5sum = $(shell echo "$(view_sql)" | md5sum | cut -f 1 -d ' ')

viewimport tableimport: table-$(view_table_name)
table-$(view_table_name): $(TOP_LEVEL)/build/stamps/table-$(view_table_name)
tabledropdeps-$(view_table_name)::
tabledrop: tabledrop-$(view_table_name)
tabledrop-$(view_table_name):: view_table_name := $(view_table_name)
tabledrop-$(view_table_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(view_table_name)
	$(MAKE) -s tabledropdeps-$(view_table_name)
	$(PSQL) -c "DROP MATERIALIZED VIEW IF EXISTS $(view_table_name)"

$(patsubst %,tabledropdeps-%,$(view_dep_tables)):: tabledrop-$(view_table_name)
$(TOP_LEVEL)/build/stamps/view-$(view_table_name).$(view_def_md5sum): view_table_name := $(view_table_name)
$(TOP_LEVEL)/build/stamps/view-$(view_table_name).$(view_def_md5sum): view_sql := $(view_sql)
$(TOP_LEVEL)/build/stamps/view-$(view_table_name).$(view_def_md5sum):
	@mkdir -p $(@D)
	@rm -f $(@D)/view-$(view_table_name).*
	echo "$(view_sql)" > "$@.new"
	mv -- "$@.new" "$@"

$(TOP_LEVEL)/build/stamps/table-$(view_table_name):: $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(view_dep_tables))
$(TOP_LEVEL)/build/stamps/table-$(view_table_name): view_table_name := $(view_table_name)
$(TOP_LEVEL)/build/stamps/table-$(view_table_name): view_sql := $(view_sql)

$(TOP_LEVEL)/build/stamps/table-$(view_table_name):: $(TOP_LEVEL)/build/stamps/view-$(view_table_name).$(view_def_md5sum)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(view_table_name)
	$(PSQL) -c "CREATE MATERIALIZED VIEW $(view_table_name) AS $(view_sql)"
	@touch "$@"
endif

view_table_name =
view_sql =
view_dep_tables =
