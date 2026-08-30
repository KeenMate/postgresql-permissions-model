# Examples

Annotated, **aspect-by-aspect** demonstrations of the permissions model. These
are meant to be *read and explored*, not run blindly: each file walks a topic as
a series of standalone SQL statements, each preceded by a comment explaining the
capability it showcases and (where useful) the result to expect.

Design of these scripts:

- **Plain SQL, no psql magic.** No `\set` / `\gset` / `\echo` and no `:'var'`
  interpolation — every statement is self-contained (IDs are looked up inline via
  sub-selects on stable emails/codes). So you can highlight one statement and run
  it on its own in **any** client: psql, DataGrip, DBeaver, pgAdmin, …
- **Data persists.** There is no `rollback`; the demo rows stay so you can query
  and tinker with them afterwards. Run [`cleanup.sql`](cleanup.sql) to remove all
  demo data — do this before re-running a file, since the `create_*` calls are
  not idempotent.
- **Acts as the seeded system user** (`user_id = 1`, tenant 1), which holds all
  permissions, so the permission-checked `auth.*` / `public.*` API can be called
  directly.
- **Demo data is Twin Peaks characters on `@twinpeaks.com`** — that domain is the
  key `cleanup.sql` uses to find and delete the demo users.

## Running

Run a whole file, or copy individual statements into your client:

```bash
./debee.ps1 -Operations execSql -SqlFile examples/01-user-provisioning.sql   # PowerShell
./debee.sh  -o execSql --sql-file examples/01-user-provisioning.sql          # Bash
python debee.py -o execSql --sql-file examples/01-user-provisioning.sql       # Python
psql "$CONN" -f examples/01-user-provisioning.sql                             # psql directly

# reset when done / before re-running
./debee.sh -o execSql --sql-file examples/cleanup.sql
```

## Topic files

| File | Aspects showcased |
|------|-------------------|
| `01-user-provisioning.sql`    | Full user lifecycle: provision from a provider (+ idempotency) & local signup; authenticate via SSO (`ensure_user_from_provider`) and via email+password (`verify_user_by_email`); password management (`update_user_password`); how lock / disable gate login |
| `02-user-status.sql`          | Status operations in isolation: enable / disable / lock / unlock an account vs. disable / enable a single provider identity |
| `03-tenants-and-owners.sql`   | Creating a tenant, assigning owners, cross-tenant reads of users / groups / members from the admin tenant |
| `04-groups-and-mappings.sql`  | Internal vs. external vs. hybrid groups; direct members; mapping external provider groups/roles |
| `05-permissions-and-sets.sql` | Hierarchical permissions, permission sets, direct vs. group-inherited vs. external-group access, `ensure_groups_and_permissions` + cache |
| `06-tokens-and-events.sql`    | Audit events and single-use tokens (`create_user_event`, `create_token`, `validate_token`) |
| `07-api-keys.sql`             | API keys as technical users, granting them permissions, plain service users |
| `cleanup.sql`                 | Removes every demo artifact created by the files above |

## Resource-level ACL examples (path / role based)

Larger, self-contained demos of the **resource access** subsystem (per-object
grants on an `ltree` hierarchy). They manage their own schema/data and clean up
after themselves.

| File | Covers |
|------|--------|
| `resource-acl-icons.sql`         | Path-based ACL at scale: ~27k filesystem paths, direct-flag / group / role / deny grants, latency + bulk-filter probes. Requires `resource-acl-icons-data.sql` (regenerate with `python gen_icons_inserts.py`). |
| `resource-roles-organiogram.sql` | Resource roles on a 30-node org tree: `org_reader` / `org_writer`, custom `assign_manager` flag, deny rules, effective-flag queries. (This one *does* wrap in a transaction and roll back.) |
