"! <p class="shorttext synchronized">IDoc Monitor - SALV dashboard (MVC)</p>
"! Interactive CL_SALV_TABLE dashboard: KPI header + signatures list; double-click
"! a signature to drill into its errored IDocs; double-click an instance for the
"! status history; toolbar buttons run the configured action single or throttled-
"! bulk. All behaviour goes through the facade (Observer = SALV events).
CLASS /cod1/cl_idoc_mon_dashboard DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING io_facade TYPE REF TO /cod1/cl_idoc_mon_facade.

    "! Build + display the signatures dashboard (entry from the report).
    METHODS show.

  PRIVATE SECTION.
    DATA: mo_facade   TYPE REF TO /cod1/cl_idoc_mon_facade,
          mt_sig      TYPE /cod1/if_idoc_mon_types=>tt_signature,
          mt_inst     TYPE /cod1/if_idoc_mon_types=>tt_instance,
          mo_sig_salv TYPE REF TO cl_salv_table,
          mo_inst_salv TYPE REF TO cl_salv_table,
          mv_cur_sig  TYPE /cod1/idoc_sig-sig_key,
          mt_cur_act  TYPE /cod1/if_idoc_mon_types=>tt_action.

    METHODS kpi_title RETURNING VALUE(rv_title) TYPE lvc_title.
    METHODS show_instances IMPORTING iv_sig_key TYPE /cod1/idoc_sig-sig_key.
    METHODS show_detail    IMPORTING iv_docnum  TYPE edidc-docnum.

    METHODS on_sig_dclick  FOR EVENT double_click   OF cl_salv_events_table IMPORTING row.
    METHODS on_inst_dclick FOR EVENT double_click   OF cl_salv_events_table IMPORTING row.
    METHODS on_inst_func   FOR EVENT added_function  OF cl_salv_events_table IMPORTING e_salv_function.
ENDCLASS.


