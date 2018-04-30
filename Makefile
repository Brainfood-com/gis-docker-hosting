#!/usr/bin/make -f

include .env.defaults
sinclude .env

override CURRENT_MAKEFILE_DIR := $(dir $(firstword $(MAKEFILE_LIST)))

default:
import:
prune:

include rules.mk

# These are tools used by later steps
include maven.mk
include gdal.mk
include geoserver.mk

# This is where things start happening

table-%: $(TOP_LEVEL)/build/stamps/table-%
tabledropdeps-%::
tabledrop-%::
	rm -f $(TOP_LEVEL)/build/stamps/table-$*
	$(MAKE) -s tabledropdeps-$*

$(TOP_LEVEL)/build/stamps/table-%::
	@mkdir -p $(@D)
	$(MAKE) -s tabledrop-$*

shp_data_file = data/lariac_buildings_2008.zip
shp_table_name = lariac_buildings
include rules.shp.mk

shp_data_file = data/tl_2017_06037_areawater.zip
shp_table_name = tl_2017_06037_areawater
include rules.shp.mk
shp_data_file = data/tl_2017_06037_roads.zip
shp_table_name = tl_2017_06037_roads
include rules.shp.mk
shp_data_file = data/tl_2017_06_place.zip
shp_table_name = tl_2017_06_place
include rules.shp.mk
shp_data_file = data/tl_2017_us_state.zip
shp_table_name = tl_2017_us_state
include rules.shp.mk

view_table_name = sunset_road
view_sql = SELECT DISTINCT * FROM tl_2017_06037_roads WHERE LOWER(fullname) LIKE '%sunset blvd'
view_dep_tables = tl_2017_06037_roads
include rules.view.mk

view_table_name = sunset_buildings
view_sql = SELECT DISTINCT a.* from lariac_buildings a INNER JOIN sunset_road b ON ST_DWithin(a.wkb_geometry, b.wkb_geometry, 0.001)
view_dep_tables = lariac_buildings sunset_road
include rules.view.mk

csv_table_name = taxdata
define csv_schema
(
	zip_code TEXT,
	tax_rate_area_city TEXT,
	ain TEXT,
	roll_year TEXT,
	tax_rate_area TEXT,
	assessor_id TEXT,
	property_location TEXT,
	property_type TEXT,
	property_use_code TEXT,
	general_use_type TEXT,
	specific_use_type TEXT,
	specific_use_detail1 TEXT,
	specific_use_detail2 TEXT,
	tot_building_data_lines TEXT,
	year_built TEXT,
	effective_year_built TEXT,
	sqft_main TEXT,
	bedrooms TEXT,
	bathrooms TEXT,
	units TEXT,
	recording_date TEXT,
	land_value TEXT,
	land_base_year TEXT,
	improvement_value TEXT,
	imp_base_year TEXT,
	total_land_imp_value TEXT,
	homeowners_exemption TEXT,
	real_estate_exemption TEXT,
	fixture_value TEXT,
	fixture_exemption TEXT,
	personal_property_value TEXT,
	personal_property_exemption TEXT,
	is_taxable_parcel TEXT,
	total_value TEXT,
	total_exemption TEXT,
	net_taxable_value TEXT,
	special_parcel_classification TEXT,
	administrative_region TEXT,
	cluster TEXT,
	parcel_boundary_description TEXT,
	house_no TEXT,
	house_fraction TEXT,
	street_direction TEXT,
	street_name TEXT,
	unit_no TEXT,
	city TEXT,
	zip_code5 TEXT,
	row_id TEXT PRIMARY KEY,
	center_lat TEXT,
	center_lon TEXT,
	location_1 TEXT,
	UNIQUE(ain, roll_year)
);
CREATE INDEX taxdata_assessor_id ON taxdata(assessor_id);
CREATE INDEX taxdata_roll_year ON taxdata(roll_year);
CREATE INDEX taxdata_street_name ON taxdata(street_name);
endef

csv_file = data/Assessor_Parcels_Data_-_2006_thru_2017.csv.gz
include rules.csv.mk

view_table_name = sunset_taxdata
view_sql = SELECT * FROM taxdata a WHERE street_name = 'SUNSET BLVD'
view_dep_tables = taxdata
include rules.view.mk

view_table_name = sunset_taxdata_2017
view_sql = SELECT * FROM sunset_taxdata WHERE roll_year = '2017'
view_dep_tables = sunset_taxdata
include rules.view.mk

view_table_name = sunset_taxdata_2017_buildings
view_sql = SELECT b.* FROM sunset_taxdata_2017 a INNER JOIN lariac_buildings b ON a.ain = b.ain
view_dep_tables = sunset_taxdata_2017 lariac_buildings
include rules.view.mk

view_table_name = sunset_taxdata_buildings
view_sql = SELECT DISTINCT b.* FROM sunset_taxdata a INNER JOIN lariac_buildings b ON a.ain = b.ain
view_dep_tables = sunset_taxdata_2017 lariac_buildings
include rules.view.mk

