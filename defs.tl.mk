#!/usr/bin/make -f

# This rule set takes 3 variables:
#
#  1: view_table_name -> The name of the table that stores the converted data
#  2: view_sql -> The SQL that defines the view
#  3: view_dep_tables -> The tables the view depends on

# Always define the rules
download:
purge:
clean:

eval_protected = $(if $(filter 0,$(foreach v,$1,$(words $($v)))),,$(eval $($2)))

define tl_rules_def
download: download-tl_$(tl_year)_$(tl_key)_$(tl_type).zip
download-tl_$(tl_year)_$(tl_key)_$(tl_type).zip: data/tl_$(tl_year)_$(tl_key)_$(tl_type).zip
data/tl_$(tl_year)_$(tl_key)_$(tl_type).zip:
	mkdir -p $$(@D)/.tmp
	if [ -e $$@ ]; then cp -a $$@ $$(@D)/.tmp/$$(@F); fi
	wget -P $$(@D)/.tmp -c https://www2.census.gov/geo/tiger/TIGER$(tl_year)/$(shell echo "$(tl_type)" | tr '[a-z]' '[A-Z]')/$$(@F)
	mv $$(@D)/.tmp/$$(@F) $$@

purge: purge-tl_$(tl_year)_$(tl_key)_$(tl_type).zip
PHONY: purge-tl_$(tl_year)_$(tl_key)_$(tl_type).zip
purge-tl_$(tl_year)_$(tl_key)_$(tl_type).zip:
	rm -f data/tl_$(tl_year)_$(tl_key)_$(tl_type).zip

clean: clean-tl_$(tl_year)_$(tl_key)_$(tl_type).zip
PHONY: clean-tl_$(tl_year)_$(tl_key)_$(tl_type).zip
clean-tl_$(tl_year)_$(tl_key)_$(tl_type).zip:
	rm -f data/.tmp/.tl_$(tl_year)_$(tl_key)_$(tl_type).zip
endef

tl_rules = $(call eval_protected,tl_year tl_key tl_type,tl_rules_def)
