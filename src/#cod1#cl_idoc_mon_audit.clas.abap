"! <p class="shorttext synchronized">IDoc Monitor - audit log (append only)</p>
"! Writes the immutable remediation/audit trail to /COD1/IDOC_AUD. Every action
"! result and approval transition is recorded. INV-13: this log is sacred - the
"! class offers no delete and nothing in the monitor ever removes a row.
CLASS /cod1/cl_idoc_mon_audit DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Append one audit record. Commits in its own LUW so the trail survives
    "! even if the surrounding action is later rolled back.
    METHODS log
      IMPORTING iv_docnum    TYPE edidc-docnum OPTIONAL
                iv_action_id TYPE /cod1/idoc_aud-action_id OPTIONAL
                iv_action    TYPE /cod1/idoc_aud-action
                iv_request   TYPE string OPTIONAL
                iv_result    TYPE string OPTIONAL
                iv_success   TYPE abap_bool DEFAULT abap_true.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_audit IMPLEMENTATION.

  METHOD log.
    DATA ls_aud TYPE /cod1/idoc_aud.

    TRY.
        ls_aud-aud_id = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        GET TIME STAMP FIELD DATA(lv_ts).
        ls_aud-aud_id = |{ lv_ts }{ sy-uzeit }{ sy-tabix }|.
    ENDTRY.

    GET TIME STAMP FIELD ls_aud-created_at.
    ls_aud-mandt      = sy-mandt.
    ls_aud-docnum     = iv_docnum.
    ls_aud-action_id  = iv_action_id.
    ls_aud-action     = iv_action.
    ls_aud-request    = iv_request.
    ls_aud-result     = iv_result.
    ls_aud-success    = iv_success.
    ls_aud-created_by = sy-uname.

    INSERT /cod1/idoc_aud FROM ls_aud.
    COMMIT WORK.
  ENDMETHOD.

ENDCLASS.
