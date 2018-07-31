#!/usr/bin/make -f

include .env.defaults
sinclude .env

override CURRENT_MAKEFILE_DIR := $(dir $(firstword $(MAKEFILE_LIST)))

empty :=
space := $(empty) $(empty)
comma := $(empty),$(empty)
colon := $(empty):$(empty)
open_paren := $(empty)($(empty)
close_paren := $(empty))$(empty)

default:
default: tableimport configure-geoserver
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
tl_year = 2017
tl_key = 06037
tl_type = edges
#$(call tl_rules)

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
index_schema = ALTER TABLE tl_2017_06037_edges ALTER COLUMN wkb_geometry TYPE geometry(LineString,4326) USING ST_GeometryN(wkb_geometry, 1)
include rules.index.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_fullname_like ON tl_2017_06037_edges USING gin (LOWER(fullname) gin_trgm_ops)
include rules.index.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_tfidr ON tl_2017_06037_edges (tfidr)
include rules.index.mk
index_table_name = tl_2017_06037_edges
index_schema = CREATE INDEX tl_2017_06037_edges_tfidl ON tl_2017_06037_edges (tfidl)
include rules.index.mk

function_name = gisapp_nearest_edge
define function_body
-- explain
(point geometry) RETURNS integer
AS
$$body$$
WITH fast_query AS (
	SELECT
		wkb_geometry,
		ogc_fid
	FROM
		tl_2017_06037_edges
	WHERE
		roadflg = 'Y'
	ORDER BY
		wkb_geometry <#> $$1
	LIMIT 30
)
SELECT
	ogc_fid
FROM
	fast_query
WHERE
	$$1 IS NOT NULL
ORDER BY
	ST_Distance(wkb_geometry, $$1)
LIMIT 1
$$body$$
immutable
language sql;
endef
function_table_deps = tl_2017_06037_edges
include rules.function.mk

view_table_name = tl_2017_06037_edges_gis_routing
view_materialized = true
define view_sql
SELECT
	a.ogc_fid AS id,
	a.tnidf::integer AS source,
	a.tnidt::integer AS target,
	CASE
		WHEN gis_drivable THEN ST_Length(ST_Transform(a.wkb_geometry, 4326)::geography)
		ELSE -1
	END::float8 AS cost,
	ST_X(ST_StartPoint(a.wkb_geometry)) AS x1,
	ST_Y(ST_StartPoint(a.wkb_geometry)) AS y1,
	ST_X(ST_EndPoint(a.wkb_geometry)) AS x2,
	ST_Y(ST_EndPoint(a.wkb_geometry)) AS y2
FROM
	(
		SELECT
			CASE
				WHEN hydroflg = 'Y' THEN false
				WHEN railflg = 'Y' THEN false
				WHEN roadflg = 'Y' THEN true
				ELSE false
			END AS gis_drivable,
			*
		FROM
			tl_2017_06037_edges

	) a
WHERE
	tfidl IS NOT NULL AND tfidr IS NOT NULL
endef
view_table_deps = tl_2017_06037_edges
include rules.view.mk

static_table_name = route_cache
define static_table_schema
(
	start_point geometry(Point, 4326),
	end_point geometry(Point, 4326),
	route geometry(LineString, 4326),
	PRIMARY KEY(start_point, end_point)
)
endef
include rules.static-table.mk
index_table_name = route_cache
index_schema = CREATE INDEX route_cache_start_point ON route_cache USING gist(start_point)
include rules.index.mk
index_table_name = route_cache
index_schema = CREATE INDEX route_cache_end_point ON route_cache USING gist(end_point)
include rules.index.mk

function_name = route_point_data
define function_body
(point geometry(Point, 4326)) RETURNS TABLE(
	edge bigint,
	from_node bigint,
	to_node bigint,
	cost double precision,
	percentage double precision,
	point geometry
)
AS
$$body$$
WITH
phase_1 AS (
	SELECT gisapp_nearest_edge(point) AS edge
)
SELECT
	edges.ogc_fid::bigint AS edge,
	edges.tnidf::bigint AS from_node,
	edges.tnidt::bigint AS to_node,
	ST_Length(ST_Transform(edges.wkb_geometry, 4326)::geography) AS cost,
	ST_LineLocatePoint(edges.wkb_geometry, point) AS percentage,
	ST_ClosestPoint(edges.wkb_geometry, point) AS point
FROM
	tl_2017_06037_edges edges
WHERE
	edges.ogc_fid = (SELECT edge FROM phase_1)
$$body$$
language sql;
endef
function_table_deps = tl_2017_06037_edges
include rules.function.mk

