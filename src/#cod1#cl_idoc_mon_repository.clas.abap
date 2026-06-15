"! <p class="shorttext synchronized">IDoc Monitor - repository (read side)</p>
"! Repository pattern. Aggregates errored IDocs (EDIDC join the matching EDIDS
"! status record) into the materialized /COD1/IDOC_SIG, and serves the live
"! reads for the dashboard (signatures, instances, KPIs). No control logic.
CLASS /cod1/cl_idoc_mon_repository DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES /cod1/if_idoc_mon_repository.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_repository IMPLEMENTATION.

  METHOD /cod1/if_idoc_mon_repository~refresh_signatures.
    DATA(lt_err) = /cod1/cl_idoc_mon_config=>error_status_range( ).

    " Aggregate the errored IDocs by the composing fields. The error status
    " record (EDIDS where status = current EDIDC status) carries STAMID/STAMNO.
    " COUNT DISTINCT docnum so a 2-record status chain is not double counted.
    SELECT c~direct, c~mestyp, c~status, s~stamid, s~stamno,
           COUNT( DISTINCT c~docnum ) AS cnt,
           MIN( c~credat ) AS first_seen,
           MAX( c~credat ) AS last_seen
      FROM edidc AS c
      INNER JOIN edids AS s
        ON  s~docnum = c~docnum
        AND s~status = c~status
      WHERE c~status IN @lt_err
      GROUP BY c~direct, c~mestyp, c~status, s~stamid, s~stamno
      INTO TABLE @DATA(lt_agg).

    " Preserve CONFIG_STATE of signatures that already exist (BTP S6.2).
    SELECT sig_key, config_state FROM /cod1/idoc_sig
      INTO TABLE @DATA(lt_existing).
    SORT lt_existing BY sig_key.

    GET TIME STAMP FIELD DATA(lv_now).
    DATA lt_sig TYPE STANDARD TABLE OF /cod1/idoc_sig.

    LOOP AT lt_agg INTO DATA(ls_agg).
      DATA(lv_key) = /cod1/cl_idoc_mon_signature=>compute(
                       iv_direct = ls_agg-direct iv_mestyp = ls_agg-mestyp
                       iv_status = ls_agg-status iv_stamid = ls_agg-stamid
                       iv_stamno = ls_agg-stamno ).

      READ TABLE lt_existing INTO DATA(ls_ex) WITH KEY sig_key = lv_key BINARY SEARCH.
      DATA(lv_state) = COND /cod1/idoc_sig-config_state(
        WHEN sy-subrc = 0 THEN ls_ex-config_state
        ELSE /cod1/cl_idoc_mon_config=>c_config_state-needs_config ).

      APPEND VALUE #(
        mandt        = sy-mandt
        sig_key      = lv_key
        direct       = ls_agg-direct
        mestyp       = ls_agg-mestyp
        status       = ls_agg-status
        stamid       = ls_agg-stamid
        stamno       = ls_agg-stamno
        text         = /cod1/cl_idoc_mon_signature=>describe(
                         iv_direct = ls_agg-direct iv_mestyp = ls_agg-mestyp
                         iv_status = ls_agg-status iv_stamid = ls_agg-stamid
                         iv_stamno = ls_agg-stamno )
        instance_cnt = ls_agg-cnt
        first_seen   = ls_agg-first_seen
        last_seen    = ls_agg-last_seen
        config_state = lv_state
        refreshed_at = lv_now ) TO lt_sig.
    ENDLOOP.

    MODIFY /cod1/idoc_sig FROM TABLE lt_sig.
    COMMIT WORK.
    rv_count = lines( lt_sig ).
  ENDMETHOD.


  METHOD /cod1/if_idoc_mon_repository~read_signatures.
    " /cod1/idoc_sig holds only the aggregate (a handful of rows), so read all
    " and apply the optional filter in memory - Open SQL does not allow a host
    " variable on the left of a WHERE comparison (the "@is_filter-x = ''" form).
    SELECT sig_key, direct, mestyp, status, stamid, stamno, text,
           instance_cnt, first_seen, last_seen, config_state
      FROM /cod1/idoc_sig
      ORDER BY instance_cnt DESCENDING
      INTO CORRESPONDING FIELDS OF TABLE @rt_sig.

    IF is_filter-direct IS NOT INITIAL.
      DELETE rt_sig WHERE direct <> is_filter-direct.
    ENDIF.
    IF is_filter-status IS NOT INITIAL.
      DELETE rt_sig WHERE status <> is_filter-status.
    ENDIF.
    IF is_filter-mestyp IS NOT INITIAL.
      DELETE rt_sig WHERE mestyp <> is_filter-mestyp.
    ENDIF.

    " flag which signatures already have a configured action
    SELECT DISTINCT sig_key FROM /cod1/idoc_acfg INTO TABLE @DATA(lt_cfg).
    SORT lt_cfg BY sig_key.
    LOOP AT rt_sig ASSIGNING FIELD-SYMBOL(<s>).
      READ TABLE lt_cfg TRANSPORTING NO FIELDS WITH KEY sig_key = <s>-sig_key BINARY SEARCH.
      <s>-has_actions = xsdbool( sy-subrc = 0 ).
    ENDLOOP.
  ENDMETHOD.


  METHOD /cod1/if_idoc_mon_repository~read_signature.
    SELECT SINGLE sig_key, direct, mestyp, status, stamid, stamno, text,
           instance_cnt, first_seen, last_seen, config_state
      FROM /cod1/idoc_sig
      WHERE sig_key = @iv_sig_key
      INTO CORRESPONDING FIELDS OF @rs_sig.
  ENDMETHOD.


  METHOD /cod1/if_idoc_mon_repository~read_instances.
    DATA(lv_max) = COND i( WHEN iv_max_rows > 0 THEN iv_max_rows
                           ELSE /cod1/cl_idoc_mon_config=>c_max_instance_rows ).

    DATA(ls_sig) = /cod1/if_idoc_mon_repository~read_signature( iv_sig_key ).
    IF ls_sig-sig_key IS INITIAL.
      RETURN.
    ENDIF.

    SELECT c~docnum, c~status, c~direct, c~mestyp, c~sndprn, c~rcvprn,
           c~credat, c~cretim, s~stamid, s~stamno
      FROM edidc AS c
      INNER JOIN edids AS s
        ON  s~docnum = c~docnum
        AND s~status = c~status
      WHERE c~direct = @ls_sig-direct
        AND c~mestyp = @ls_sig-mestyp
        AND c~status = @ls_sig-status
        AND s~stamid = @ls_sig-stamid
        AND s~stamno = @ls_sig-stamno
      ORDER BY c~docnum
      INTO CORRESPONDING FIELDS OF TABLE @rt_instance
      UP TO @lv_max ROWS.
  ENDMETHOD.


  METHOD /cod1/if_idoc_mon_repository~read_kpis.
    DATA(lt_err) = /cod1/cl_idoc_mon_config=>error_status_range( ).
    SELECT direct, status, COUNT(*) AS cnt
      FROM edidc
      WHERE status IN @lt_err
      GROUP BY direct, status
      ORDER BY direct, status
      INTO CORRESPONDING FIELDS OF TABLE @rt_kpi.
  ENDMETHOD.

ENDCLASS.
