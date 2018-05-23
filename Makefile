#!/usr/bin/make -f

include .env.defaults
sinclude .env

override CURRENT_MAKEFILE_DIR := $(dir $(firstword $(MAKEFILE_LIST)))

empty :=
space := $(empty) $(empty)
comma := $(empty),$(empty)
open_paren := $(empty)($(empty)
close_paren := $(empty))$(empty)

default:
import:
prune:

PSQL_db = GIS
PSQL = ./gis.sh psql gis ${POSTGRES_${PSQL_db}_USER} < /dev/null

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

#$(TOP_LEVEL)/build/stamps/table-%::
#	@mkdir -p $(@D)
#	echo 'bar' "$@"
#	$(MAKE) -s tabledrop-$*

shp_data_file = data/lariac_buildings_2008.zip
shp_table_name = lariac_buildings
include rules.shp.mk

shp_data_file = data/tl_2017_06037_areawater.zip
shp_table_name = tl_2017_06037_areawater
include rules.shp.mk

shp_data_file = data/tl_2017_06037_roads.zip
shp_table_name = tl_2017_06037_roads
include rules.shp.mk

index_table_name = tl_2017_06037_roads
index_schema = CREATE INDEX itl_2017_06037_roads_fullname_like ON tl_2017_06037_roads USING gin (LOWER(fullname) gin_trgm_ops)
include rules.index.mk

shp_data_file = data/tl_2017_06_place.zip
shp_table_name = tl_2017_06_place
include rules.shp.mk

shp_data_file = data/tl_2017_us_state.zip
shp_table_name = tl_2017_us_state
include rules.shp.mk

view_table_name = sunset_road
view_sql = SELECT DISTINCT * FROM tl_2017_06037_roads WHERE LOWER(fullname) LIKE '%sunset blvd'
view_table_deps = tl_2017_06037_roads
include rules.view.mk

# another county?
# 135036 131438
#
# Cesar E Chavez rename?
# 124884
#
# Extrude?
# 124926 121508 124247 124930

view_table_name = sunset_road_problems
view_sql = SELECT DISTINCT * FROM sunset_road WHERE ogc_fid IN (135036, 131438, 124884, 124926, 121508, 124247, 124930)
view_table_deps = sunset_road
include rules.view.mk

view_table_name = sunset_road_reduced
view_sql = SELECT DISTINCT * FROM sunset_road WHERE ogc_fid NOT IN (SELECT ogc_fid FROM sunset_road_problems)
view_table_deps = sunset_road_problems
include rules.view.mk

view_table_name = sunset_road_debug
view_sql = SELECT ST_LineMerge(ST_Transform(ST_ApproximateMedialAxis(ST_Transform(ST_Simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001), 900913)), 4326)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT st_simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001) AS geom FROM sunset_road_reduced;
#view_sql = SELECT ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00002) AS geom FROM sunset_road;
#view_sql = select st_straightskeleton(foo) as geom from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .0001))).geom as foo from sunset_road limit 1) as foo;
#view_sql = select st_collect(st_approximatemedialaxis(foo)) as geom from (select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road limit 1 offset 1) as foo union select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road offset 3) as foo) as foo
view_table_deps = sunset_road_reduced
include rules.view.mk

view_table_name = sunset_road_merged
view_sql = SELECT ST_LINEMERGE(ST_UNION(wkb_geometry)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT st_approximatemedialaxis(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00003)) AS geom FROM sunset_road_reduced;
view_sql = SELECT ST_LineMerge(ST_Transform(ST_ApproximateMedialAxis(ST_Transform(ST_Simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001), 900913)), 4326)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00002) AS geom FROM sunset_road;
#view_sql = select st_straightskeleton(foo) as geom from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .0001))).geom as foo from sunset_road limit 1) as foo;
#view_sql = select st_collect(st_approximatemedialaxis(foo)) as geom from (select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road limit 1 offset 1) as foo union select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road offset 3) as foo) as foo
view_table_deps = sunset_road_reduced
include rules.view.mk

view_table_name = sunset_buildings
view_sql = SELECT DISTINCT a.* from lariac_buildings a INNER JOIN sunset_road_reduced b ON ST_DWithin(a.wkb_geometry, b.wkb_geometry, 0.001)
view_table_deps = lariac_buildings sunset_road_reduced
include rules.view.mk

static_table_name = iiif
define static_table_schema
(
	iiif_id SERIAL PRIMARY KEY,
	iiif_type_id TEXT,
	external_id TEXT UNIQUE,

	label TEXT
)
endef
include rules.static-table.mk
index_table_name = iiif
index_schema = CREATE INDEX iiif_external_id ON iiif(external_id)
include rules.index.mk

static_table_name = iiif_canvas
define static_table_schema
(
	iiif_id INTEGER REFERENCES iiif(iiif_id) PRIMARY KEY,

	format TEXT,
	height INTEGER,
	image TEXT,
	thumbnail TEXT,
	width INTEGER
)
endef
static_table_deps = iiif
include rules.static-table.mk

