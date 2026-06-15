"! <p class="shorttext synchronized">IDoc Monitor - action config registry</p>
"! Registry over the data-driven /COD1/IDOC_ACFG customizing table: which actions
"! a signature offers, mapping each to an existing command key (REPROCESS /
"! SET_STATUS / CLOSE / TRIGGER). No control logic here - just the lookup.
CLASS /cod1/cl_idoc_mon_actioncfg DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Actions configured for a signature, ordered by SEQNR.
    METHODS read_for_signature
      IMPORTING iv_sig_key      TYPE /cod1/idoc_acfg-sig_key
      RETURNING VALUE(rt_action) TYPE /cod1/if_idoc_mon_types=>tt_action.

    "! Single action by id.
    METHODS read_action
      IMPORTING iv_action_id    TYPE /cod1/idoc_acfg-action_id
      RETURNING VALUE(rs_action) TYPE /cod1/if_idoc_mon_types=>ts_action.

    "! Set of signature keys that have at least one configured action
    "! (so the dashboard can flag "needs mapping").
    METHODS configured_keys
      RETURNING VALUE(rt_keys) TYPE /cod1/if_idoc_mon_types=>tt_signature.

    "! Map a configured action + a target IDoc to the existing service's action
    "! request. TARGET is the command key; PARAMS is "k=v;k=v" (status, message,
    "! mestyp, rcvprn, rcvprt). Shared by single and bulk execution.
    CLASS-METHODS build_request
      IMPORTING is_action         TYPE /cod1/if_idoc_mon_types=>ts_action
                iv_docnum         TYPE edidc-docnum
      RETURNING VALUE(rs_request) TYPE /cod1/if_idoc_types=>ts_action_request.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_actioncfg IMPLEMENTATION.

  METHOD read_for_signature.
    SELECT action_id, sig_key, label, seqnr, target, params,
           bulkable, req_approval, rate_per_min, concurrency
      FROM /cod1/idoc_acfg
      WHERE sig_key = @iv_sig_key
      ORDER BY seqnr
      INTO CORRESPONDING FIELDS OF TABLE @rt_action.
  ENDMETHOD.

  METHOD read_action.
    SELECT SINGLE action_id, sig_key, label, seqnr, target, params,
           bulkable, req_approval, rate_per_min, concurrency
      FROM /cod1/idoc_acfg
      WHERE action_id = @iv_action_id
      INTO CORRESPONDING FIELDS OF @rs_action.
  ENDMETHOD.

  METHOD configured_keys.
    SELECT DISTINCT sig_key FROM /cod1/idoc_acfg
      INTO CORRESPONDING FIELDS OF TABLE @rt_keys.
  ENDMETHOD.

  METHOD build_request.
    rs_request-action = is_action-target.            "REPROCESS / SET_STATUS / CLOSE / TRIGGER
    rs_request-docnum = iv_docnum.

    " parse PARAMS "k=v;k=v" into the typed request fields
    SPLIT is_action-params AT ';' INTO TABLE DATA(lt_pairs).
    LOOP AT lt_pairs INTO DATA(lv_pair).
      SPLIT lv_pair AT '=' INTO DATA(lv_k) DATA(lv_v).
      CONDENSE: lv_k, lv_v.
      CASE to_lower( lv_k ).
        WHEN 'status'.  rs_request-status  = lv_v.
        WHEN 'message'. rs_request-message = lv_v.
        WHEN 'mestyp'.  rs_request-mestyp  = lv_v.
        WHEN 'rcvprn'.  rs_request-rcvprn  = lv_v.
        WHEN 'rcvprt'.  rs_request-rcvprt  = lv_v.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
