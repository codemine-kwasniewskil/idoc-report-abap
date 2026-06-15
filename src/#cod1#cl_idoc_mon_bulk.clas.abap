"! <p class="shorttext synchronized">IDoc Monitor - bulk action runner</p>
"! Throttled bulk execution (BTP INV-1/INV-9). Runs a configured action over all
"! errored IDocs of a signature in COMMIT-bounded packages, status-guarding each
"! item (skip if no longer in error), pacing by RATE_PER_MIN, logging every item
"! to the audit, and tracking progress in /COD1/IDOC_BJOB. Actions execute only
"! through the existing service - no control logic here.
CLASS /cod1/cl_idoc_mon_bulk DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_service   TYPE REF TO /cod1/if_idoc_service
                io_repository TYPE REF TO /cod1/if_idoc_mon_repository
                io_actioncfg TYPE REF TO /cod1/cl_idoc_mon_actioncfg
                io_audit     TYPE REF TO /cod1/cl_idoc_mon_audit.

    "! Queue a bulk job (state QUEUED) for a signature + action. Returns the job id.
    METHODS submit
      IMPORTING iv_sig_key      TYPE /cod1/idoc_bjob-sig_key
                iv_action_id    TYPE /cod1/idoc_bjob-action_id
      RETURNING VALUE(rv_job_id) TYPE /cod1/idoc_bjob-job_id.

    "! Execute a queued job (foreground for small scope, or in a background step).
    METHODS run
      IMPORTING iv_job_id TYPE /cod1/idoc_bjob-job_id.

  PRIVATE SECTION.
    DATA: mo_service    TYPE REF TO /cod1/if_idoc_service,
          mo_repository TYPE REF TO /cod1/if_idoc_mon_repository,
          mo_actioncfg  TYPE REF TO /cod1/cl_idoc_mon_actioncfg,
          mo_audit      TYPE REF TO /cod1/cl_idoc_mon_audit.

    METHODS still_errored
      IMPORTING iv_docnum     TYPE edidc-docnum
      RETURNING VALUE(rv_yes) TYPE abap_bool.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_bulk IMPLEMENTATION.

  METHOD constructor.
    mo_service    = io_service.
    mo_repository = io_repository.
    mo_actioncfg  = io_actioncfg.
    mo_audit      = io_audit.
  ENDMETHOD.

  METHOD submit.
    DATA(ls_sig) = mo_repository->read_signature( iv_sig_key ).

    DATA ls_job TYPE /cod1/idoc_bjob.
    TRY.
        ls_job-job_id = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        GET TIME STAMP FIELD DATA(lv_ts).
        ls_job-job_id = |{ lv_ts }{ sy-uzeit }|.
    ENDTRY.

    DATA(ls_action) = mo_actioncfg->read_action( iv_action_id ).
    GET TIME STAMP FIELD ls_job-created_at.
    ls_job-mandt        = sy-mandt.
    ls_job-sig_key      = iv_sig_key.
    ls_job-action_id    = iv_action_id.
    ls_job-scope_cnt    = ls_sig-instance_cnt.
    ls_job-rate_per_min = COND i( WHEN ls_action-rate_per_min > 0 THEN ls_action-rate_per_min
                                  ELSE /cod1/cl_idoc_mon_config=>c_default_rate_min ).
    ls_job-state        = /cod1/cl_idoc_mon_config=>c_job-queued.
    ls_job-launched_by  = sy-uname.
    ls_job-updated_at   = ls_job-created_at.

    INSERT /cod1/idoc_bjob FROM ls_job.
    COMMIT WORK.
    rv_job_id = ls_job-job_id.
  ENDMETHOD.

  METHOD run.
    SELECT SINGLE * FROM /cod1/idoc_bjob WHERE job_id = @iv_job_id INTO @DATA(ls_job).
    IF sy-subrc <> 0 OR ls_job-state = /cod1/cl_idoc_mon_config=>c_job-done.
      RETURN.
    ENDIF.

    DATA(ls_action) = mo_actioncfg->read_action( ls_job-action_id ).
    IF ls_action-bulkable = abap_false.
      RETURN.
    ENDIF.

    " whole scope of the signature (capped by config); process packaged.
    DATA(lt_inst) = mo_repository->read_instances( iv_sig_key  = ls_job-sig_key
                                                   iv_max_rows = ls_job-scope_cnt ).
    DATA(lv_rate)    = COND i( WHEN ls_job-rate_per_min > 0 THEN ls_job-rate_per_min ELSE 60 ).
    DATA(lv_pkg)     = /cod1/cl_idoc_mon_config=>c_bulk_package.
    DATA(lv_in_pkg)  = 0.
    DATA(lv_done)    = 0.
    DATA(lv_fail)    = 0.

    UPDATE /cod1/idoc_bjob SET state = @/cod1/cl_idoc_mon_config=>c_job-running
                           WHERE job_id = @iv_job_id.
    COMMIT WORK.

    LOOP AT lt_inst INTO DATA(ls_inst).
      " INV-9: idempotent guard - act only if the IDoc is still errored.
      IF still_errored( ls_inst-docnum ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(ls_req) = /cod1/cl_idoc_mon_actioncfg=>build_request(
                       is_action = ls_action iv_docnum = ls_inst-docnum ).
      TRY.
          DATA(ls_res) = mo_service->execute_action( ls_req ).
          IF ls_res-success = abap_true.
            lv_done = lv_done + 1.
          ELSE.
            lv_fail = lv_fail + 1.
          ENDIF.
          mo_audit->log( iv_docnum    = ls_inst-docnum
                         iv_action_id = ls_job-action_id
                         iv_action    = ls_action-target
                         iv_request   = |bulk { iv_job_id }|
                         iv_result    = ls_res-message
                         iv_success   = ls_res-success ).
        CATCH /cod1/cx_idoc_error INTO DATA(lx).
          lv_fail = lv_fail + 1.
          mo_audit->log( iv_docnum    = ls_inst-docnum
                         iv_action_id = ls_job-action_id
                         iv_action    = ls_action-target
                         iv_request   = |bulk { iv_job_id }|
                         iv_result    = lx->get_text( )
                         iv_success   = abap_false ).
      ENDTRY.

      lv_in_pkg = lv_in_pkg + 1.
      IF lv_in_pkg >= lv_pkg.
        UPDATE /cod1/idoc_bjob SET done_cnt = @lv_done, fail_cnt = @lv_fail
                               WHERE job_id = @iv_job_id.
        COMMIT WORK.
        lv_in_pkg = 0.
        " throttle: keep within RATE_PER_MIN (seconds to drain one package).
        DATA(lv_wait) = lv_pkg * 60 / lv_rate.
        IF lv_wait > 0.
          WAIT UP TO lv_wait SECONDS.
        ENDIF.
      ENDIF.
    ENDLOOP.

    UPDATE /cod1/idoc_bjob
       SET done_cnt = @lv_done, fail_cnt = @lv_fail,
           state    = @/cod1/cl_idoc_mon_config=>c_job-done
     WHERE job_id = @iv_job_id.
    COMMIT WORK.

    mo_audit->log( iv_action_id = ls_job-action_id
                   iv_action    = 'BULK_DONE'
                   iv_result    = |job { iv_job_id } done={ lv_done } fail={ lv_fail }| ).
  ENDMETHOD.

  METHOD still_errored.
    DATA(lt_err) = /cod1/cl_idoc_mon_config=>error_status_range( ).
    SELECT SINGLE status FROM edidc WHERE docnum = @iv_docnum INTO @DATA(lv_status).
    rv_yes = xsdbool( sy-subrc = 0 AND lv_status IN lt_err ).
  ENDMETHOD.

ENDCLASS.
