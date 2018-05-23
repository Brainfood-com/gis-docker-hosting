#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: static_table_name -> The name of the table that stores the converted data
#  2: static_table_schema -> The SQL that defines the view
#  3: static_table_deps -> The tables the view depends on

override static_table_rules_needed = 1
ifeq ($(strip $(static_table_name)),)
override static_table_rules_needed =
endif
ifeq ($(strip $(static_table_schema)),)
override static_table_rules_needed =
endif
#ifeq ($(strip $(static_dep_tables)),)
#override static_table_rules_needed =
#endif

# Always define the rules
statictableimport:
statictabledrop:

ifeq ($(static_table_rules_needed),1)

override static_table_schema_md5sum := $(shell echo "$(static_table_schema)" | md5sum | cut -f 1 -d ' ')

statictableimport tableimport: table-$(static_table_name)
index-$(static_table_name):
table-$(static_table_name): $(TOP_LEVEL)/build/stamps/table-$(static_table_name)
tabledropdeps-$(static_table_name)::
tabledrop statictabledrop: tabledrop-$(static_table_name)
tabledrop-$(static_table_name):: PSQL_db := $(PSQL_db)
tabledrop-$(static_table_name):: static_table_name := $(static_table_name)
tabledrop-$(static_table_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(static_table_name)
	$(MAKE) -s tabledropdeps-$(static_table_name)
	$(PSQL) -c "DROP TABLE IF EXISTS $(static_table_name)"

$(patsubst %,tabledropdeps-%,$(static_table_deps)):: tabledrop-$(static_table_name)
$(TOP_LEVEL)/build/stamps/static-table-$(static_table_name).$(static_table_schema_md5sum): static_table_name := $(static_table_name)
$(TOP_LEVEL)/build/stamps/static-table-$(static_table_name).$(static_table_schema_md5sum): export static_table_schema := $(static_table_schema)
$(TOP_LEVEL)/build/stamps/static-table-$(static_table_name).$(static_table_schema_md5sum):
	@mkdir -p $(@D)
	rm -f $(@D)/static-table-$(static_table_name).*
	echo "$${static_table_schema}" > "$@.new"
	mv -- "$@.new" "$@"

$(TOP_LEVEL)/build/stamps/table-$(static_table_name):: $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(static_table_deps))
$(TOP_LEVEL)/build/stamps/table-$(static_table_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(static_table_name): static_table_name := $(static_table_name)
$(TOP_LEVEL)/build/stamps/table-$(static_table_name): export static_table_schema := $(static_table_schema)

$(TOP_LEVEL)/build/stamps/table-$(static_table_name):: $(TOP_LEVEL)/build/stamps/static-table-$(static_table_name).$(static_table_schema_md5sum)
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$(static_table_name)
	$(PSQL) -c "CREATE TABLE $(static_table_name) $${static_table_schema}"
	$(MAKE) -s index-$(static_table_name)
	touch "$@"
endif

static_table_name =
static_table_schema =
static_table_deps =
PSQL_db = GIS
