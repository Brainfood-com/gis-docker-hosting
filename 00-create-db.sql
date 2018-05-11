CREATE DATABASE gis;

REVOKE ALL PRIVILEGES ON DATABASE gis FROM public;

CREATE USER gis WITH PASSWORD 'sig';
GRANT ALL PRIVILEGES ON DATABASE gis TO gis;

\c gis
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
CREATE EXTENSION pg_trgm;
CREATE EXTENSION postgis_sfcgal;

