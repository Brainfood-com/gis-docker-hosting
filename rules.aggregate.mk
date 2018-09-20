#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: aggregate_name -> The name of the table that stores the converted data
#  2: aggregate_signature -> The signature that defines the aggregate
#  3: aggregate_body -> The SQL that defines the aggregate
#  4: aggregate_dep_tables -> The tables the aggregate depends on

override aggregate_rules_needed = 1
ifeq ($(strip $(aggregate_name)),)
override aggregate_rules_needed =
endif
ifeq ($(strip $(aggregate_signature)),)
override aggregate_rules_needed =
endif
ifeq ($(strip $(aggregate_body)),)
override aggregate_rules_needed =
endif
ifeq ($(strip $(aggregate_table_deps)),)
override aggregate_rules_needed =
endif

# Always define the rules
aggregate-import:

ifeq ($(aggregate_rules_needed),1)

override aggregate_def_md5sum = $(shell echo "$(aggregate_signature):$(aggregate_body)" | md5sum | cut -f 1 -d ' ')

aggregate-import tableimport: table-$(aggregate_name)
table-$(aggregate_name): $(TOP_LEVEL)/build/stamps/table-$(aggregate_name)
tabledropdeps-$(aggregate_name)::
tabledrop: tabledrop-$(aggregate_name)
tabledrop-$(aggregate_name):: PSQL_db := $(PSQL_db)
tabledrop-$(aggregate_name):: aggregate_name := $(aggregate_name)
tabledrop-$(aggregate_name):: aggregate_signature := $(aggregate_signature)
tabledrop-$(aggregate_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(aggregate_name)
	$(MAKE) -s tabledropdeps-$(aggregate_name)
	$(PSQL) -c "DROP AGGREGATE IF EXISTS $(aggregate_name) $(aggregate_signature);"

$(patsubst %,tabledropdeps-%,$(aggregate_table_deps)):: tabledrop-$(aggregate_name)
$(TOP_LEVEL)/build/stamps/aggregate-$(aggregate_name).$(aggregate_def_md5sum): aggregate_name := $(aggregate_name)
$(TOP_LEVEL)/build/stamps/aggregate-$(aggregate_name).$(aggregate_def_md5sum): export aggregate_body := $(aggregate_body)
$(TOP_LEVEL)/build/stamps/aggregate-$(aggregate_name).$(aggregate_def_md5sum):
	@mkdir -p $(@D)
	@rm -f $(@D)/aggregate-$(aggregate_name).*
	echo "$$aggregate_body" > "$@.new"
	mv -- "$@.new" "$@"

$(TOP_LEVEL)/build/stamps/table-$(aggregate_name):: $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(aggregate_table_deps))
$(TOP_LEVEL)/build/stamps/table-$(aggregate_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(aggregate_name): aggregate_table_deps := $(aggregate_table_deps)
$(TOP_LEVEL)/build/stamps/table-$(aggregate_name): aggregate_name := $(aggregate_name)
$(TOP_LEVEL)/build/stamps/table-$(aggregate_name): aggregate_signature := $(aggregate_signature)
$(TOP_LEVEL)/build/stamps/table-$(aggregate_name): export aggregate_body := $(aggregate_body)

$(TOP_LEVEL)/build/stamps/table-$(aggregate_name):: $(TOP_LEVEL)/build/stamps/aggregate-$(aggregate_name).$(aggregate_def_md5sum)
	@mkdir -p $(@D)
	echo "aggregate_table_deps=$(aggregate_table_deps)"
	$(MAKE) -s tabledrop-$(aggregate_name)
	$(PSQL) -c "CREATE AGGREGATE $(aggregate_name) $(aggregate_signature) $$aggregate_body"
	@touch "$@"
endif

aggregate_name =
aggregate_body =
aggregate_table_deps =
PSQL_db = GIS
