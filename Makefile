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
PSQL = ./bin/psql gis ${POSTGRES_${PSQL_db}_USER} < /dev/null

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

function_name = gisapp_camera_fov_plpgsql
define function_body
-- explain
(point geometry, direction float, depth float, spread float) RETURNS geometry
AS
$$body$$
-- direction is degrees
-- depth is meters
-- spread is degrees
DECLARE
	_pi float = pi();
	_left float = _pi * (direction - spread / 2) / 180;
	_right float = _pi * (direction + spread / 2) / 180;
	_double_depth float = 2 * depth / 200000;
	E1 float := _double_depth * sin(_left);
	E2 float := _double_depth * sin(_right);
	N1 float := _double_depth * cos(_left);
	N2 float := _double_depth * cos(_right);
	_x float := ST_X(point::geometry);
	_y float := ST_Y(point::geometry);
	point1 geometry := ST_SetSRID(ST_Point(_x + E1, _y + N1), ST_SRID(point));
	point2 geometry := ST_SetSRID(ST_Point(_x + E2, _y + N2), ST_SRID(point));
	triangle geometry := ST_SetSRID(ST_MakePolygon(ST_MakeLine(ARRAY[point, point1, point2, point])), ST_SRID(point));
BEGIN
	RETURN ST_Intersection(ST_Buffer(point, depth / 200000), triangle);
	--RETURN ST_Buffer(point, depth);
	--RETURN triangle;
	--RETURN ST_Collect(triangle, ST_Buffer(point, depth));
END
$$body$$
language plpgsql immutable;
endef
function_table_deps = tl_2017_06037_edges
include rules.function.mk

function_name = gisapp_camera_fov_sql
define function_body
-- explain
(point geometry, direction float, depth float, spread float) RETURNS geometry
AS
$$body$$
-- direction is degrees
-- depth is meters
-- spread is degrees
SELECT
	ST_Intersection(ST_Buffer(point, depth / 200000), ST_SetSRID(ST_MakePolygon(ST_MakeLine(ARRAY[point, p4.point1, p4.point2, point])), p1.srid))
FROM
	(
		SELECT
			pi() AS pi,
			2 * depth / 200000 AS double_depth,
			ST_X(point::geometry) AS x,
			ST_Y(point::geometry) AS y,
			ST_SRID(point) AS srid
	) p1,
	LATERAL (
		SELECT
			p1.pi * (direction - spread / 2) / 180 AS left,
			p1.pi * (direction + spread / 2) / 180 AS right
	) p2,
	LATERAL (
		SELECT
			p1.double_depth * sin(p2.left) AS E1,
			p1.double_depth * sin(p2.right) AS E2,
			p1.double_depth * cos(p2.left) AS N1,
			p1.double_depth * cos(p2.right) AS N2
	) p3,
	LATERAL (
		SELECT
			ST_SetSRID(ST_Point(p1.x + p3.E1, p1.y + p3.N1), p1.srid) AS point1,
			ST_SetSRID(ST_Point(p1.x + p3.E2, p1.y + p3.N2), p1.srid) AS point2
	) p4
$$body$$
language sql immutable;
endef
function_table_deps = tl_2017_06037_edges
include rules.function.mk

function_name = gisapp_camera_fov
define function_body
-- explain
(point geometry, direction float, depth float, spread float) RETURNS geometry
AS
$$body$$
SELECT CASE WHEN point IS NULL OR direction IS NULL OR depth IS NULL OR spread IS NULL THEN NULL ELSE gisapp_camera_fov_sql(point, direction, depth, spread) END
$$body$$
language sql immutable;
endef
function_table_deps = gisapp_camera_fov_plpgsql gisapp_camera_fov_sql
include rules.function.mk

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

