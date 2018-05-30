CREATE DATABASE gis;
REVOKE ALL PRIVILEGES ON DATABASE gis FROM public;

CREATE USER gis WITH PASSWORD 'sig';
GRANT ALL PRIVILEGES ON DATABASE gis TO gis;

\c gis
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
CREATE EXTENSION postgis_sfcgal;
CREATE EXTENSION postgres_fdw;
CREATE EXTENSION pg_trgm;
CREATE EXTENSION btree_gis;
CREATE EXTENSION btree_gin;
CREATE SERVER perm_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'perm-postgresql', port '5432', dbname 'perm');
GRANT USAGE ON FOREIGN SERVER perm_server TO gis;

\c gis gis
CREATE SCHEMA perm;
CREATE USER MAPPING FOR gis SERVER perm_server OPTIONS (user 'perm', password 'mrep');
--IMPORT FOREIGN SCHEMA public LIMIT TO (actors, directors) FROM SERVER film_server INTO films;