function_name = route_build
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS geometry
AS
$$body$$
WITH
param_start AS (SELECT * FROM route_point_data(start_at)),
param_end AS (SELECT * FROM route_point_data(end_at)),
plan AS (
	SELECT
		path_seq,
		node,
		edge,
		cost
	FROM
		pgr_dijkstra('select * from tl_2017_06037_edges_gis_routing', (SELECT from_node FROM param_start), (SELECT to_node FROM param_end), directed:=false)
--		pgr_astar('select * from tl_2017_06037_edges_gis_routing', (SELECT from_node FROM param_start), (SELECT to_node FROM param_end), directed:=false)
	WHERE
		edge != -1
),
first_plan_row AS (
	SELECT * FROM plan ORDER BY path_seq LIMIT 1
),
last_plan_row AS (
	SELECT * FROM plan ORDER BY path_seq DESC LIMIT 1
),
include_start AS (
	SELECT
		-1 AS path_seq,
		to_node AS node,
		edge,
		cost
	FROM
		param_start
	WHERE NOT EXISTS (SELECT path_seq FROM plan JOIN param_start ON plan.edge = param_start.edge)
),
include_end AS (
	SELECT
		(SELECT max(path_seq) + 1 FROM plan) AS path_seq,
		from_node AS node,
		edge,
		cost
	FROM
		param_end
	WHERE NOT EXISTS (SELECT path_seq FROM plan JOIN param_end ON plan.edge = param_end.edge)
),
all_edges AS (
	SELECT * FROM include_start
	UNION
	SELECT * FROM plan
	UNION
	SELECT * FROM include_end
),
join_geom AS (
	SELECT
		a.*,
		CASE
			WHEN a.node = edges.tnidf THEN edges.wkb_geometry
			ELSE ST_Reverse(edges.wkb_geometry)
		END AS geom
	FROM
		all_edges a JOIN tl_2017_06037_edges edges ON
			a.edge = edges.ogc_fid
	ORDER BY
		a.path_seq
),
build_line AS (
	SELECT ST_MakeLine((SELECT ST_MakeLine(geom) FROM join_geom)) AS line
),
line_points AS (
	SELECT
		ST_LineLocatePoint(a.line, param_start.point) AS start_percent,
		ST_LineLocatePoint(a.line, param_end.point) AS end_percent
	FROM
		build_line a,
		param_start,
		param_end
),
fixed_line_points AS (
	SELECT
		CASE WHEN start_percent > end_percent THEN end_percent ELSE start_percent END as start_percent,
		CASE WHEN start_percent > end_percent THEN start_percent ELSE end_percent END as end_percent
	FROM
		line_points
)
SELECT
	ST_LineSubstring(a.line, b.start_percent, b.end_percent) AS route
FROM
	build_line a,
	fixed_line_points b
$$body$$
language sql;
endef
function_table_deps = route_point_data tl_2017_06037_edges
include rules.function.mk

# TODO: Split first and last edges if the points are in the middle
function_name = plan_route
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS geometry(LineString, 4326)
AS
$$body$$
WITH
new_row AS (
	INSERT INTO route_cache (start_point, end_point, route)
	SELECT
		start_at,
		end_at,
		route_build(start_at, end_at) AS route
	WHERE
		NOT EXISTS (SELECT route FROM route_cache WHERE start_point = start_at AND end_point = end_at)
	ON CONFLICT DO NOTHING
	RETURNING route
)
SELECT route FROM new_row
UNION
SELECT route FROM route_cache WHERE start_point = start_at AND end_point = end_at
$$body$$
language sql;
endef
function_table_deps = tl_2017_06037_edges route_build route_cache
include rules.function.mk


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
view_sql = SELECT * FROM tl_2017_06037_roads WHERE LOWER(fullname) SIMILAR TO '%(sunset blvd|w cesar e chavez ave)'
view_table_deps = tl_2017_06037_roads
#view_materialized = true
include rules.view.mk

view_table_name = sunset_road_edges
define view_sql
SELECT *
FROM
	tl_2017_06037_edges
WHERE
	(
		LOWER(fullname) SIMILAR TO '%(sunset blvd|w cesar e chavez ave)'
		AND
		tlid NOT IN (141615850, 141615852, 141615860, 141618155)
	)
	OR
	tlid IN (142718688, 241139227, 142718318, 142683751)
endef
view_table_deps = tl_2017_06037_edges
include rules.view.mk

view_table_name = sunset_road_edges_connected
define view_sql
SELECT DISTINCT
	b.*
FROM
	sunset_road_edges a JOIN tl_2017_06037_edges b ON
		(
			b.tfidr IN (a.tfidr, a.tfidl)
			OR
			b.tfidl IN (a.tfidr, a.tfidl)
		)
		AND
		b.roadflg = 'Y'
endef
view_table_deps = tl_2017_06037_edges sunset_road_edges
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

	exclude BOOLEAN DEFAULT FALSE,
	hole BOOLEAN DEFAULT FALSE
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
      'point', ST_AsGeoJSON(point)
    )) FROM canvas_point_overrides WHERE external_id = can_base.external_id) AS overrides,
    can_base.label, can.*
FROM
  range_canvas JOIN iiif can_base ON
    range_canvas.iiif_id = can_base.iiif_id
  JOIN iiif_canvas can ON
    can_base.iiif_id = can.iiif_id
endef
view_table_deps = range_canvas iiif iiif_canvas canvas_overrides
include rules.view.mk

