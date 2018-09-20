#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: function_name -> The name of the table that stores the converted data
#  2: function_body -> The SQL that defines the view
#  3: function_dep_tables -> The tables the view depends on

override view_rules_needed = 1
ifeq ($(strip $(function_name)),)
override view_rules_needed =
endif
ifeq ($(strip $(function_body)),)
override view_rules_needed =
endif
#ifeq ($(strip $(function_table_deps)),)
#override view_rules_needed =
#endif

# Always define the rules
view-import:

ifeq ($(view_rules_needed),1)

override function_def_md5sum = $(shell echo "mat=$(view_materialized):$(function_body)" | md5sum | cut -f 1 -d ' ')

viewimport tableimport: table-$(function_name)
table-$(function_name): $(TOP_LEVEL)/build/stamps/table-$(function_name)
tabledropdeps-$(function_name)::
tabledrop: tabledrop-$(function_name)
tabledrop-$(function_name):: PSQL_db := $(PSQL_db)
tabledrop-$(function_name):: function_name := $(function_name)
tabledrop-$(function_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(function_name)
	$(MAKE) -s tabledropdeps-$(function_name)
	$(PSQL) -c "DROP FUNCTION IF EXISTS $(function_name)"

$(patsubst %,tabledropdeps-%,$(function_table_deps)):: tabledrop-$(function_name)
$(TOP_LEVEL)/build/stamps/view-$(function_name).$(function_def_md5sum): function_name := $(function_name)
$(TOP_LEVEL)/build/stamps/view-$(function_name).$(function_def_md5sum): export function_body := $(function_body)
$(TOP_LEVEL)/build/stamps/view-$(function_name).$(function_def_md5sum):
	@mkdir -p $(@D)
	@rm -f $(@D)/view-$(function_name).*
	echo "$$function_body" > "$@.new"
	mv -- "$@.new" "$@"

$(TOP_LEVEL)/build/stamps/table-$(function_name):: $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(function_table_deps))
$(TOP_LEVEL)/build/stamps/table-$(function_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(function_name): function_table_deps := $(function_table_deps)
$(TOP_LEVEL)/build/stamps/table-$(function_name): function_name := $(function_name)
$(TOP_LEVEL)/build/stamps/table-$(function_name): export function_body := $(function_body)

$(TOP_LEVEL)/build/stamps/table-$(function_name):: $(TOP_LEVEL)/build/stamps/view-$(function_name).$(function_def_md5sum)
	@mkdir -p $(@D)
	echo "function_table_deps=$(function_table_deps)"
	$(MAKE) -s tabledrop-$(function_name)
	$(PSQL) -c "CREATE FUNCTION $(function_name) $$function_body"
	@touch "$@"
endif

function_name =
function_body =
function_table_deps =
PSQL_db = GIS
