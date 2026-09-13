#!/bin/sh
# Applies every Flyway style migration the database has not recorded, in
# version order, and records each one. This is what the deploy runs too.
set -eu
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS flyway_schema_history (
    installed_rank serial PRIMARY KEY,
    version        text        NOT NULL,
    description    text        NOT NULL,
    script         text        NOT NULL,
    installed_on   timestamptz NOT NULL DEFAULT now(),
    success        boolean     NOT NULL
);
SQL
for f in $(ls migrations/V*__*.sql | sort -t V -k 2 -n); do
    name=$(basename "$f" .sql)
    version=${name#V}; version=${version%%__*}
    applied=$(psql "$DATABASE_URL" -tAc "SELECT 1 FROM flyway_schema_history WHERE version = '$version' AND success")
    if [ -z "$applied" ]; then
        echo "applying $name"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$f"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "INSERT INTO flyway_schema_history (version, description, script, success) VALUES ('$version', '${name#*__}', '$name.sql', true)"
    fi
done
