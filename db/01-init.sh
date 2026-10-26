#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname n8n <<-SQL
  CREATE ROLE persona_app LOGIN PASSWORD '${PERSONA_DB_PASSWORD}';
  CREATE DATABASE persona OWNER "$POSTGRES_USER";
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname persona -f /docker-entrypoint-initdb.d/schema/02-schema.sql
