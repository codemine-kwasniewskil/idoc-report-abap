"! <p class="shorttext synchronized">IDoc Monitor - repository (read side)</p>
"! Repository pattern. All DB access for the monitor: the signature
"! aggregation/refresh and the live reads (signatures, instances, KPIs).
"! The facade depends only on this interface, so the read side is testable
"! via a double.
INTERFACE /cod1/if_idoc_mon_repository
  PUBLIC.

  "! Rebuild the materialized signature aggregate (/COD1/IDOC_SIG) from the
  "! errored IDocs in EDIDC/EDIDS. Idempotent; preserves CONFIG_STATE of
  "! existing signatures. Run as a (background) job.
  METHODS refresh_signatures
    RETURNING VALUE(rv_count) TYPE i.

  "! Read the materialized signatures for the dashboard.
  METHODS read_signatures
    IMPORTING is_filter        TYPE /cod1/if_idoc_mon_types=>ts_filter OPTIONAL
    RETURNING VALUE(rt_sig)    TYPE /cod1/if_idoc_mon_types=>tt_signature.

  "! One signature header (for drill-down / action scope).
  METHODS read_signature
    IMPORTING iv_sig_key      TYPE /cod1/idoc_sig-sig_key
    RETURNING VALUE(rs_sig)   TYPE /cod1/if_idoc_mon_types=>ts_signature.

  "! Live read of the errored IDocs belonging to a signature (capped).
  METHODS read_instances
    IMPORTING iv_sig_key         TYPE /cod1/idoc_sig-sig_key
              iv_max_rows        TYPE i OPTIONAL
    RETURNING VALUE(rt_instance) TYPE /cod1/if_idoc_mon_types=>tt_instance.

  "! KPI counts (errored IDocs by direction + status).
  METHODS read_kpis
    RETURNING VALUE(rt_kpi) TYPE /cod1/if_idoc_mon_types=>tt_kpi.

ENDINTERFACE.