function_name = gisapp_point_addr
define function_body
-- explain
(point geometry) RETURNS TABLE(
	ogc_fid INTEGER,
	number INTEGER
)
AS
$$body$$
WITH edge_row AS (
	SELECT
		ST_LineLocatePoint(wkb_geometry, $$1) AS point_offset_position,
		*
	FROM
		tl_2017_06037_edges
	WHERE
		ogc_fid = gisapp_nearest_edge($$1)
)
SELECT
	ogc_fid,
	CASE
		WHEN lfromadd IS NOT NULL AND ltoadd IS NOT NULL THEN
			(ltoadd::INTEGER - lfromadd::INTEGER) * (point_offset_position) + lfromadd::INTEGER
		WHEN rfromadd IS NOT NULL AND rtoadd IS NOT NULL THEN
			(rtoadd::INTEGER - rfromadd::INTEGER) * (1 - point_offset_position) + rfromadd::INTEGER
		ELSE
			NULL
	END::INTEGER AS number
FROM
	edge_row
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
	END::float8 AS cost
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
index_table_name = tl_2017_06037_edges_gis_routing
index_schema = CREATE INDEX tl_2017_06037_edges_gis_routing_id ON tl_2017_06037_edges_gis_routing (id)
include rules.index.mk
index_table_name = tl_2017_06037_edges_gis_routing
index_schema = CREATE INDEX tl_2017_06037_edges_gis_routing_source ON tl_2017_06037_edges_gis_routing (source)
include rules.index.mk
index_table_name = tl_2017_06037_edges_gis_routing
index_schema = CREATE INDEX tl_2017_06037_edges_gis_routing_target ON tl_2017_06037_edges_gis_routing (target)
include rules.index.mk

static_table_name = iiif_proc
define static_table_schema
(
	image TEXT UNIQUE,
	iiif_proc_type_id TEXT,
	proc_json JSONB,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	last_modified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY(image, iiif_proc_type_id)
)
endef
static_table_deps = iiif_overrides
include rules.static-table.mk

static_table_name = route_cache
define static_table_schema
(
	start_point geometry(Point, 4326),
	end_point geometry(Point, 4326),
	route geometry(LineString, 4326),
	created_at timestamp not null default current_timestamp,
	last_used_at timestamp not null default current_timestamp,
	PRIMARY KEY(start_point, end_point)
)
endef
static_table_deps = route_build
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

