#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: view_table_name -> The name of the table that stores the converted data
#  2: view_sql -> The SQL that defines the view
#  3: view_dep_tables -> The tables the view depends on

override index_rules_needed = 1
ifeq ($(strip $(index_table_name)),)
override index_rules_needed =
endif
ifeq ($(strip $(index_schema)),)
override index_rules_needed =
endif

override index_schema_quoted = $(subst $(comma),_,$(subst $(close_paren),_,$(subst $(open_paren),_,$(subst $(space),_,$(index_schema)))))
override index_schema_quoted = $(subst $(space),_,$(index_schema))

# Always define the rules
tableindex:
PSQL = ./gis.sh psql gis ${POSTGRES_DB_USER}

ifeq ($(index_rules_needed),1)

tableindex: index-$(index_table_name)
index-$(index_table_name): $(TOP_LEVEL)/build/stamps/index-$(index_table_name)-$(index_schema_quoted)

$(TOP_LEVEL)/build/stamps/index-$(index_table_name)-$(index_schema_quoted): index_schema := $(index_schema)
$(TOP_LEVEL)/build/stamps/index-$(index_table_name)-$(index_schema_quoted):
	@mkdir -p $(@D)
	$(PSQL) -c "$(index_schema)"
	@touch "$@"
endif

index_table_name =
index_schema = 
