# In-ERP IDoc Monitor — `/COD1/IDOC_MONITOR`

The ABAP OO counterpart of the BTP service + Fiori dashboard, running **natively inside the ERP**.
It groups errored IDocs into **signatures**, maps signatures to **configurable actions**, and runs
them **single or throttled-bulk** with an **approval + audit** trail — all on an interactive **SALV**
dashboard. Every read and action reuses the existing `/COD1/CL_IDOC_SERVICE` (no duplicated logic).

Because it runs *on* the ERP, there's no sync/staging/high-water-mark (EDIDC/EDIDS is the database);
the BTP "delta sync" becomes a periodic **refresh** job that materializes the signature aggregate.

---

## Objects (abapGit, namespace `/COD1/`)

| Kind | Objects |
|---|---|
| Tables | `/COD1/IDOC_SIG` (signature aggregate), `/COD1/IDOC_ACFG` (action config, SM30), `/COD1/IDOC_APRV` (approvals), `/COD1/IDOC_AUD` (audit, append-only), `/COD1/IDOC_BJOB` (bulk jobs) |
| Interfaces | `/COD1/IF_IDOC_MON_TYPES`, `/COD1/IF_IDOC_MON_REPOSITORY` |
| Classes | `/COD1/CL_IDOC_MON_` `FACADE` · `FACTORY` · `REPOSITORY` · `SIGNATURE` · `CONFIG` · `ACTIONCFG` · `BULK` · `APPROVAL` · `AUDIT` · `DASHBOARD` |
| Report | `/COD1/IDOC_MONITOR` |

Patterns: **Facade** (`_FACADE`), **Factory** (`_FACTORY`), **Repository** (`_REPOSITORY`),
**Strategy/Value-Object** (`_SIGNATURE`), **Registry** (`_ACTIONCFG`), **Template Method** (`_BULK`),
**State** (`_APPROVAL`), **MVC/Observer** (`_DASHBOARD`). Actions run only through the existing
**Command**s (REPROCESS / SET_STATUS / CLOSE / TRIGGER) via the service.

## Prerequisites

1. The `/COD1/` **service package is imported and active** (`/COD1/CL_IDOC_SERVICE` etc.).
2. After abapGit pull, **activate the 5 tables first**, then the interfaces, then the classes/report.
3. **Generate the SM30 dialog** for `/COD1/IDOC_ACFG` (SE11 → table → Utilities → Table Maintenance
   Generator: authorization group `&NC&`, function group e.g. `/COD1/IDOC_ACFG`, maintenance type
   1-step) so the action config is maintainable in **SM30**.

## Setup & run

### 1. Build the signatures (the "sync" equivalent)
`/COD1/IDOC_MONITOR` → tick **`P_REFR`** → execute. Reads errored IDocs (EDIDC status in the error
set, joined to the matching EDIDS status record), aggregates by
`direction|mestyp|status|stamid|stamno`, and fills `/COD1/IDOC_SIG`. New signatures get
`CONFIG_STATE = NEEDS_CONFIG`. **Schedule it as a periodic background job** (SM36) for a live picture.

### 2. Configure actions (SM30 on `/COD1/IDOC_ACFG`)
Map a signature to one or more actions. Get the `SIG_KEY` from `/COD1/IDOC_SIG` (SE16). Example rows:

| ACTION_ID | SIG_KEY | LABEL | SEQNR | TYPE | TARGET | PARAMS | BULKABLE | REQ_APPROVAL | RATE_PER_MIN |
|---|---|---|---|---|---|---|---|---|---|
| `DELINS_CLOSE` | `<sig>` | Close (set 68) | 10 | `erp_action` | `SET_STATUS` | `status=68;message=Closed by monitor` | `X` | ` ` | 120 |
| `DELINS_REPROC` | `<sig>` | Reprocess | 20 | `erp_action` | `REPROCESS` | | `X` | `X` | 60 |

`TARGET` is the command key (`REPROCESS` / `SET_STATUS` / `CLOSE` / `TRIGGER`); `PARAMS` is
`k=v;k=v` (`status`, `message`, `mestyp`, `rcvprn`, `rcvprt`). `REQ_APPROVAL = X` routes the action
through an approval request before it runs.

### 3. Dashboard
`/COD1/IDOC_MONITOR` (no flags) → the signatures SALV with a KPI header (errored totals IN/OUT).
- **double-click a signature** → its errored IDocs (capped at 5000, see `/COD1/CL_IDOC_MON_CONFIG`).
- **double-click an instance** → status history.
- select instance(s) + **Run action** → single execution of the signature's primary action.
- **Bulk run** → throttled run over the whole signature (foreground if ≤ 50, else a background job).

### 4. Approvals
Actions flagged `REQ_APPROVAL` create a row in `/COD1/IDOC_APRV` (state `REQUESTED`). Approve/reject
in SM30/SE16 (or extend the dashboard's approvals view); an approved request becomes executable.

## Verify against the `/COD1/IDOC_TESTGEN` data

1. Run `/COD1/IDOC_TESTGEN` (bulk mode) to populate errored IDocs.
2. `P_REFR=X` → `/COD1/IDOC_SIG` shows ~11 signatures, counts matching the generator (status-29 dominant).
3. Dashboard → KPIs + signatures; drill to instances; drill to status history.
4. Maintain one action; **Run action** on a status-51 IDoc → status changes (check WE02), one
   `/COD1/IDOC_AUD` row written.
5. **Bulk run** a small signature → `/COD1/IDOC_BJOB` reaches `DONE`; re-running skips already-fixed
   IDocs (status-guard); one audit row per item.
6. An `REQ_APPROVAL` action → `/COD1/IDOC_APRV` `REQUESTED`; approve → executes.

## Invariants (carried from the BTP app)
- **Throttle bulk** (INV-1): mass actions go through `/COD1/CL_IDOC_MON_BULK` (packaged + rate-paced),
  never a naive loop. **Idempotent** (INV-9): each item is status-guarded before the command runs.
  **Audit sacred** (INV-13): `/COD1/IDOC_AUD` is append-only — nothing deletes it. **No generic
  action** (INV-8): only the registered command keys.

## Notes / limits
- ABAP has no real threads in a report: bulk throttle = package size + `WAIT` on `RATE_PER_MIN`;
  `CONCURRENCY` is stored but advisory.
- The instances grid is **capped** (default 5000) — a 1.8M-instance signature is never loaded whole;
  bulk processes the full scope server-side regardless.
- `refresh_signatures` aggregates the errored subset (~2.2M of 12M) in one `GROUP BY`; run it in the
  background and rely on the EDIDC status index.