function_name = route_plan
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS TABLE(
	path_seq int,
	node bigint,
	edge bigint
)
AS
$$body$$
WITH
param_start AS (SELECT * FROM route_point_data(start_at)),
param_end AS (SELECT * FROM route_point_data(end_at)),
edge_meta AS (SELECT MAX(id) AS max_id, LEAST(MIN(source), MIN(target)) AS node FROM tl_2017_06037_edges_gis_routing),
raw_plan AS (
	SELECT
		path_seq,
		node,
		edge,
		cost,
		agg_cost
	FROM
	pgr_dijkstra('select * from route_build2_routing(''' || start_at::text || ''', ''' || end_at::text || ''')', (SELECT edge_meta.node - 1 FROM edge_meta), (SELECT edge_meta.node - 2 FROM edge_meta), directed:=false) a
--		pgr_astar('select * from tl_2017_06037_edges_gis_routing', (SELECT from_node FROM param_start), (SELECT from_node FROM param_end), directed:=false) a
)
SELECT
	a.path_seq,
	a.node,
	a.edge
FROM
	raw_plan a
$$body$$
language sql;
endef
function_table_deps = tl_2017_06037_edges_gis_routing route_point_data
include rules.function.mk

function_name = route_edges
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS TABLE(
	path_seq int,
	node bigint,
	edge bigint,
	geom geometry
)
AS
$$body$$
WITH
param_start AS (SELECT * FROM route_point_data(start_at)),
param_end AS (SELECT * FROM route_point_data(end_at)),
edge_meta AS (SELECT MAX(id) AS max_id, LEAST(MIN(source), MIN(target)) AS node FROM tl_2017_06037_edges_gis_routing),
plan AS (
	SELECT * FROM route_plan(start_at, end_at)
),
join_edges AS (
	SELECT
		a.*,
		CASE
			WHEN a.edge = (SELECT edge_meta.max_id + 1 FROM edge_meta) THEN ST_Reverse(ST_LineSubstring(start_edge.wkb_geometry, 0, param_start.percentage))
			WHEN a.edge = (SELECT edge_meta.max_id + 2 FROM edge_meta) THEN ST_LineSubstring(start_edge.wkb_geometry, param_start.percentage, 1)
			WHEN a.edge = (SELECT edge_meta.max_id + 3 FROM edge_meta) THEN ST_LineSubstring(end_edge.wkb_geometry, 0, param_end.percentage)
			WHEN a.edge = (SELECT edge_meta.max_id + 4 FROM edge_meta) THEN ST_Reverse(ST_LineSubstring(end_edge.wkb_geometry, param_end.percentage, 1))
			WHEN a.node = plan_edge.tnidf THEN plan_edge.wkb_geometry
			ELSE ST_Reverse(plan_edge.wkb_geometry)
		END AS geom
	FROM
		plan a LEFT JOIN tl_2017_06037_edges plan_edge ON
			a.edge = plan_edge.ogc_fid
			AND
			a.edge != -1
		, param_start LEFT JOIN tl_2017_06037_edges start_edge ON
			param_start.edge = start_edge.ogc_fid
		, param_end LEFT JOIN tl_2017_06037_edges end_edge ON
			param_end.edge = end_edge.ogc_fid
	WHERE
		param_start.edge != param_end.edge
	UNION
	SELECT
		0 AS path_seq,
		param_start.from_node,
		param_start.edge,
		CASE
			WHEN param_start.percentage < param_end.percentage THEN
				ST_LineSubstring(plan_edge.wkb_geometry, param_start.percentage, param_end.percentage)
			WHEN param_end.percentage < param_start.percentage THEN
				ST_Reverse(ST_LineSubstring(plan_edge.wkb_geometry, param_end.percentage, param_start.percentage))
		END AS geom
	FROM
		param_start JOIN tl_2017_06037_edges plan_edge ON
			param_start.edge = plan_edge.ogc_fid
		, param_end
	WHERE
		param_start.edge = param_end.edge
)
SELECT * FROM join_edges
--SELECT edge_meta.max_id + 1 AS id, param_start.from_node AS source, edge_meta.node - 1 AS target, param_start.cost * percentage AS cost FROM edge_meta, param_start
--SELECT edge_meta.max_id + 2 AS id, edge_meta.node - 1, param_start.to_node AS source, param_start.cost * (1 - percentage) AS cost FROM edge_meta, param_start

--SELECT edge_meta.max_id + 3 AS id, param_end.from_node AS source, edge_meta.node - 2 AS target, param_end.cost * percentage AS cost FROM edge_meta, param_end
--SELECT edge_meta.max_id + 4 AS id, edge_meta.node - 2, param_end.to_node AS source, param_end.cost * (1 - percentage) AS cost FROM edge_meta, param_end
$$body$$
language sql;
endef
function_table_deps = route_plan route_point_data
include rules.function.mk

function_name = route_build2_routing
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS TABLE(
	id integer,
	source bigint,
	target bigint,
	cost float8
)
AS
$$body$$
WITH
param_start AS (SELECT * FROM route_point_data(start_at)),
param_end AS (SELECT * FROM route_point_data(end_at)),
edge_meta AS (SELECT MAX(id) AS max_id, LEAST(MIN(source), MIN(target)) AS node FROM tl_2017_06037_edges_gis_routing)

SELECT edge_meta.max_id + 1 AS id, param_start.from_node AS source, edge_meta.node - 1 AS target, param_start.cost * percentage AS cost FROM edge_meta, param_start
UNION
SELECT edge_meta.max_id + 2 AS id, edge_meta.node - 1, param_start.to_node AS source, param_start.cost * (1 - percentage) AS cost FROM edge_meta, param_start
UNION
SELECT edge_meta.max_id + 3 AS id, param_end.from_node AS source, edge_meta.node - 2 AS target, param_end.cost * percentage AS cost FROM edge_meta, param_end
UNION
SELECT edge_meta.max_id + 4 AS id, edge_meta.node - 2, param_end.to_node AS source, param_end.cost * (1 - percentage) AS cost FROM edge_meta, param_end
UNION
SELECT * FROM tl_2017_06037_edges_gis_routing
$$body$$
language sql;
endef
function_table_deps = route_point_data route_edges
include rules.function.mk

function_name = route_build
define function_body
(start_at geometry(Point, 4326), end_at geometry(Point, 4326)) RETURNS geometry
AS
$$body$$
WITH
param_start AS (SELECT * FROM route_point_data(start_at)),
param_end AS (SELECT * FROM route_point_data(end_at)),
join_geom AS (
	SELECT
		a.geom
	FROM
		route_edges(start_at, end_at) a
	ORDER BY
		a.path_seq
),
build_line AS (
	SELECT
		ST_MakeLine(geom) AS line
	FROM
		join_geom
)
SELECT
	line
FROM
	build_line
$$body$$
language sql;
endef
function_table_deps = route_point_data route_edges
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
		CASE
			WHEN NOT EXISTS (SELECT route FROM route_cache WHERE start_point = start_at AND end_point = end_at) THEN route_build(start_at, end_at)
			ELSE null
		END AS route
	ON CONFLICT(start_point, end_point) DO UPDATE SET last_used_at = current_timestamp
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

static_table_name = iiif_overrides_values
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id),
	value_type_id TEXT,
	name TEXT,
	number_value NUMERIC,
	text_value TEXT,
	timestamp_value TIMESTAMP,
	json_value JSONB,
	geometry_value GEOMETRY,
	PRIMARY KEY(iiif_override_id, name)
)
endef
static_table_deps = iiif_overrides
include rules.static-table.mk

static_table_name = iiif_range_overrides
define static_table_schema
(
	iiif_override_id INTEGER REFERENCES iiif_overrides(iiif_override_id) PRIMARY KEY,

	reverse BOOLEAN,
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

view_table_name = iiif_values
define view_sql
SELECT
  a.iiif_id,
  json_agg(to_json(c.*)) AS values
FROM
  iiif a JOIN iiif_overrides b ON
    a.external_id = b.external_id
  JOIN iiif_overrides_values c ON
    b.iiif_override_id = c.iiif_override_id
GROUP BY
  a.iiif_id
endef
view_table_deps = iiif iiif_overrides iiif_overrides_values
include rules.view.mk

view_table_name = range_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif.external_id,
  iiif_overrides.notes,
  iiif_range_overrides.*
FROM
  iiif LEFT JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  LEFT JOIN iiif_range_overrides ON
    iiif_overrides.iiif_override_id = iiif_range_overrides.iiif_override_id
endef
view_table_deps = iiif iiif_overrides iiif_range_overrides
include rules.view.mk

view_table_name = canvas_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif.external_id,
  iiif_overrides.notes,
  iiif_canvas_overrides.*
FROM
  iiif LEFT JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  LEFT JOIN iiif_canvas_overrides ON
    iiif_overrides.iiif_override_id = iiif_canvas_overrides.iiif_override_id
endef
view_table_deps = iiif iiif_overrides iiif_canvas_overrides
include rules.view.mk

view_table_name = canvas_point_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif.external_id,
  iiif_canvas_point_overrides.*
FROM
  iiif LEFT JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
  LEFT JOIN iiif_canvas_point_overrides ON
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

view_table_name = collection_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif_overrides.external_id,
  iiif_overrides.notes
FROM
  iiif JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
endef
view_table_deps = iiif iiif_overrides
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

view_table_name = manifest_overrides
define view_sql
SELECT
  iiif.iiif_id,
  iiif_overrides.external_id,
  iiif_overrides.notes
FROM
  iiif JOIN iiif_overrides ON
    iiif.external_id = iiif_overrides.external_id
endef
view_table_deps = iiif iiif_overrides
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
  gv.proc_json AS google_vision,
  canvas.*
FROM
  iiif can_base JOIN iiif_canvas canvas ON
    can_base.iiif_id = canvas.iiif_id
  LEFT JOIN iiif_proc gv ON
    canvas.image = gv.image
    AND
    gv.iiif_proc_type_id = 'GOOGLE_VISION'
endef
view_table_deps = iiif iiif_canvas iiif_proc
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
  iiif JOIN iiif_assoc ran_can_assoc ON
    iiif.iiif_id = ran_can_assoc.iiif_id_from
    AND
    iiif.iiif_type_id = 'sc:Range'
  JOIN canvas ON
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

function_name = coalesce_agg_func
define function_body
(state anyelement, value anyelement) RETURNS anyelement AS $$body$$ SELECT coalesce(value, state) $$body$$ LANGUAGE SQL;
endef
include rules.function.mk

aggregate_name = coalesce_agg
aggregate_signature = (anyelement)
aggregate_body = (SFUNC = coalesce_agg_func, STYPE = anyelement)
aggregate_table_deps = coalesce_agg_func
include rules.aggregate.mk

view_table_name = routing_canvas_range_grouping
define view_sql
SELECT
	range_canvas.range_id,
	range_canvas.iiif_id,
	range_canvas.sequence_num,
	point,
	exclude,
	case when exclude is true then -1 else count(point) OVER reverse end AS reverse,
	case when exclude is true then null else coalesce_agg(point) OVER reverse end AS end_point,
	case when exclude is true then null else coalesce_agg(point) OVER forward end AS start_point
FROM
	range_canvas LEFT JOIN canvas_point_overrides ON
		range_canvas.iiif_id = canvas_point_overrides.iiif_id
	LEFT JOIN canvas_overrides ON
		range_canvas.iiif_id = canvas_overrides.iiif_id
WINDOW
	reverse AS (PARTITION BY range_canvas.range_id, exclude IS NULL OR exclude = false ORDER BY sequence_num DESC),
	forward AS (PARTITION BY range_canvas.range_id, exclude IS NULL OR exclude = false ORDER BY sequence_num)
endef
view_table_deps = range_canvas canvas_point_overrides canvas_overrides coalesce_agg
include rules.view.mk

static_table_name = routing_canvas_range_interpolation_cache
define static_table_schema
AS SELECT *, FALSE AS needs_refresh FROM routing_canvas_range_interpolation
endef
static_table_deps = routing_canvas_range_interpolation
include rules.static-table.mk
index_table_name = routing_canvas_range_interpolation_cache
index_schema = CREATE INDEX routing_canvas_range_interpolation_cache_range_id ON routing_canvas_range_interpolation_cache (range_id)
include rules.index.mk
index_table_name = routing_canvas_range_interpolation_cache
index_schema = CREATE INDEX routing_canvas_range_interpolation_cache_iiif_id ON routing_canvas_range_interpolation_cache (iiif_id)
include rules.index.mk
index_table_name = routing_canvas_range_interpolation_cache
index_schema = CREATE INDEX routing_canvas_range_interpolation_cache_needs_refresh ON routing_canvas_range_interpolation_cache (needs_refresh)
include rules.index.mk
index_table_name = routing_canvas_range_interpolation_cache
index_schema = CREATE INDEX routing_canvas_range_interpolation_cache_point ON routing_canvas_range_interpolation_cache USING gist(point)
include rules.index.mk
index_table_name = routing_canvas_range_interpolation_cache
index_schema = ALTER TABLE routing_canvas_range_interpolation_cache ADD PRIMARY KEY (range_id, iiif_id)
include rules.index.mk

trigger_name = rcri_update_needs_refresh_trigger
trigger_constraint = yes
trigger_table = routing_canvas_range_interpolation_cache
trigger_events = AFTER UPDATE
define trigger_body
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (
	(NEW.needs_refresh AND rcri_check_needs_trigger())
) EXECUTE PROCEDURE rcri_process_refresh_request_trigger()
endef
trigger_table_deps = routing_canvas_range_interpolation_cache rcri_check_needs_trigger rcri_process_refresh_request_trigger
include rules.trigger.mk

function_name = rcri_check_needs_trigger
define function_body
() RETURNS boolean
AS
$$body$$
DECLARE
	refresh_count INTEGER;
BEGIN
	SELECT COUNT(*) INTO refresh_count FROM routing_canvas_range_interpolation_cache WHERE needs_refresh;
	RETURN refresh_count = 1;
END
$$body$$
LANGUAGE plpgsql
endef
function_table_deps = routing_canvas_range_interpolation_cache
include rules.function.mk

static_table_name = rcri_range_summary_cache
define static_table_schema
AS SELECT * FROM rcri_range_summary
endef
static_table_deps = rcri_range_summary
include rules.static-table.mk
index_table_name = rcri_range_summary_cache
index_schema = CREATE UNIQUE INDEX rcri_range_summary_cache_pk ON rcri_range_summary_cache (range_id)
include rules.index.mk
index_table_name = rcri_range_summary_cache
index_schema = CREATE INDEX rcri_range_summary_name ON rcri_range_summary_cache (name)
include rules.index.mk

view_table_name = rcri_range_summary
define view_sql
SELECT
	range_id,
	'global_bounds'::text AS name,
	NULL::numeric AS number,
	NULL::text AS text,
	ST_Extent(point)::geometry AS geometry
FROM
	routing_canvas_range_interpolation_cache
GROUP BY
	range_id
endef
view_table_deps = routing_canvas_range_interpolation_cache
include rules.view.mk

function_name = rcri_process_refresh_request_trigger
define function_body
() RETURNS trigger
AS
$$body$$
DECLARE
	ids INTEGER[];
BEGIN
	SELECT ARRAY_AGG(range_id) INTO ids FROM (SELECT DISTINCT range_id FROM routing_canvas_range_interpolation_cache WHERE needs_refresh) a;
	EXECUTE rcri_update_ranges(ids);
	RETURN NULL;
END
$$body$$
LANGUAGE plpgsql
endef
function_table_deps = routing_canvas_range_interpolation_cache rcri_update_ranges
include rules.function.mk

function_name = rcri_update_ranges
define function_body
(ids INTEGER[]) RETURNS void
AS
$$body$$
BEGIN
	RAISE NOTICE 'Updating ranges %', ids;
	DELETE FROM routing_canvas_range_interpolation_cache WHERE range_id = ANY(ids);
	DELETE FROM rcri_range_summary_cache WHERE range_id = ANY(ids);
	DELETE FROM rcri_buildings WHERE range_id = ANY(ids);
	INSERT INTO
		routing_canvas_range_interpolation_cache
	SELECT *, FALSE AS needs_refresh FROM routing_canvas_range_interpolation WHERE range_id = ANY(ids);
	INSERT INTO rcri_range_summary_cache SELECT * FROM rcri_range_summary WHERE range_id = ANY(ids);
	INSERT INTO
		rcri_buildings
	SELECT
		a.range_id,
		a.iiif_id,
		b.ogc_fid AS building_id
	FROM
		routing_canvas_range_interpolation_cache a JOIN lariac_buildings b ON
			ST_Intersects(a.camera, b.wkb_geometry)
	WHERE
		a.range_id = ANY(ids)
	;
END
$$body$$
LANGUAGE plpgsql
endef
function_table_deps = routing_canvas_range_interpolation_cache routing_canvas_range_interpolation rcri_range_summary_cache rcri_range_summary rcri_buildings lariac_buildings
include rules.function.mk


trigger_name = rcri_range_override_insert_trigger
trigger_table = iiif_range_overrides
trigger_events = AFTER INSERT
define trigger_body
FOR EACH ROW WHEN (
	COALESCE(NEW.fov_angle, 60) != 60
	OR
	COALESCE(NEW.fov_depth, 100) != 100
	OR
	COALESCE(NEW.fov_orientation, 'left') != 'left'
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_range_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_range_override_update_trigger
trigger_table = iiif_range_overrides
trigger_events = AFTER UPDATE
define trigger_body
FOR EACH ROW WHEN (
	COALESCE(OLD.fov_angle, 60) != COALESCE(NEW.fov_angle, 60)
	OR
	COALESCE(OLD.fov_depth, 100) != COALESCE(NEW.fov_depth, 100)
	OR
	COALESCE(OLD.fov_orientation, 'left') != COALESCE(NEW.fov_orientation, 'left')
)
EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_range_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_range_override_delete_trigger
trigger_table = iiif_range_overrides
trigger_events = AFTER DELETE
define trigger_body
FOR EACH ROW EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_range_overrides rcri_override_trigger
include rules.trigger.mk

function_name = rcri_override_trigger
define function_body
() RETURNS trigger
AS
$$body$$
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		PERFORM rcri_update_override(NEW.iiif_override_id);
		RETURN NEW;
	END IF;
	IF (TG_OP = 'DELETE') THEN
		PERFORM rcri_update_override(OLD.iiif_override_id);
		RETURN OLD;
	END IF;
	RETURN NEW;
END
$$body$$
LANGUAGE plpgsql;
endef
function_table_deps = rcri_update_override
include rules.function.mk

trigger_name = rcri_canvas_override_insert_trigger
trigger_table = iiif_canvas_overrides
trigger_events = AFTER INSERT
define trigger_body
FOR EACH ROW WHEN (
	COALESCE(NEW.exclude, FALSE) != FALSE -- insert of an exclude
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_canvas_override_update_trigger
trigger_table = iiif_canvas_overrides
trigger_events = AFTER UPDATE
define trigger_body
FOR EACH ROW WHEN (
	COALESCE(OLD.exclude, FALSE) != COALESCE(NEW.exclude, FALSE)
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_canvas_override_delete_trigger
trigger_table = iiif_canvas_overrides
trigger_events = AFTER DELETE
define trigger_body
FOR EACH ROW WHEN (
	COALESCE(OLD.exclude, FALSE) != FALSE
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_canvas_point_override_insert_trigger
trigger_table = iiif_canvas_point_overrides
trigger_events = AFTER INSERT
define trigger_body
FOR EACH ROW WHEN (
	NEW.point IS NOT NULL
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_canvas_point_override_update_trigger
trigger_table = iiif_canvas_point_overrides
trigger_events = AFTER UPDATE
define trigger_body
FOR EACH ROW WHEN (
	(OLD.priority IS NULL AND NEW.priority IS NOT NULL)
	OR
	(OLD.priority IS NOT NULL AND NEW.priority IS NULL)
	OR
	(OLD.priority != NEW.priority)
	OR
	(OLD.point IS NULL AND NEW.point IS NOT NULL)
	OR
	(OLD.point IS NOT NULL AND NEW.point IS NULL)
	OR
	(NOT ST_Equals(OLD.point, NEW.point))
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

trigger_name = rcri_canvas_point_override_delete_trigger
trigger_table = iiif_canvas_point_overrides
trigger_events = AFTER DELETE
define trigger_body
FOR EACH ROW WHEN (
	OLD.point IS NOT NULL
) EXECUTE PROCEDURE rcri_override_trigger()
endef
trigger_table_deps = iiif_canvas_overrides rcri_override_trigger
include rules.trigger.mk

function_name = rcri_update_schedule
define function_body
(iiif_id_p integer) RETURNS void
AS
$$body$$
UPDATE routing_canvas_range_interpolation_cache
SET needs_refresh = TRUE
WHERE
	iiif_id_p IS NOT NULL
	AND
	(
		iiif_id_p = range_id
		OR
		iiif_id_p = iiif_id
	)
$$body$$
LANGUAGE SQL;
endef
function_table_deps = routing_canvas_range_interpolation_cache
include rules.function.mk

function_name = rcri_update_override
define function_body
-- explain
(iiif_override_id_p integer) RETURNS void
AS
$$body$$
SELECT
	CASE
		WHEN b.iiif_type_id = 'sc:Canvas' THEN rcri_update_schedule(b.iiif_id)
		WHEN b.iiif_type_id = 'sc:Range' THEN rcri_update_schedule(b.iiif_id)
	END AS ignore
FROM
	iiif_overrides a JOIN iiif b ON
		a.external_id = b.external_id
WHERE
	a.iiif_override_id = iiif_override_id_p
$$body$$
LANGUAGE SQL;
endef
function_table_deps = rcri_update_schedule iiif_overrides iiif
include rules.function.mk

view_table_name = routing_canvas_range_interpolation
define view_sql
WITH range_fov AS (
	SELECT
		iiif_id,
		COALESCE(reverse, false) AS reverse,
		COALESCE(fov_depth, 100) AS depth,
		COALESCE(fov_angle, 60) AS angle,
		COALESCE(fov_orientation, 'left') AS orientation
	FROM
		range_overrides
)
SELECT
	a.*,
	CASE
		WHEN a.point IS NULL OR a.bearing IS NULL THEN null
		ELSE gisapp_camera_fov(a.point, degrees(a.bearing) + CASE WHEN b.orientation = 'left' THEN -90 ELSE 90 END, b.depth, b.angle)
	END AS camera
FROM
	(
		SELECT
			a.range_id,
			a.iiif_id,
			a.sequence_num,
			a.route_point AS point,
			CASE
				WHEN route_point IS NULL THEN
					null
				WHEN (row_number() OVER points_forward_order) = (count(*) OVER points_forward) THEN
					ST_Azimuth(lag(route_point, 1) OVER points, route_point)
				WHEN (row_number() OVER points_forward_order) = 1 THEN
					ST_Azimuth(route_point, lead(route_point, 1) OVER points)
				ELSE
					ST_Azimuth(lag(route_point, 1) OVER points, route_point)
			END AS bearing
		FROM
			(
				SELECT
					*,
					CASE
						WHEN point IS NOT NULL THEN point
						WHEN start_point IS NOT NULL AND end_point IS NOT NULL AND start_point::text != end_point::text THEN ST_LineInterpolatePoint(plan_route(start_point, end_point), cume_dist() OVER ranking)
						ELSE null
					END AS route_point
				FROM
					routing_canvas_range_grouping
				WINDOW
					ranking AS (PARTITION BY range_id, reverse ORDER BY sequence_num)
			) a
		WINDOW
			points AS (PARTITION BY range_id, a.route_point IS NOT NULL ORDER BY sequence_num),
			points_forward AS (PARTITION BY range_id, a.start_point, a.route_point IS NOT NULL),
			points_forward_order AS (PARTITION BY range_id, a.start_point, a.route_point IS NOT NULL ORDER BY sequence_num)
	) a LEFT JOIN range_fov b ON
		a.range_id = b.iiif_id
ORDER BY
	a.sequence_num

endef

view_table_deps = routing_canvas_range_grouping plan_route range_overrides gisapp_camera_fov
include rules.view.mk

static_table_name = rcri_buildings
define static_table_schema
AS
SELECT
	a.range_id,
	a.iiif_id,
	b.ogc_fid AS building_id
FROM
	routing_canvas_range_interpolation_cache a JOIN lariac_buildings b ON ST_Intersects(a.camera, b.wkb_geometry)
endef
static_table_deps = routing_canvas_range_interpolation_cache lariac_buildings
include rules.static-table.mk
index_table_name = rcri_buildings
index_schema = CREATE INDEX rcri_buildings_range_id ON rcri_buildings (range_id)
include rules.index.mk
index_table_name = rcri_buildings
index_schema = CREATE INDEX rcri_buildings_building_id ON rcri_buildings (building_id)
include rules.index.mk

view_table_name = routing_canvas_range_camera
define view_sql
SELECT
	addredge.fullname AS addr_fullname,
	COALESCE(addredge.zipl, addredge.zipr) AS addr_zipcode,
	addr.number AS addr_number,
	a.*
FROM
	routing_canvas_range_interpolation_cache a LEFT JOIN LATERAL (SELECT * FROM gisapp_point_addr(a.point)) addr ON
		TRUE
	LEFT JOIN tl_2017_06037_edges addredge ON
		addr.ogc_fid = addredge.ogc_fid
endef
view_table_deps = routing_canvas_range_interpolation_cache gisapp_camera_fov range_overrides gisapp_point_addr
include rules.view.mk

PHONY: tableimport configure-geoserver import-tables dump-tables iiif-import

iiif_json_files := $(shell find data/media.getty.edu/ -name 'collection.json' -or -name 'manifest.json')
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
