"! <p class="shorttext synchronized">IDoc Monitor - facade</p>
"! Facade pattern. The single entry point for the report/dashboard: KPIs, list
"! signatures + instances, resolve actions, execute single, submit bulk, refresh,
"! and the approval operations. Composes the repository, action registry, audit,
"! approval and bulk engines + the existing /COD1/CL_IDOC_SERVICE (for the actual
"! reads/actions). Holds no control logic of its own.
CLASS /cod1/cl_idoc_mon_facade DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_repository TYPE REF TO /cod1/if_idoc_mon_repository
                io_actioncfg  TYPE REF TO /cod1/cl_idoc_mon_actioncfg
                io_audit      TYPE REF TO /cod1/cl_idoc_mon_audit
                io_approval   TYPE REF TO /cod1/cl_idoc_mon_approval
                io_bulk       TYPE REF TO /cod1/cl_idoc_mon_bulk
                io_service    TYPE REF TO /cod1/if_idoc_service.

    " ---- dashboard reads ----
    METHODS read_kpis        RETURNING VALUE(rt_kpi) TYPE /cod1/if_idoc_mon_types=>tt_kpi.
    METHODS list_signatures
      IMPORTING is_filter     TYPE /cod1/if_idoc_mon_types=>ts_filter OPTIONAL
      RETURNING VALUE(rt_sig) TYPE /cod1/if_idoc_mon_types=>tt_signature.
    METHODS read_signature
      IMPORTING iv_sig_key    TYPE /cod1/idoc_sig-sig_key
      RETURNING VALUE(rs_sig) TYPE /cod1/if_idoc_mon_types=>ts_signature.
    METHODS list_instances
      IMPORTING iv_sig_key         TYPE /cod1/idoc_sig-sig_key
      RETURNING VALUE(rt_instance) TYPE /cod1/if_idoc_mon_types=>tt_instance.
    METHODS actions_for
      IMPORTING iv_sig_key       TYPE /cod1/idoc_sig-sig_key
      RETURNING VALUE(rt_action) TYPE /cod1/if_idoc_mon_types=>tt_action.
    METHODS get_detail
      IMPORTING iv_docnum        TYPE edidc-docnum
      RETURNING VALUE(rs_detail) TYPE /cod1/if_idoc_types=>ts_detail
      RAISING   /cod1/cx_idoc_error.

    " ---- actions ----
    "! Execute one action on one IDoc. If the action needs approval, raises a
    "! request instead and returns SUCCESS = abap_false with the request id.
    METHODS execute_single
      IMPORTING iv_docnum        TYPE edidc-docnum
                iv_action_id     TYPE /cod1/idoc_acfg-action_id
      RETURNING VALUE(rs_result) TYPE /cod1/if_idoc_types=>ts_action_result.

    "! Submit a throttled bulk action over the whole signature. Small scope runs
    "! in the foreground; large scope is scheduled as a background job. Returns
    "! the job id (empty when an approval was requested instead).
    METHODS submit_bulk
      IMPORTING iv_sig_key       TYPE /cod1/idoc_sig-sig_key
                iv_action_id     TYPE /cod1/idoc_acfg-action_id
      RETURNING VALUE(rv_job_id) TYPE /cod1/idoc_bjob-job_id.

    "! Background entry: run a queued bulk job.
    METHODS run_bulk IMPORTING iv_job_id TYPE /cod1/idoc_bjob-job_id.

    METHODS refresh_signatures RETURNING VALUE(rv_count) TYPE i.

    " ---- approvals ----
    METHODS list_approvals
      RETURNING VALUE(rt_aprv) TYPE /cod1/if_idoc_mon_types=>tt_approval.
    METHODS approve IMPORTING iv_aprv_id TYPE /cod1/idoc_aprv-aprv_id.
    METHODS reject  IMPORTING iv_aprv_id TYPE /cod1/idoc_aprv-aprv_id.

  PRIVATE SECTION.
    DATA: mo_repository TYPE REF TO /cod1/if_idoc_mon_repository,
          mo_actioncfg  TYPE REF TO /cod1/cl_idoc_mon_actioncfg,
          mo_audit      TYPE REF TO /cod1/cl_idoc_mon_audit,
          mo_approval   TYPE REF TO /cod1/cl_idoc_mon_approval,
          mo_bulk       TYPE REF TO /cod1/cl_idoc_mon_bulk,
          mo_service    TYPE REF TO /cod1/if_idoc_service.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_facade IMPLEMENTATION.

  METHOD constructor.
    mo_repository = io_repository.
    mo_actioncfg  = io_actioncfg.
    mo_audit      = io_audit.
    mo_approval   = io_approval.
    mo_bulk       = io_bulk.
    mo_service    = io_service.
  ENDMETHOD.

  METHOD read_kpis.        rt_kpi = mo_repository->read_kpis( ). ENDMETHOD.
  METHOD list_signatures.  rt_sig = mo_repository->read_signatures( is_filter ). ENDMETHOD.
  METHOD read_signature.   rs_sig = mo_repository->read_signature( iv_sig_key ). ENDMETHOD.
  METHOD list_instances.   rt_instance = mo_repository->read_instances( iv_sig_key ). ENDMETHOD.
  METHOD actions_for.      rt_action = mo_actioncfg->read_for_signature( iv_sig_key ). ENDMETHOD.
  METHOD refresh_signatures. rv_count = mo_repository->refresh_signatures( ). ENDMETHOD.
  METHOD run_bulk.         mo_bulk->run( iv_job_id ). ENDMETHOD.
  METHOD list_approvals.   rt_aprv = mo_approval->list_open( ). ENDMETHOD.
  METHOD approve.          mo_approval->approve( iv_aprv_id ). ENDMETHOD.
  METHOD reject.           mo_approval->reject( iv_aprv_id ). ENDMETHOD.

  METHOD get_detail.
    rs_detail = mo_service->get_detail( iv_docnum ).
  ENDMETHOD.

  METHOD execute_single.
    DATA(ls_action) = mo_actioncfg->read_action( iv_action_id ).

    IF ls_action-req_approval = abap_true.
      DATA(lv_aprv) = mo_approval->request( iv_sig_key   = ls_action-sig_key
                                            iv_action_id = iv_action_id
                                            iv_docnum    = iv_docnum ).
      rs_result = VALUE #( docnum  = iv_docnum action = ls_action-target
                           success = abap_false message = |Approval requested: { lv_aprv }| ).
      RETURN.
    ENDIF.

    DATA(ls_req) = /cod1/cl_idoc_mon_actioncfg=>build_request(
                     is_action = ls_action iv_docnum = iv_docnum ).
    TRY.
        rs_result = mo_service->execute_action( ls_req ).
      CATCH /cod1/cx_idoc_error INTO DATA(lx).
        rs_result = VALUE #( docnum  = iv_docnum action = ls_action-target
                             success = abap_false message = lx->get_text( ) ).
    ENDTRY.

    mo_audit->log( iv_docnum    = iv_docnum
                   iv_action_id = iv_action_id
                   iv_action    = ls_action-target
                   iv_request   = 'single'
                   iv_result    = rs_result-message
                   iv_success   = rs_result-success ).
  ENDMETHOD.

  METHOD submit_bulk.
    DATA(ls_action) = mo_actioncfg->read_action( iv_action_id ).

    IF ls_action-req_approval = abap_true.
      mo_approval->request( iv_sig_key   = iv_sig_key
                            iv_action_id = iv_action_id
                            iv_scope_cnt = mo_repository->read_signature( iv_sig_key )-instance_cnt ).
      RETURN.                                   "empty job id -> approval first
    ENDIF.

    rv_job_id = mo_bulk->submit( iv_sig_key = iv_sig_key iv_action_id = iv_action_id ).
    DATA(ls_sig) = mo_repository->read_signature( iv_sig_key ).

    IF ls_sig-instance_cnt <= /cod1/cl_idoc_mon_config=>c_bulk_fg_threshold.
      mo_bulk->run( rv_job_id ).                "small scope: run now
    ELSE.
      " large scope: schedule a background step running this report in bulk mode
      DATA lv_jobcount TYPE tbtcjob-jobcount.
      DATA(lv_jobname) = CONV tbtcjob-jobname( |COD1_IDOC_BULK| ).
      CALL FUNCTION 'JOB_OPEN'
        EXPORTING  jobname  = lv_jobname
        IMPORTING  jobcount = lv_jobcount
        EXCEPTIONS OTHERS   = 1.
      IF sy-subrc = 0.
        SUBMIT /cod1/idoc_monitor WITH p_job = rv_job_id
               VIA JOB lv_jobname NUMBER lv_jobcount AND RETURN.
        CALL FUNCTION 'JOB_CLOSE'
          EXPORTING jobcount  = lv_jobcount
                    jobname   = lv_jobname
                    strtimmed = abap_true
          EXCEPTIONS OTHERS   = 1.
      ENDIF.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
