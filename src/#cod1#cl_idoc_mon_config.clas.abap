"! <p class="shorttext synchronized">IDoc Monitor - config (statuses, throttle)</p>
"! Single place for tunable values - mirrors the BTP srv/config.js. Error-status
"! sets, signature composing fields (fixed here), bulk throttle + the instance
"! grid cap. Kept as constants/methods so behaviour changes without touching the
"! engines.
CLASS /cod1/cl_idoc_mon_config DEFINITION
  PUBLIC
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES tt_status_range TYPE RANGE OF edidc-status.

    CONSTANTS c_max_instance_rows  TYPE i VALUE 5000.   "instances SALV cap (never load 1.8M)
    CONSTANTS c_default_rate_min   TYPE i VALUE 60.     "bulk default rate / minute
    CONSTANTS c_bulk_package       TYPE i VALUE 200.    "bulk COMMIT package size
    CONSTANTS c_bulk_fg_threshold  TYPE i VALUE 50.     "<= run bulk in foreground, else background

    CONSTANTS: BEGIN OF c_config_state,
                 needs_config TYPE /cod1/idoc_sig-config_state VALUE 'NEEDS_CONFIG',
                 configured   TYPE /cod1/idoc_sig-config_state VALUE 'CONFIGURED',
               END OF c_config_state.

    CONSTANTS: BEGIN OF c_approval,
                 requested TYPE /cod1/idoc_aprv-state VALUE 'REQUESTED',
                 approved  TYPE /cod1/idoc_aprv-state VALUE 'APPROVED',
                 rejected  TYPE /cod1/idoc_aprv-state VALUE 'REJECTED',
               END OF c_approval.

    CONSTANTS: BEGIN OF c_job,
                 queued  TYPE /cod1/idoc_bjob-state VALUE 'QUEUED',
                 running TYPE /cod1/idoc_bjob-state VALUE 'RUNNING',
                 done    TYPE /cod1/idoc_bjob-state VALUE 'DONE',
               END OF c_job.

    "! Error-status set the monitor treats as "errored" (inbound + outbound),
    "! as a ready-to-use SELECT range. Mirrors BTP statuses.inbound/outboundError.
    CLASS-METHODS error_status_range
      RETURNING VALUE(rt_range) TYPE tt_status_range.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_config IMPLEMENTATION.

  METHOD error_status_range.
    DATA(lt_codes) = VALUE string_table(
      ( `51` ) ( `56` ) ( `61` ) ( `63` ) ( `65` )    "inbound application errors
      ( `02` ) ( `04` ) ( `05` ) ( `25` ) ( `26` ) ( `29` ) ).  "outbound / ALE errors
    LOOP AT lt_codes INTO DATA(lv_code).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = lv_code ) TO rt_range.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