CLASS /cod1/cl_idoc_mon_dashboard IMPLEMENTATION.

  METHOD constructor.
    mo_facade = io_facade.
  ENDMETHOD.

  METHOD kpi_title.
    DATA(lt_kpi) = mo_facade->read_kpis( ).
    DATA lv_total TYPE i.
    DATA lv_in    TYPE i.
    DATA lv_out   TYPE i.
    LOOP AT lt_kpi INTO DATA(ls).
      lv_total = lv_total + ls-cnt.
      IF ls-direct = '2'. lv_in = lv_in + ls-cnt. ELSE. lv_out = lv_out + ls-cnt. ENDIF.
    ENDLOOP.
    rv_title = |IDoc Monitor - errored { lv_total }  (IN { lv_in } / OUT { lv_out })  signatures { lines( mt_sig ) }|.
  ENDMETHOD.

  METHOD show.
    mt_sig = mo_facade->list_signatures( ).
    IF mt_sig IS INITIAL.
      MESSAGE 'No signatures - run the refresh (P_REFR) first' TYPE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_sig_salv
                                CHANGING  t_table      = mt_sig ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
        RETURN.
    ENDTRY.

    mo_sig_salv->get_functions( )->set_all( abap_true ).
    mo_sig_salv->get_columns( )->set_optimize( abap_true ).
    mo_sig_salv->get_display_settings( )->set_list_header( kpi_title( ) ).
    SET HANDLER on_sig_dclick FOR mo_sig_salv->get_event( ).
    mo_sig_salv->display( ).
  ENDMETHOD.

  METHOD on_sig_dclick.
    READ TABLE mt_sig INTO DATA(ls_sig) INDEX row.
    IF sy-subrc = 0.
      show_instances( ls_sig-sig_key ).
    ENDIF.
  ENDMETHOD.

  METHOD show_instances.
    mv_cur_sig = iv_sig_key.
    mt_cur_act = mo_facade->actions_for( iv_sig_key ).
    mt_inst    = mo_facade->list_instances( iv_sig_key ).
    IF mt_inst IS INITIAL.
      MESSAGE 'No errored instances for this signature' TYPE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_inst_salv
                                CHANGING  t_table      = mt_inst ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
        RETURN.
    ENDTRY.

    DATA(lo_fn) = mo_inst_salv->get_functions( ).
    lo_fn->set_all( abap_true ).
    TRY.
        lo_fn->add_function( name = 'SINGLE' text = 'Run action'
                             tooltip = 'Run the configured action on the selected IDoc(s)'
                             position = if_salv_c_function_position=>right_of_salv_functions ).
        lo_fn->add_function( name = 'BULK' text = 'Bulk run'
                             tooltip = 'Throttled run of the action on the whole signature'
                             position = if_salv_c_function_position=>right_of_salv_functions ).
      CATCH cx_salv_existing cx_salv_wrong_call ##NO_HANDLER.
    ENDTRY.

    mo_inst_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).
    mo_inst_salv->get_columns( )->set_optimize( abap_true ).
    mo_inst_salv->get_display_settings( )->set_list_header(
      |Signature { iv_sig_key }  ({ lines( mt_inst ) } shown)| ).
    SET HANDLER on_inst_dclick on_inst_func FOR mo_inst_salv->get_event( ).
    mo_inst_salv->set_screen_popup( start_column = 5 end_column = 130
                                    start_line   = 2 end_line   = 28 ).
    mo_inst_salv->display( ).
  ENDMETHOD.

  METHOD on_inst_dclick.
    READ TABLE mt_inst INTO DATA(ls_i) INDEX row.
    IF sy-subrc = 0.
      show_detail( ls_i-docnum ).
    ENDIF.
  ENDMETHOD.

  METHOD on_inst_func.
    IF mt_cur_act IS INITIAL.
      MESSAGE 'No action configured for this signature (maintain /COD1/IDOC_ACFG)' TYPE 'I'.
      RETURN.
    ENDIF.
    DATA(ls_action) = mt_cur_act[ 1 ].          "primary configured action

    CASE e_salv_function.
      WHEN 'SINGLE'.
        DATA(lt_sel) = mo_inst_salv->get_selections( )->get_selected_rows( ).
        IF lt_sel IS INITIAL.
          MESSAGE 'Select at least one IDoc' TYPE 'I'.
          RETURN.
        ENDIF.
        LOOP AT lt_sel INTO DATA(lv_row).
          READ TABLE mt_inst INTO DATA(ls_i) INDEX lv_row.
          CHECK sy-subrc = 0.
          DATA(ls_res) = mo_facade->execute_single( iv_docnum    = ls_i-docnum
                                                     iv_action_id = ls_action-action_id ).
          MESSAGE |{ ls_i-docnum }: { ls_res-message }| TYPE 'S'.
        ENDLOOP.
        mt_inst = mo_facade->list_instances( mv_cur_sig ).
        mo_inst_salv->refresh( ).

      WHEN 'BULK'.
        DATA(lv_job) = mo_facade->submit_bulk( iv_sig_key   = mv_cur_sig
                                               iv_action_id = ls_action-action_id ).
        IF lv_job IS INITIAL.
          MESSAGE 'Bulk action needs approval - request raised' TYPE 'I'.
        ELSE.
          MESSAGE |Bulk job { lv_job } submitted ({ ls_action-label })| TYPE 'I'.
        ENDIF.
        mt_inst = mo_facade->list_instances( mv_cur_sig ).
        mo_inst_salv->refresh( ).
    ENDCASE.
  ENDMETHOD.

  METHOD show_detail.
    DATA lt_status TYPE /cod1/if_idoc_types=>tt_status.
    TRY.
        DATA(ls_detail) = mo_facade->get_detail( iv_docnum ).
      CATCH /cod1/cx_idoc_error INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
        RETURN.
    ENDTRY.
    lt_status = ls_detail-statuses.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_d)
                                CHANGING  t_table      = lt_status ).
        lo_d->get_columns( )->set_optimize( abap_true ).
        lo_d->get_display_settings( )->set_list_header( |IDoc { iv_docnum } - status history| ).
        lo_d->set_screen_popup( start_column = 10 end_column = 110
                                start_line   = 4  end_line   = 22 ).
        lo_d->display( ).
      CATCH cx_salv_msg INTO DATA(lx2).
        MESSAGE lx2->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
