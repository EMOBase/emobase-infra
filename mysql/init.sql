-- Created only on the first start of the MySQL data volume.
--
-- Keycloak needs its own database. Portal and species databases are created
-- by their own setup steps with scripts/create-database.sh.
CREATE DATABASE IF NOT EXISTS keycloak;
