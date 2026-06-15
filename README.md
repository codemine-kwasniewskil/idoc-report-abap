# /COD1/ IDoc Monitor — ABAP OO report + dashboard

In-ERP monitor for errored IDocs, in the **`/COD1/`** namespace, packaged for **abapGit** import.
The native ABAP OO counterpart of the BTP IDoc-monitoring app: it groups errored IDocs into
**signatures**, maps signatures to **configurable actions** (`/COD1/IDOC_ACFG`, SM30), and runs them
**single or throttled-bulk** with an **approval + audit** trail, on an interactive **SALV** dashboard
(`/COD1/IDOC_MONITOR`).

> This repo contains **only the monitor objects**. It reuses the IDoc **service** package
> (`/COD1/CL_IDOC_SERVICE` etc.) for every read/action — that package must already be imported and
> active on the target system (repo: `idoc_monitor`). No control logic is duplicated here.

---

## ⚠️ Prerequisites on the target SAP system

1. **Namespace `/COD1/` registered** (SE03) with a valid namespace/repair license — one-time Basis.
2. **The `/COD1/` service package is imported & active** (`/COD1/CL_IDOC_SERVICE`,
   `/COD1/IF_IDOC_TYPES`, `/COD1/CX_IDOC_ERROR`, …). The monitor compiles against it.
3. **abapGit installed**; a package in the namespace, e.g. `/COD1/IDOC_MON`.

## Import (abapGit, online)

1. `SE80`/`SE21` → create package `/COD1/IDOC_MON`.
2. abapGit → **New Online** → URL `https://github.com/codemine-kwasniewskil/idoc-report-abap.git`,
   package `/COD1/IDOC_MON`, branch `main` → **Pull**.
3. **Activate in order: the 5 tables first → interfaces → classes → report.**
4. **Generate SM30** for `/COD1/IDOC_ACFG` (SE11 → Utilities → Table Maintenance Generator) so the
   action config is maintainable.

## What's in `src/`

| Kind | Objects |
|---|---|
| Tables | `/COD1/IDOC_SIG`, `_ACFG`, `_APRV`, `_AUD`, `_BJOB` |
| Interfaces | `/COD1/IF_IDOC_MON_TYPES`, `_REPOSITORY` |
| Classes | `/COD1/CL_IDOC_MON_FACADE`, `_FACTORY`, `_REPOSITORY`, `_SIGNATURE`, `_CONFIG`, `_ACTIONCFG`, `_BULK`, `_APPROVAL`, `_AUDIT`, `_DASHBOARD` |
| Report | `/COD1/IDOC_MONITOR` |

Patterns: Facade, Factory, Repository, Strategy/Value-Object, Registry, Template Method, State,
MVC/Observer. Filenames use abapGit's namespace encoding (`/COD1/` → `#cod1#`).

## Run

- `/COD1/IDOC_MONITOR` with **`P_REFR`** ticked → rebuild the materialized signatures (schedule as a
  background job for a live picture).
- `/COD1/IDOC_MONITOR` (no flags) → the dashboard: KPIs + signatures → drill to instances → status
  history; toolbar **Run action** (single) / **Bulk run** (throttled).

Full setup + verification: see `IDOC-MONITOR-GUIDE.md`.

## Invariants (from the BTP app)
Throttle bulk (mass actions only via the packaged, rate-paced runner), idempotent per-item
status-guard, append-only audit (`/COD1/IDOC_AUD` is never deleted), no generic action.
