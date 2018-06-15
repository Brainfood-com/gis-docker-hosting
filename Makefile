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
index_table_name = lariac_buildings
index_schema = CREATE INDEX lariac_buildings_expand_geometry ON lariac_buildings USING gist (ST_Expand(wkb_geometry, 0.001))
include rules.index.mk
index_table_name = lariac_buildings
index_schema = CREATE INDEX lariac_buildings_ain ON lariac_buildings (ain)
include rules.index.mk

shp_data_file = data/tl_2017_06037_edges.zip
shp_table_name = tl_2017_06037_edges
include rules.shp.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_fullname_like ON tl_2017_06037_edges USING gin (LOWER(fullname) gin_trgm_ops)
include rules.index.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_tfidr ON tl_2017_06037_edges (tfidr)
include rules.index.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_tfidl ON tl_2017_06037_edges (tfidl)
include rules.index.mk

shp_data_file = data/tl_2017_06037_areawater.zip
shp_table_name = tl_2017_06037_areawater
include rules.shp.mk

shp_data_file = data/tl_2017_06037_roads.zip
shp_table_name = tl_2017_06037_roads
include rules.shp.mk
index_table_name = tl_2017_06037_roads
index_schema = CREATE INDEX tl_2017_06037_roads_fullname_like ON tl_2017_06037_roads USING gin (LOWER(fullname) gin_trgm_ops)
include rules.index.mk

shp_data_file = data/tl_2017_06_place.zip
shp_table_name = tl_2017_06_place
include rules.shp.mk

shp_data_file = data/tl_2017_us_state.zip
shp_table_name = tl_2017_us_state
include rules.shp.mk

view_table_name = sunset_road
view_sql = SELECT * FROM tl_2017_06037_roads WHERE LOWER(fullname) LIKE '%sunset blvd'
view_table_deps = tl_2017_06037_roads
#view_materialized = true
include rules.view.mk

view_table_name = sunset_road_edge
define view_sql
SELECT DISTINCT
	b.*
FROM
	tl_2017_06037_edges a JOIN tl_2017_06037_edges b ON
		(
			b.tfidr IN (a.tfidr, a.tfidl)
			OR
			b.tfidl IN (a.tfidr, a.tfidl)
		)
		AND
		b.roadflg = 'Y'
WHERE
	LOWER(a.fullname) LIKE '%sunset blvd'
endef
view_table_deps = tl_2017_06037_edges
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
view_sql = SELECT * FROM sunset_road WHERE ogc_fid IN (135036, 131438, 124884, 124926, 121508, 124247, 124930)
view_table_deps = sunset_road
#view_materialized = true
include rules.view.mk

view_table_name = sunset_road_reduced
view_sql = SELECT * FROM sunset_road WHERE ogc_fid NOT IN (SELECT ogc_fid FROM sunset_road_problems)
view_table_deps = sunset_road sunset_road_problems
#view_materialized = true
include rules.view.mk

view_table_name = sunset_road_debug
view_sql = SELECT ST_LineMerge(ST_Transform(ST_ApproximateMedialAxis(ST_Transform(ST_Simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001), 900913)), 4326)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT st_simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001) AS geom FROM sunset_road_reduced;
#view_sql = SELECT ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00002) AS geom FROM sunset_road;
#view_sql = select st_straightskeleton(foo) as geom from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .0001))).geom as foo from sunset_road limit 1) as foo;
#view_sql = select st_collect(st_approximatemedialaxis(foo)) as geom from (select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road limit 1 offset 1) as foo union select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road offset 3) as foo) as foo
view_table_deps = sunset_road_reduced
#view_materialized = true
include rules.view.mk

view_table_name = sunset_road_merged
view_sql = SELECT ST_LINEMERGE(ST_UNION(wkb_geometry)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT st_approximatemedialaxis(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00003)) AS geom FROM sunset_road_reduced;
view_sql = SELECT ST_LineMerge(ST_Transform(ST_ApproximateMedialAxis(ST_Transform(ST_Simplify(ST_BUFFER(ST_COLLECT(wkb_geometry), 0.0005), 0.0001), 900913)), 4326)) AS geom FROM sunset_road_reduced;
#view_sql = SELECT ST_BUFFER(ST_COLLECT(wkb_geometry), 0.00002) AS geom FROM sunset_road;
#view_sql = select st_straightskeleton(foo) as geom from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .0001))).geom as foo from sunset_road limit 1) as foo;
#view_sql = select st_collect(st_approximatemedialaxis(foo)) as geom from (select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road limit 1 offset 1) as foo union select * from (select (st_dump(st_Buffer(st_collect(wkb_geometry), .00015))).geom as foo from sunset_road offset 3) as foo) as foo
view_table_deps = sunset_road_reduced
#view_materialized = true
include rules.view.mk

