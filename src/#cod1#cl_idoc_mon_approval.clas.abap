"! <p class="shorttext synchronized">IDoc Monitor - approval state machine</p>
"! An action flagged REQ_APPROVAL must be approved before it runs. Simple state
"! machine over /COD1/IDOC_APRV: REQUESTED -> APPROVED | REJECTED. Every
"! transition is written to the audit log.
CLASS /cod1/cl_idoc_mon_approval DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_audit TYPE REF TO /cod1/cl_idoc_mon_audit.

    "! Raise an approval request (state REQUESTED). DOCNUM set for a single
    "! action, blank + SCOPE_CNT for a bulk request.
    METHODS request
      IMPORTING iv_sig_key       TYPE /cod1/idoc_aprv-sig_key
                iv_action_id     TYPE /cod1/idoc_aprv-action_id
                iv_docnum        TYPE edidc-docnum OPTIONAL
                iv_scope_cnt     TYPE i DEFAULT 1
      RETURNING VALUE(rv_aprv_id) TYPE /cod1/idoc_aprv-aprv_id.

    METHODS approve IMPORTING iv_aprv_id TYPE /cod1/idoc_aprv-aprv_id.
    METHODS reject  IMPORTING iv_aprv_id TYPE /cod1/idoc_aprv-aprv_id.

    METHODS is_approved
      IMPORTING iv_aprv_id      TYPE /cod1/idoc_aprv-aprv_id
      RETURNING VALUE(rv_ok)    TYPE abap_bool.

    "! Open (REQUESTED) requests, for the dashboard "Approvals" view.
    METHODS list_open
      RETURNING VALUE(rt_aprv) TYPE /cod1/if_idoc_mon_types=>tt_approval.

  PRIVATE SECTION.
    DATA mo_audit TYPE REF TO /cod1/cl_idoc_mon_audit.
    METHODS set_state
      IMPORTING iv_aprv_id TYPE /cod1/idoc_aprv-aprv_id
                iv_state   TYPE /cod1/idoc_aprv-state.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_approval IMPLEMENTATION.

  METHOD constructor.
    mo_audit = io_audit.
  ENDMETHOD.

  METHOD request.
    DATA ls_aprv TYPE /cod1/idoc_aprv.
    TRY.
        ls_aprv-aprv_id = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        GET TIME STAMP FIELD DATA(lv_ts).
        ls_aprv-aprv_id = |{ lv_ts }{ sy-uzeit }|.
    ENDTRY.

    GET TIME STAMP FIELD ls_aprv-created_at.
    ls_aprv-mandt        = sy-mandt.
    ls_aprv-sig_key      = iv_sig_key.
    ls_aprv-action_id    = iv_action_id.
    ls_aprv-docnum       = iv_docnum.
    ls_aprv-scope_cnt    = iv_scope_cnt.
    ls_aprv-state        = /cod1/cl_idoc_mon_config=>c_approval-requested.
    ls_aprv-requested_by = sy-uname.
    ls_aprv-updated_at   = ls_aprv-created_at.

    INSERT /cod1/idoc_aprv FROM ls_aprv.
    COMMIT WORK.
    rv_aprv_id = ls_aprv-aprv_id.

    mo_audit->log( iv_docnum    = iv_docnum
                   iv_action_id = iv_action_id
                   iv_action    = 'APPROVAL_REQUEST'
                   iv_result    = |request { rv_aprv_id }| ).
  ENDMETHOD.

  METHOD approve.
    set_state( iv_aprv_id = iv_aprv_id iv_state = /cod1/cl_idoc_mon_config=>c_approval-approved ).
    mo_audit->log( iv_action = 'APPROVAL_APPROVE' iv_result = |{ iv_aprv_id }| ).
  ENDMETHOD.

  METHOD reject.
    set_state( iv_aprv_id = iv_aprv_id iv_state = /cod1/cl_idoc_mon_config=>c_approval-rejected ).
    mo_audit->log( iv_action = 'APPROVAL_REJECT' iv_success = abap_false iv_result = |{ iv_aprv_id }| ).
  ENDMETHOD.

  METHOD set_state.
    GET TIME STAMP FIELD DATA(lv_now).
    UPDATE /cod1/idoc_aprv
       SET state       = @iv_state,
           approved_by = @sy-uname,
           updated_at  = @lv_now
     WHERE aprv_id = @iv_aprv_id.
    COMMIT WORK.
  ENDMETHOD.

  METHOD is_approved.
    SELECT SINGLE state FROM /cod1/idoc_aprv
      WHERE aprv_id = @iv_aprv_id INTO @DATA(lv_state).
    rv_ok = xsdbool( lv_state = /cod1/cl_idoc_mon_config=>c_approval-approved ).
  ENDMETHOD.

  METHOD list_open.
    SELECT * FROM /cod1/idoc_aprv
      WHERE state = @/cod1/cl_idoc_mon_config=>c_approval-requested
      INTO TABLE @rt_aprv.
  ENDMETHOD.

ENDCLASS.