view_table_name = range_canvas_routing_base
define view_sql
WITH
road AS (
	SELECT st_linemerge(st_collect(geom)) AS geom FROM sunset_road_merged
),
road_meta AS (
	SELECT
		ST_StartPoint(road.geom) AS start_point,
		gisapp_nearest_edge(ST_StartPoint(road.geom)) AS start_edge,
		ST_EndPoint(road.geom) AS end_point,
		gisapp_nearest_edge(ST_EndPoint(road.geom)) AS end_edge
	FROM
		road
),
canvas_point_override AS (
	SELECT
		iiif.iiif_id,
		canvas_point_overrides.point,
		gisapp_nearest_edge(canvas_point_overrides.point) AS edge
	FROM
		iiif JOIN canvas_point_overrides ON
			iiif.external_id = canvas_point_overrides.external_id
	GROUP BY
		iiif.iiif_id,
		canvas_point_overrides.point
),
canvas_range_grouping AS (
	SELECT
		a.range_id,
		a.iiif_id,
		a.sequence_num,
		b.point,
		c.exclude,
		count(b.point) OVER (PARTITION BY c.exclude IS NULL OR c.exclude = false, a.range_id ORDER BY a.sequence_num) AS forward,
		count(b.point) OVER (PARTITION BY c.exclude IS NULL OR c.exclude = false, a.range_id ORDER BY a.sequence_num DESC) AS reverse,
		percent_rank() OVER (PARTITION BY c.exclude IS NULL OR c.exclude = false, a.range_id, count(b.point) ORDER BY a.sequence_num) start_rank,
		cume_dist() OVER (PARTITION BY c.exclude IS NULL OR c.exclude = false, a.range_id, count(b.point) ORDER BY a.sequence_num) other_rank
	FROM
		range_canvas a LEFT JOIN canvas_point_overrides b ON
			a.external_id = b.external_id
		LEFT JOIN canvas_overrides c ON
			a.iiif_id = c.iiif_id
	GROUP BY
		a.range_id,
		a.iiif_id,
		c.exclude,
		a.sequence_num,
		b.point
)
SELECT
	canvas_range_grouping.*
--	COALESCE(first_value(canvas_range_grouping.point) OVER (PARTITION BY canvas_range_grouping.reverse ORDER BY canvas_range_grouping.sequence_num DESC), (SELECT end_point FROM road_meta)) AS end_point,
--	COALESCE(first_value(canvas_range_grouping.point) OVER (PARTITION BY canvas_range_grouping.forward ORDER BY canvas_range_grouping.sequence_num), (SELECT start_point FROM road_meta)) AS start_point
FROM
	canvas_range_grouping
ORDER BY
	sequence_num
endef
view_table_deps = range_canvas iiif canvas_point_overrides canvas_overrides gisapp_nearest_edge
include rules.view.mk

PHONY: tableimport configure-geoserver import-tables dump-tables iiif-import

iiif_json_files := $(shell find data/media.getty.edu/ -name '*.json')
iiif_tables = iiif iiif_metadata iiif_assoc iiif_manifest iiif_range iiif_canvas
iiif-import: $(TOP_LEVEL)/build/stamps/iiif-import
$(TOP_LEVEL)/build/stamps/iiif-import: $(iiif_json_files) $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(iiif_tables))
	@mkdir -p $(@D)
	./gis.sh gis-iiif-loader $(iiif_json_files)
	@touch $@

geoserver_tables := $(shell sed -n 's/^postgis featuretype publish --workspace gis --datastore postgresql --table \(.*\)/\1/p' init-geoserver.gs-shell)

configure-geoserver: $(TOP_LEVEL)/build/stamps/configure-geoserver
$(TOP_LEVEL)/build/stamps/configure-geoserver: init-geoserver.gs-shell $(patsubst %,$(TOP_LEVEL)/build/stamps/table-%,$(geoserver_tables))
	@mkdir -p $(@D)
	./gis.sh gs-shell --cmdfile init-geoserver.gs-shell
	@touch $@

tables_to_dump = iiif_overrides iiif_canvas_overrides iiif_canvas_point_overrides iiif_range_overrides iiif_tags iiif_overrides_tags

dump-tables: $(patsubst %,dump-table.%,$(tables_to_dump))

$(patsubst %,dump-table.%,$(tables_to_dump)): dump-table.%:
	@mkdir -p dumps
	./gis.sh pg_dump gis --column-inserts -at $* | sed 's/^\(INSERT .*\);\r\?$$/\1 ON CONFLICT DO NOTHING;/' > dumps/$*.tmp
	@mv dumps/$*.tmp dumps/$*.sql

import-tables: $(patsubst dumps/%.sql,import-table.%,$(wildcard dumps/*.sql))

$(patsubst %,import-table.%,iiif_canvas_overrides iiif_canvas_point_overrides iiif_range_overrides iiif_overrides_tags): import-table.iiif_overrides
$(patsubst %,import-table.%,iiif_overrides_tags): import-table.iiif_tags
import-table.%: dumps/%.sql $(TOP_LEVEL)/build/stamps/table-%
	./gis.sh psql -P pager=off -Atqc 'SELECT 1'
	docker exec -i -u postgres gis_postgresql_1 psql gis < dumps/$*.sql
