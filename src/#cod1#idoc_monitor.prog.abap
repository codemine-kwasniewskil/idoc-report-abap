*&---------------------------------------------------------------------*
*& Report /COD1/IDOC_MONITOR
*&---------------------------------------------------------------------*
*& In-ERP IDoc monitor - the ABAP OO counterpart of the BTP service +
*& dashboard. Thin entry point; all logic lives in the monitor classes
*& (facade / repository / signature / actioncfg / bulk / approval / audit /
*& dashboard), which reuse /COD1/CL_IDOC_SERVICE for every read and action.
*&
*& Modes:
*&   (default)   show the interactive SALV dashboard
*&   P_REFR = X  rebuild the materialized signatures (schedule as a job)
*&   P_JOB  set  run a queued bulk job (set automatically by submit_bulk)
*&---------------------------------------------------------------------*
REPORT /cod1/idoc_monitor.

PARAMETERS: p_refr AS CHECKBOX DEFAULT ' '.
PARAMETERS: p_job  TYPE /cod1/idoc_bjob-job_id NO-DISPLAY.

START-OF-SELECTION.
  DATA(go_facade) = /cod1/cl_idoc_mon_factory=>create_facade( ).

  " --- background bulk runner step (scheduled by the facade) ---
  IF p_job IS NOT INITIAL.
    go_facade->run_bulk( p_job ).
    RETURN.
  ENDIF.

  " --- refresh the materialized signatures (the "sync" equivalent) ---
  IF p_refr = abap_true.
    DATA(lv_n) = go_facade->refresh_signatures( ).
    WRITE: / |Signatures refreshed: { lv_n }|.
    RETURN.
  ENDIF.

  " --- interactive dashboard ---
  NEW /cod1/cl_idoc_mon_dashboard( go_facade )->show( ).
