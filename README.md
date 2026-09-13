# Orders, an Antifailure demo

This repository exists to run the Antifailure GitHub Action on a real pull
request. [Pull request #1](https://github.com/VirSanghavi/antifailure-demo-orders/pull/1)
widens `orders.total_cents` from `integer` to `bigint` in one statement, and the
check on it fails with the finding that matters: rehearsed against six million
orders, the migration held `AccessExclusiveLock` on `orders` for at least 10.5
seconds. The report is the comment on that pull request, and the run that
produced it is
[34741273951](https://github.com/VirSanghavi/antifailure-demo-orders/actions/runs/34741273951).

The repository is archived, so it is read only.

The application is a copy of
[`examples/next-app`](https://github.com/antifailure/antifailure/tree/main/examples/next-app)
from the Antifailure repository, changed in four ways so that a hosted runner
can check it with no production database and no secrets:

- `seed.sh` fills the golden with production's shape, 25,000 customers and
  6,000,000 orders, because a runner has no production to copy
- migrations follow the Flyway layout, applied by `migrate.sh`, so a pull
  request's pending migration is still pending when the rehearsal branches the
  golden
- `masking.yaml` rewrites only the three columns that hold a person
- `.github/workflows/antifailure.yml` calls the reusable check with no control
  plane, so the run comments on the pull request itself

It is a Next.js application against the same schema as
[`examples/go-api`](https://github.com/antifailure/antifailure/tree/main/examples/go-api),
and deliberately a different shape. That one is a compiled binary with three
endpoints. This one has a framework, a build step, and server rendered pages,
which brings the two problems those always bring:

- the build must not need a database, because it runs inside the image where
  there is not one yet
- the runtime must, and must say so before it is called ready

One page and one route, because that is enough to have both problems:

    GET  /              the customers and what each has spent, rendered per request
    GET  /api/health    answers only once the database answers

## Run it

From a clone, with Docker running:

```sh
af up
```

That seeds a golden, masks it, branches a Postgres database from it, runs the
migrations against the branch, seals the network, and starts the service. The
first run spends several minutes generating six million orders; later runs
reuse the golden.

```sh
open "$(af status -o json | jq -r .url)"
af down
```

## What to look at, and why

**The build does not touch the database, and that is arranged rather than
lucky.** Two lines do it. `app/page.tsx` sets `export const dynamic =
"force-dynamic"`, so Next renders it per request instead of trying to prerender
it during `next build`. `lib/db.ts` creates the pool on first use rather than
at import time, so importing the module during the build does not open a
connection. Without either one the image fails to build, with a connection
error that reads like a configuration problem and is not one.

**The health path is the readiness contract.** `/api/health` runs `SELECT 1`
and returns 503 until that works. The manifest names it, and the engine waits
for it, so `ready` means the page will render rather than that a process is
listening. A service whose health check only proves a port is open reports
ready and then serves a stack trace.

**Standalone output needs its static files copied separately.** `next.config.ts`
sets `output: "standalone"`, which produces a server and a pruned
`node_modules`. The static assets are not in it. The Dockerfile copies
`.next/static` in a second `COPY`, and leaving that step out is the classic
mistake: the page renders, arrives with no CSS, and looks like a styling bug.

**`HOSTNAME` is set to `0.0.0.0` on purpose.** The standalone server binds to
whatever `HOSTNAME` says. Left unset it has bound to localhost in some
versions, which inside a container means the port is open and nothing outside
can reach it. The symptom is a service that starts cleanly and never becomes
ready.

**The join survives masking because the keys are not masked.** `masking.yaml`
rewrites `customers.email`, `customers.name` and `customers.phone`, and nothing
else. `customers.id` and `orders.customer_id` are row numbers the database
assigned, not facts about a person, so both are copied unchanged and every
order still belongs to the same customer. The upstream example remaps the keys
instead and links them so they stay equal; either way, a join that masking
breaks renders every customer with zero orders, which is not an error and not
an empty page, just quietly wrong numbers.

**The egress default is `block` and there are no rules.** This application
calls nothing, and the policy says so rather than leaving a door open in case
it one day does. For a rule that is actually used, read
[`examples/go-api`](https://github.com/antifailure/antifailure/tree/main/examples/go-api),
which takes a payment through `api.stripe.com` answered by the pack that ships
with the engine.

## License

MIT, the same as the Antifailure repository it was copied from. See `LICENSE`.
