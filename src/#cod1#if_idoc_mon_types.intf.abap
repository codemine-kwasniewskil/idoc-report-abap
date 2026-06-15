"! <p class="shorttext synchronized">IDoc Monitor - DTO type definitions</p>
"! Transport structures for the in-ERP monitor (signatures, instances, KPIs,
"! actions, approvals). Decoupled from the DDIC line types so the dashboard
"! and the engines share one stable contract.
INTERFACE /cod1/if_idoc_mon_types
  PUBLIC.

  "! Signature aggregate (one recurring error pattern), as shown on the dashboard.
  TYPES: BEGIN OF ts_signature,
           sig_key      TYPE /cod1/idoc_sig-sig_key,
           direct       TYPE edidc-direct,
           mestyp       TYPE edidc-mestyp,
           status       TYPE edidc-status,
           stamid       TYPE edids-stamid,
           stamno       TYPE edids-stamno,
           text         TYPE /cod1/idoc_sig-text,
           instance_cnt TYPE i,
           first_seen   TYPE edidc-credat,
           last_seen    TYPE edidc-credat,
           config_state TYPE /cod1/idoc_sig-config_state,
           has_actions  TYPE abap_bool,
         END OF ts_signature.
  TYPES tt_signature TYPE STANDARD TABLE OF ts_signature WITH DEFAULT KEY.

  "! Errored-IDoc instance (drill-down row under a signature).
  TYPES: BEGIN OF ts_instance,
           docnum TYPE edidc-docnum,
           status TYPE edidc-status,
           direct TYPE edidc-direct,
           mestyp TYPE edidc-mestyp,
           sndprn TYPE edidc-sndprn,
           rcvprn TYPE edidc-rcvprn,
           credat TYPE edidc-credat,
           cretim TYPE edidc-cretim,
           stamid TYPE edids-stamid,
           stamno TYPE edids-stamno,
         END OF ts_instance.
  TYPES tt_instance TYPE STANDARD TABLE OF ts_instance WITH DEFAULT KEY.

  "! KPI tile (count of errored IDocs per status, split by direction).
  TYPES: BEGIN OF ts_kpi,
           direct TYPE edidc-direct,
           status TYPE edidc-status,
           cnt    TYPE i,
         END OF ts_kpi.
  TYPES tt_kpi TYPE STANDARD TABLE OF ts_kpi WITH DEFAULT KEY.

  "! Configured action for a signature (data-driven, from /COD1/IDOC_ACFG).
  TYPES: BEGIN OF ts_action,
           action_id    TYPE /cod1/idoc_acfg-action_id,
           sig_key      TYPE /cod1/idoc_acfg-sig_key,
           label        TYPE /cod1/idoc_acfg-label_txt,
           seqnr        TYPE /cod1/idoc_acfg-seqnr,
           target       TYPE /cod1/idoc_acfg-target,   "command key: REPROCESS/SET_STATUS/CLOSE/TRIGGER
           params       TYPE /cod1/idoc_acfg-params,   "e.g. status=68;message=closed
           bulkable     TYPE abap_bool,
           req_approval TYPE abap_bool,
           rate_per_min TYPE i,
           concurrency  TYPE i,
         END OF ts_action.
  TYPES tt_action TYPE STANDARD TABLE OF ts_action WITH DEFAULT KEY.

  "! Open/processed approval requests (named type - RETURNING cannot use an
  "! inline STANDARD TABLE OF ...).
  TYPES tt_approval TYPE STANDARD TABLE OF /cod1/idoc_aprv WITH DEFAULT KEY.

  "! Filter for the signature list / refresh.
  TYPES: BEGIN OF ts_filter,
           direct    TYPE edidc-direct,
           status    TYPE edidc-status,
           mestyp    TYPE edidc-mestyp,
           cred_from TYPE edidc-credat,
           cred_to   TYPE edidc-credat,
           max_rows  TYPE i,
         END OF ts_filter.

ENDINTERFACE.
