// The suite CI runs: migrate a fresh test database, then check the page query.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import pg from "pg";

const url = process.env.TEST_DATABASE_URL;

test("migrations apply to a fresh database", () => {
  execFileSync("sh", ["migrate.sh"], { env: { ...process.env, DATABASE_URL: url } });
});

test("orders page lists customers with what each spent", async () => {
  const db = new pg.Client({ connectionString: url });
  await db.connect();
  const { rows } = await db.query(`
    SELECT c.name, COUNT(o.id)::int AS orders, COALESCE(SUM(o.total_cents), 0)::int AS spent_cents
    FROM customers c LEFT JOIN orders o ON o.customer_id = c.id
    GROUP BY c.id, c.name ORDER BY c.id LIMIT 100`);
  await db.end();
  assert.equal(rows.length, 4);
  assert.equal(rows[0].spent_cents, 17499);
});

test("an order total must be positive", async () => {
  const db = new pg.Client({ connectionString: url });
  await db.connect();
  await assert.rejects(db.query("INSERT INTO orders (customer_id, total_cents) VALUES (1, 0)"));
  await db.end();
});
