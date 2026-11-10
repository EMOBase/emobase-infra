-- Created only on the first start of the MySQL data volume.
--
-- Portal and Keycloak databases. Per-species Directus databases are created
-- later with scripts/create-database.sh (one database per species deployment).
CREATE DATABASE IF NOT EXISTS emobase_genomics;
CREATE DATABASE IF NOT EXISTS keycloak;
CREATE DATABASE IF NOT EXISTS directus;
