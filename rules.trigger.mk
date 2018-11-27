#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: trigger_name -> The name of the trigger
#  2: trigger_body -> The SQL that defines the trigger
#  3: trigger_table_deps -> The tables the trigger depends on

override trigger_rules_needed = 1
ifeq ($(strip $(trigger_name)),)
override trigger_rules_needed =
endif
ifeq ($(strip $(trigger_table)),)
override trigger_rules_needed =
endif
ifeq ($(strip $(trigger_events)),)
override trigger_rules_needed =
endif
ifeq ($(strip $(trigger_body)),)
override trigger_rules_needed =
endif
#ifeq ($(strip $(trigger_table_deps)),)
#override trigger_rules_needed =
#endif

triggers:

ifeq ($(trigger_rules_needed),1)

override trigger_def_md5sum = $(shell echo "table=$(trigger_table):events=$(trigger_events):$(trigger_body)" | md5sum | cut -f 1 -d ' ')

triggers tableimport: table-$(trigger_name)
table-$(trigger_name): $(TOP_LEVEL)/build/stamps/table-$(trigger_name)
tabledropdeps-$(trigger_name)::
tabledrop: tabledrop-$(trigger_name)
tabledrop-$(trigger_name):: PSQL_db := $(PSQL_db)
tabledrop-$(trigger_name):: trigger_name := $(trigger_name)
tabledrop-$(trigger_name):: trigger_table := $(trigger_table)
tabledrop-$(trigger_name)::
	rm -f $(TOP_LEVEL)/build/stamps/table-$(trigger_name)
	$(MAKE) -s tabledropdeps-$(trigger_name)
	$(PSQL) -c "DROP TRIGGER IF EXISTS $(trigger_name) ON $(trigger_table)"

$(patsubst %,tabledropdeps-%,$(trigger_table_deps)):: tabledrop-$(trigger_name)
$(TOP_LEVEL)/build/stamps/trigger-$(trigger_name).$(trigger_def_md5sum): trigger_name := $(trigger_name)
$(TOP_LEVEL)/build/stamps/trigger-$(trigger_name).$(trigger_def_md5sum): export trigger_body := $(trigger_body)
$(TOP_LEVEL)/build/stamps/trigger-$(trigger_name).$(trigger_def_md5sum):
	@mkdir -p $(@D)
	@rm -f $(@D)/trigger-$(trigger_name).*
	echo "$$trigger_body" > "$@.new"
	mv -- "$@.new" "$@"

$(TOP_LEVEL)/build/stamps/table-$(trigger_name):: $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(trigger_table_deps))
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): PSQL_db := $(PSQL_db)
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): trigger_table_deps := $(trigger_table_deps)
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): trigger_name := $(trigger_name)
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): trigger_table := $(trigger_table)
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): trigger_events := $(trigger_events)
$(TOP_LEVEL)/build/stamps/table-$(trigger_name): export trigger_body := $(trigger_body)

$(TOP_LEVEL)/build/stamps/table-$(trigger_name):: $(TOP_LEVEL)/build/stamps/trigger-$(trigger_name).$(trigger_def_md5sum)
	@mkdir -p $(@D)
	echo "trigger_table_deps=$(trigger_table_deps)"
	$(MAKE) -s tabledrop-$(trigger_name)
	$(PSQL) -c "CREATE TRIGGER $(trigger_name) $(trigger_events) ON $(trigger_table) $$trigger_body"
	@touch "$@"
endif

trigger_name =
trigger_body =
trigger_table_deps =
