#!/bin/sh
# Fills a golden with production's shape when there is no production to copy,
# which is the case on a CI runner: 25,000 customers and 6,000,000 orders, the
# same counts as the production database the local manifest reads from.
#
# It applies V1 only and records it, never the branch's own migrations. A
# golden is what production looks like before this change, so a pull request's
# pending migrations must still be pending when the rehearsal branches it.
set -eu
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f migrations/V1__init.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS flyway_schema_history (
    installed_rank serial PRIMARY KEY,
    version        text        NOT NULL,
    description    text        NOT NULL,
    script         text        NOT NULL,
    installed_on   timestamptz NOT NULL DEFAULT now(),
    success        boolean     NOT NULL
);
INSERT INTO flyway_schema_history (version, description, script, success)
SELECT '1', 'init', 'V1__init.sql', true
WHERE NOT EXISTS (SELECT 1 FROM flyway_schema_history WHERE version = '1');
TRUNCATE orders, customers RESTART IDENTITY;
INSERT INTO customers (name, email, phone, created_at)
SELECT 'Customer ' || g,
       'customer' || g || '@example.com',
       '+1 ' || (200 + g % 700) || ' 555 ' || lpad((g % 10000)::text, 4, '0'),
       now() - (g % 1400) * interval '1 day'
FROM generate_series(1, 25000) g;
INSERT INTO orders (customer_id, total_cents, placed_at)
SELECT 1 + (hashint4(g) & 2147483647) % 25000,
       500 + (hashint4(g + 7) & 2147483647) % 49500,
       now() - ((hashint4(g + 11) & 2147483647) % (1400 * 1440)) * interval '1 minute'
FROM generate_series(1, 6000000) g;
ANALYZE customers;
ANALYZE orders;
SQL