static_table_name = iiif_manifest
define static_table_schema
(
	iiif_id INTEGER REFERENCES iiif(iiif_id) PRIMARY KEY,

	attribution TEXT,
	description TEXT,
	license TEXT,
	logo TEXT,
	viewing_hint TEXT
)
endef
static_table_deps = iiif
include rules.static-table.mk

static_table_name = iiif_range
define static_table_schema
(
	iiif_id INTEGER REFERENCES iiif(iiif_id) PRIMARY KEY,

	viewing_hint TEXT
)
endef
static_table_deps = iiif
include rules.static-table.mk

static_table_name = iiif_assoc
define static_table_schema
(
	iiif_id_from INTEGER REFERENCES iiif(iiif_id),
	iiif_id_to INTEGER REFERENCES iiif(iiif_id),
	iiif_assoc_type_id TEXT,
	sequence_num NUMERIC,
	PRIMARY KEY (iiif_id_from, iiif_id_to, iiif_assoc_type_id)
)
endef
static_table_deps = iiif
include rules.static-table.mk

static_table_name = iiif_metadata
define static_table_schema
(
	iiif_id INTEGER REFERENCES iiif(iiif_id),
	label TEXT UNIQUE,
	sequence_num NUMERIC,
	value TEXT,
	PRIMARY KEY (iiif_id, label, sequence_num)
)
endef
static_table_deps = iiif
include rules.static-table.mk

csv_table_name = taxdata
define csv_schema
(
	zip_code TEXT,
	tax_rate_area_city TEXT,
	ain NUMERIC,
	roll_year NUMERIC,
	tax_rate_area TEXT,
	assessor_id TEXT,
	property_location TEXT,
	property_type TEXT,
	property_use_code TEXT,
	general_use_type TEXT,
	specific_use_type TEXT,
	specific_use_detail1 TEXT,
	specific_use_detail2 TEXT,
	tot_building_data_lines NUMERIC,
	year_built NUMERIC,
	effective_year_built NUMERIC,
	sqft_main NUMERIC,
	bedrooms NUMERIC,
	bathrooms NUMERIC,
	units NUMERIC,
	recording_date TEXT,
	land_value MONEY,
	land_base_year NUMERIC,
	improvement_value MONEY,
	imp_base_year NUMERIC,
	total_land_imp_value MONEY,
	homeowners_exemption MONEY,
	real_estate_exemption MONEY,
	fixture_value MONEY,
	fixture_exemption MONEY,
	personal_property_value MONEY,
	personal_property_exemption MONEY,
	is_taxable_parcel TEXT,
	total_value MONEY,
	total_exemption MONEY,
	net_taxable_value MONEY,
	special_parcel_classification TEXT,
	administrative_region TEXT,
	cluster TEXT,
	parcel_boundary_description TEXT,
	house_no NUMERIC,
	house_fraction TEXT,
	street_direction TEXT,
	street_name TEXT,
	unit_no TEXT,
	city TEXT,
	zip_code5 NUMERIC,
	row_id TEXT,
	center_lat TEXT,
	center_lon TEXT,
	location_1 TEXT
);
endef
define csv_extra_index
endef

csv_file = data/Assessor_Parcels_Data_-_2006_thru_2017.csv.gz
include rules.csv.mk

index_table_name = taxdata
index_schema = ALTER TABLE taxdata ADD PRIMARY KEY(row_id), ADD UNIQUE(ain, roll_year)
include rules.index.mk
#index_table_name = taxdata
#index_schema = ALTER TABLE taxdata ADD UNIQUE(ain, roll_year)
#include rules.index.mk
index_table_name = taxdata
index_schema = CREATE INDEX taxdata_assessor_id ON taxdata(assessor_id)
include rules.index.mk
index_table_name = taxdata
index_schema = CREATE INDEX taxdata_roll_year ON taxdata(roll_year)
include rules.index.mk
index_table_name = taxdata
index_schema = CREATE INDEX taxdata_street_name ON taxdata(street_name)
include rules.index.mk

view_table_name = sunset_taxdata
view_sql = SELECT * FROM taxdata a WHERE street_name = 'SUNSET BLVD'
view_table_deps = taxdata
include rules.view.mk

view_table_name = sunset_taxdata_2017
view_sql = SELECT * FROM sunset_taxdata WHERE roll_year = '2017'
view_table_deps = sunset_taxdata
include rules.view.mk

view_table_name = sunset_taxdata_2017_buildings
view_sql = SELECT b.* FROM sunset_taxdata_2017 a INNER JOIN lariac_buildings b ON a.ain::text = b.ain
view_table_deps = sunset_taxdata_2017 lariac_buildings
include rules.view.mk

view_table_name = sunset_taxdata_buildings
view_sql = SELECT DISTINCT b.* FROM sunset_taxdata a INNER JOIN lariac_buildings b ON a.ain::text = b.ain
view_table_deps = sunset_taxdata_2017 lariac_buildings
include rules.view.mk