view_table_name = sunset_buildings
view_sql = SELECT DISTINCT a.* from lariac_buildings a INNER JOIN sunset_road_reduced b ON ST_DWithin(a.wkb_geometry, b.wkb_geometry, 0.001)
view_table_deps = lariac_buildings sunset_road_reduced
view_materialized = true
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

static_table_name = iiif_tags
define static_table_schema
(
	iiif_tag_id SERIAL PRIMARY KEY,

	iiif_type_id TEXT,
	tag TEXT,
	UNIQUE (iiif_type_id, tag)
)
endef
include rules.static-table.mk

static_table_name = iiif_overrides
define static_table_schema
(
	iiif_override_id SERIAL PRIMARY KEY,
	external_id TEXT UNIQUE,
	notes TEXT
)
endef
include rules.static-table.mk

static_table_name = iiif_overrides_tags
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id),
	iiif_tag_id INTEGER REFERENCES iiif_tags(iiif_tag_id),
	sequence_num NUMERIC,
	PRIMARY KEY(iiif_override_id, iiif_tag_id)
)
endef
static_table_deps = iiif_overrides iiif_tags
include rules.static-table.mk

static_table_name = iiif_range_overrides
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id) PRIMARY KEY,

	fov_angle INTEGER,
	fov_depth INTEGER,
	fov_orientation TEXT CHECK (fov_orientation IN ('left', 'right'))
)
endef
static_table_deps = iiif_overrides
include rules.static-table.mk

static_table_name = iiif_canvas_overrides
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id) PRIMARY KEY,

	exclude BOOLEAN NOT NULL DEFAULT FALSE,
	hole BOOLEAN NOT NULL DEFAULT FALSE
)
endef
static_table_deps = iiif_overrides
include rules.static-table.mk

static_table_name = iiif_canvas_point_overrides
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id),

	iiif_canvas_override_source_id TEXT,

	priority INTEGER,
	point geometry(Point,4326),
	PRIMARY KEY(iiif_override_id, iiif_canvas_override_source_id),
	UNIQUE(iiif_override_id, iiif_canvas_override_source_id)
)
endef
static_table_deps = iiif_overrides
include rules.static-table.mk

view_table_name = range_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif_overrides.external_id,
  iiif_overrides.notes,
  iiif_range_overrides.*
FROM
  iiif JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  JOIN iiif_range_overrides ON
    iiif_overrides.iiif_override_id = iiif_range_overrides.iiif_override_id
endef
view_table_deps = iiif_overrides iiif_range_overrides
include rules.view.mk

view_table_name = canvas_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif_overrides.external_id,
  iiif_overrides.notes,
  iiif_canvas_overrides.*
FROM
  iiif JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  JOIN iiif_canvas_overrides ON
    iiif_overrides.iiif_override_id = iiif_canvas_overrides.iiif_override_id
endef
view_table_deps = iiif_overrides iiif_canvas_overrides
include rules.view.mk

view_table_name = canvas_point_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif_overrides.external_id,
  iiif_canvas_point_overrides.*
FROM
  iiif JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  JOIN iiif_canvas_point_overrides ON
    iiif_overrides.iiif_override_id = iiif_canvas_point_overrides.iiif_override_id
endef
view_table_deps = iiif iiif_overrides iiif_canvas_point_overrides
include rules.view.mk

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
index_table_name = taxdata
index_schema = CREATE INDEX taxdata_ain ON taxdata(ain)
include rules.index.mk

view_table_name = sunset_taxdata
view_sql = SELECT * FROM taxdata a WHERE street_name = 'SUNSET BLVD'
view_table_deps = taxdata
#view_materialized = true
include rules.view.mk

view_table_name = sunset_taxdata_2017
view_sql = SELECT * FROM sunset_taxdata WHERE roll_year = '2017'
view_table_deps = sunset_taxdata
#view_materialized = true
include rules.view.mk

view_table_name = sunset_taxdata_2017_buildings
view_sql = SELECT b.* FROM sunset_taxdata_2017 a INNER JOIN lariac_buildings b ON a.ain::text = b.ain
view_table_deps = sunset_taxdata_2017 lariac_buildings
#view_materialized = true
include rules.view.mk

view_table_name = sunset_taxdata_buildings
view_sql = SELECT DISTINCT b.* FROM sunset_taxdata a INNER JOIN lariac_buildings b ON a.ain::text = b.ain
view_table_deps = sunset_taxdata lariac_buildings
#view_materialized = true
include rules.view.mk

view_table_name = collection
define view_sql
SELECT
  can_base.iiif_id,
  can_base.external_id,
  can_base.label,
  can_base.iiif_type_id
FROM
  iiif can_base
WHERE
  can_base.iiif_type_id = 'sc:Collection'
endef
view_table_deps = iiif
include rules.view.mk

view_table_name = manifest
define view_sql
SELECT
  can_base.external_id,
  can_base.label,
  can_base.iiif_type_id,
  manifest.*
FROM
  iiif can_base JOIN iiif_manifest manifest ON
    can_base.iiif_id = manifest.iiif_id
endef
view_table_deps = iiif iiif_manifest
include rules.view.mk

view_table_name = range
define view_sql
SELECT
  can_base.external_id,
  can_base.label,
  can_base.iiif_type_id,
  range.*
FROM
  iiif can_base JOIN iiif_range range ON
    can_base.iiif_id = range.iiif_id
endef
view_table_deps = iiif iiif_range
include rules.view.mk

view_table_name = canvas
define view_sql
SELECT
  can_base.external_id,
  can_base.label,
  can_base.iiif_type_id,
  canvas.*
FROM
  iiif can_base JOIN iiif_canvas canvas ON
    can_base.iiif_id = canvas.iiif_id
endef
view_table_deps = iiif iiif_canvas
include rules.view.mk

view_table_name = sequence_canvas
define view_sql
SELECT
  man_seq_assoc.iiif_id_from AS manifest_id,
  man_seq_assoc.iiif_id_to AS sequence_id,
  seq_can_assoc.sequence_num AS sequence_num,
  canvas.*
FROM
  iiif man_base JOIN iiif_assoc man_seq_assoc ON
    man_base.iiif_type_id = 'sc:Manifest'
    AND
    man_base.iiif_id = man_seq_assoc.iiif_id_from
    AND
    man_seq_assoc.iiif_assoc_type_id = 'sc:Sequence'
  JOIN iiif_assoc seq_can_assoc ON
    man_seq_assoc.iiif_id_to = seq_can_assoc.iiif_id_from
    AND
    seq_can_assoc.iiif_assoc_type_id = 'sc:Canvas'
  JOIN canvas ON
    seq_can_assoc.iiif_id_to = canvas.iiif_id
endef
view_table_deps = iiif iiif_assoc canvas
include rules.view.mk

view_table_name = range_canvas
define view_sql
SELECT
  ran_can_assoc.iiif_id_from AS range_id,
  ran_can_assoc.sequence_num AS sequence_num,
  canvas.*
FROM
  iiif_assoc ran_can_assoc JOIN canvas ON
    ran_can_assoc.iiif_assoc_type_id = 'sc:Canvas'
    AND
    ran_can_assoc.iiif_id_to = canvas.iiif_id
endef
view_table_deps = iiif iiif_assoc canvas
include rules.view.mk

view_table_name = canvas_geoposition_base
define view_sql
SELECT
    range_canvas.range_id AS range_id,
    (row_number() OVER (ORDER BY range_canvas.sequence_num) - 1)::float / (count(*) OVER () - 1)::float AS position,
    (SELECT json_agg(json_build_object(
      'iiif_canvas_override_source_id', iiif_canvas_override_source_id,
      'priority', priority,
      'notes', notes,
      'point', ST_AsGeoJSON(point)
    )) FROM canvas_overrides WHERE external_id = can_base.external_id) AS overrides,
    can_base.label, can.*
FROM
  range_canvas JOIN iiif can_base ON
    range_canvas.iiif_id = can_base.iiif_id
  JOIN iiif_canvas can ON
    can_base.iiif_id = can.iiif_id
endef
view_table_deps = range_canvas iiif iiif_canvas canvas_overrides
include rules.view.mk


