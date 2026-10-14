*&---------------------------------------------------------------------*
*& Include          ZMM_MATERIAL_MAINTENANCE_C02
*&---------------------------------------------------------------------*
*& Class implementations
*&   lcx_error, lcl_log, lcl_mapper, lcl_file_reader, lcl_config,
*&   lcl_class_info, lcl_material_bapi, lcl_output, lcl_template,
*&   lcl_screen, lcl_app
*&---------------------------------------------------------------------*

CLASS lcx_error IMPLEMENTATION.
  METHOD constructor.
    "Store the message text of the exception.
    super->constructor( ).
    mv_text = iv_text.
  ENDMETHOD.
  METHOD get_text.
    "Return the stored message text.
    result = mv_text.
  ENDMETHOD.
ENDCLASS.

*======================================================================*
* LCL_LOG
*======================================================================*
CLASS lcl_log IMPLEMENTATION.

  METHOD add.
    "Add a message to the log (= output list). The type gives the traffic-light icon,
    "the org. keys are taken from the template row; a message that already exists
    "for the same row, type, field and text is not added again.
    DATA(ls_msg) = VALUE ty_msg(
      icon  = SWITCH #( iv_type WHEN 'E' OR 'A' THEN icon_red_light
                                WHEN 'W'        THEN icon_yellow_light
                                ELSE                 icon_green_light )
      msgty = COND #( WHEN iv_type = 'A' THEN 'E' ELSE iv_type )
      row   = is_row-row
      werks = is_row-werks
      vkorg = is_row-vkorg
      vtweg = is_row-vtweg
      view  = iv_view
      field = iv_field
      fdesc = iv_fdesc
      text  = iv_text ).

    ls_msg-matnr = COND #( WHEN iv_matnr IS NOT INITIAL THEN iv_matnr
                           WHEN lcl_mapper=>is_dummy_key( is_row-matkey ) = abap_false
                           THEN is_row-matkey ).

    "no duplicates (same field can be maintained in several view tables)
    IF line_exists( mt_msg[ KEY k_dup COMPONENTS row   = ls_msg-row   msgty = ls_msg-msgty
                                                 field = ls_msg-field text  = ls_msg-text ] ).
      RETURN.
    ENDIF.
    APPEND ls_msg TO mt_msg.
    "counter per type (read by COUNT)
    ASSIGN mt_cnt[ msgty = ls_msg-msgty ] TO FIELD-SYMBOL(<ls_cnt>).
    IF sy-subrc = 0.
      <ls_cnt>-cnt = <ls_cnt>-cnt + 1.
    ELSE.
      INSERT VALUE #( msgty = ls_msg-msgty cnt = 1 ) INTO TABLE mt_cnt.
    ENDIF.
  ENDMETHOD.

  METHOD count.
    "Number of log messages of the given type.
    rv_count = VALUE #( mt_cnt[ msgty = iv_type ]-cnt OPTIONAL ).
  ENDMETHOD.

  METHOD has_error.
    "True if the template row has at least one error message.
    rv_error = COND #( WHEN line_exists( mt_msg[ KEY k_row COMPONENTS row = iv_row msgty = 'E' ] )
                       THEN abap_true ELSE abap_false ).
  ENDMETHOD.

  METHOD has_global_error.
    "True if an error that belongs to no row exists (row 0), e.g. configuration or
    "template errors.
    rv_error = COND #( WHEN line_exists( mt_msg[ KEY k_row COMPONENTS row = 0 msgty = 'E' ] )
                       THEN abap_true ELSE abap_false ).
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_CLASS_INFO - class master for the classification checks
*======================================================================*
CLASS lcl_class_info IMPLEMENTATION.

  METHOD get.
    "Class (KLAH), its characteristics incl. those of superior classes
    "(KSSK / KSML), their format (CABN) and allowed values (CAWN)
    TYPES: BEGIN OF lty_clint,
             clint TYPE klah-clint,
           END OF lty_clint,
           BEGIN OF lty_cabn,
             atinn TYPE cabn-atinn,
             atnam TYPE cabn-atnam,
             atfor TYPE cabn-atfor,
             anzst TYPE cabn-anzst,
             atein TYPE cabn-atein,
             atson TYPE cabn-atson,
             atkle TYPE cabn-atkle,
           END OF lty_cabn,
           BEGIN OF lty_cawn,
             atinn TYPE cawn-atinn,
             atwrt TYPE cawn-atwrt,
           END OF lty_cawn.
    DATA: lt_clint TYPE SORTED TABLE OF lty_clint WITH UNIQUE KEY clint,
          lt_todo  TYPE STANDARD TABLE OF lty_clint WITH EMPTY KEY,
          lt_cabn  TYPE STANDARD TABLE OF lty_cabn WITH EMPTY KEY,
          lt_cawn  TYPE STANDARD TABLE OF lty_cawn WITH EMPTY KEY,
          lv_objek TYPE kssk-objek,
          lv_atwrt TYPE cawn-atwrt,
          ls_char  TYPE ty_charinfo.

    DATA(lv_class) = CONV klah-class( to_upper( iv_class ) ).
    DATA(lv_klart) = CONV klah-klart( iv_klart ).

    READ TABLE mt_buffer INTO rs_info WITH TABLE KEY class = lv_class klart = lv_klart.
    CHECK sy-subrc <> 0.

    rs_info = VALUE #( class = lv_class klart = lv_klart ).
    SELECT SINGLE clint FROM klah INTO @DATA(lv_clint)
      WHERE klart = @lv_klart AND class = @lv_class.
    IF sy-subrc = 0.
      rs_info-exists = abap_true.

      "class + superior classes (their characteristics are inherited)
      INSERT VALUE #( clint = lv_clint ) INTO TABLE lt_clint.
      APPEND VALUE #( clint = lv_clint ) TO lt_todo.
      WHILE lt_todo IS NOT INITIAL.
        lv_objek = lt_todo[ 1 ]-clint.
        DELETE lt_todo INDEX 1.
        SELECT clint FROM kssk INTO TABLE @DATA(lt_sup)
          WHERE objek = @lv_objek AND mafid = 'K' AND klart = @lv_klart AND lkenz = @space.
        LOOP AT lt_sup INTO DATA(ls_sup).
          INSERT VALUE #( clint = ls_sup-clint ) INTO TABLE lt_clint.
          IF sy-subrc = 0.
            APPEND VALUE #( clint = ls_sup-clint ) TO lt_todo.
          ENDIF.
        ENDLOOP.
      ENDWHILE.

      SELECT imerk FROM ksml INTO TABLE @DATA(lt_ksml)
        FOR ALL ENTRIES IN @lt_clint
        WHERE clint = @lt_clint-clint AND lkenz = @space.
      IF lt_ksml IS NOT INITIAL.
        SELECT atinn, atnam, atfor, anzst, atein, atson, atkle FROM cabn
          INTO TABLE @lt_cabn
          FOR ALL ENTRIES IN @lt_ksml
          WHERE atinn = @lt_ksml-imerk AND lkenz = @space.
      ENDIF.
      IF lt_cabn IS NOT INITIAL.
        SELECT atinn, atwrt FROM cawn INTO TABLE @lt_cawn
          FOR ALL ENTRIES IN @lt_cabn
          WHERE atinn = @lt_cabn-atinn AND lkenz = @space.
      ENDIF.

      LOOP AT lt_cabn INTO DATA(ls_cabn).
        CHECK NOT line_exists( rs_info-chars[ atnam = ls_cabn-atnam ] ).  "one entry per characteristic
        ls_char = CORRESPONDING #( ls_cabn ).
        LOOP AT lt_cawn INTO DATA(ls_cawn) WHERE atinn = ls_cabn-atinn.
          lv_atwrt = COND #( WHEN ls_cabn-atkle = abap_true THEN ls_cawn-atwrt
                             ELSE to_upper( ls_cawn-atwrt ) ).
          INSERT lv_atwrt INTO TABLE ls_char-values.
        ENDLOOP.
        INSERT ls_char INTO TABLE rs_info-chars.
      ENDLOOP.
    ENDIF.

    INSERT rs_info INTO TABLE mt_buffer.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_MAPPER - generic, field-symbol based mapping
*======================================================================*
CLASS lcl_mapper IMPLEMENTATION.

  METHOD trim.
    "Remove leading and trailing blanks of any value and return it as string.
    rv_value = iv_value.
    rv_value = replace( val = rv_value pcre = `^\s+|\s+$` with = `` occ = 0 ).
  ENDMETHOD.

  METHOD is_dummy_key.
    "Dummy key = no MATNR in the template (empty) or row number marked with #.
    IF iv_key IS INITIAL.
      rv_dummy = abap_true.
      RETURN.
    ENDIF.
    rv_dummy = COND #( WHEN iv_key(1) = '#' THEN abap_true ELSE abap_false ).
  ENDMETHOD.

  METHOD resolve_param.
    "DDIC structure name -> parameter of BAPI_MATERIAL_SAVEREPLICA
    "(BAPIE1* structures; the BAPI_MARA ... names are accepted as well,
    " their field names are identical)
    CONSTANTS lc_single TYPE string VALUE
      ` HEADDATA CLIENTDATA PLANTDATA FORECASTPARAMETERS PLANNINGDATA STORAGELOCATIONDATA VALUATIONDATA WAREHOUSENUMBERDATA SALESDATA STORAGETYPEDATA CLASSKEY `.

    CONSTANTS lc_single2 TYPE string VALUE
    `PRTDATA EXTENSIONIN FORECASTVALUES UNPLNDCONSUMPTIO TOTALCONSUMPTION RETURNMESSAGES CLIENTDATACWM UNITSOFMEASURECWM VALUATIONDATACWM MATPLSTADATA MARC_APS_EXTDATA DEMAND_PENALTYDATA `.

    CONSTANTS lc_tables TYPE string VALUE
      ` MATERIALDESCRIPTION UNITSOFMEASURE INTERNATIONALARTNOS MATERIALLONGTEXT TAXCLASSIFICATIONS ALLOCVALUESCHAR ALLOCVALUESNUM ALLOCVALUESCURR `.

    CLEAR: ev_param, ev_table.
    DATA(lv_struct) = to_upper( trim( iv_struct ) ).

    ev_param = SWITCH fieldname( lv_struct
                 WHEN 'BAPIE1MATHEAD'              THEN 'HEADDATA'       "SAVEREPLICA
                 WHEN 'BAPIE1MARART'               THEN 'CLIENTDATA'
                 WHEN 'BAPIE1MARCRT'               THEN 'PLANTDATA'
                 WHEN 'BAPIE1MPOPRT'               THEN 'FORECASTPARAMETERS'
                 WHEN 'BAPIE1MPGDRT'               THEN 'PLANNINGDATA'
                 WHEN 'BAPIE1MARDRT'               THEN 'STORAGELOCATIONDATA'
                 WHEN 'BAPIE1MBEWRT'               THEN 'VALUATIONDATA'
                 WHEN 'BAPIE1MLGNRT'               THEN 'WAREHOUSENUMBERDATA'
                 WHEN 'BAPIE1MVKERT'               THEN 'SALESDATA'
                 WHEN 'BAPIE1MLGTRT'               THEN 'STORAGETYPEDATA'
                 WHEN 'BAPIE1MAKTRT'               THEN 'MATERIALDESCRIPTION'
                 WHEN 'BAPIE1MARMRT'               THEN 'UNITSOFMEASURE'
                 WHEN 'BAPIE1MEANRT'               THEN 'INTERNATIONALARTNOS'
                 WHEN 'BAPIE1MLTXRT'               THEN 'MATERIALLONGTEXT'
                 WHEN 'BAPIE1MLANRT'               THEN 'TAXCLASSIFICATIONS'
                 WHEN 'BAPIMATHEAD'                THEN 'HEADDATA'       "SAVEDATA names
                 WHEN 'BAPI_MARA'                  THEN 'CLIENTDATA'
                 WHEN 'BAPI_MARC'                  THEN 'PLANTDATA'
                 WHEN 'BAPI_MPOP'                  THEN 'FORECASTPARAMETERS'
                 WHEN 'BAPI_MPGD'                  THEN 'PLANNINGDATA'
                 WHEN 'BAPI_MARD'                  THEN 'STORAGELOCATIONDATA'
                 WHEN 'BAPI_MBEW'                  THEN 'VALUATIONDATA'
                 WHEN 'BAPI_MLGN'                  THEN 'WAREHOUSENUMBERDATA'
                 WHEN 'BAPI_MVKE'                  THEN 'SALESDATA'
                 WHEN 'BAPI_MLGT'                  THEN 'STORAGETYPEDATA'
                 WHEN 'BAPI_MAKT'                  THEN 'MATERIALDESCRIPTION'
                 WHEN 'BAPI_MARM'                  THEN 'UNITSOFMEASURE'
                 WHEN 'BAPI_MEAN'                  THEN 'INTERNATIONALARTNOS'
                 WHEN 'BAPI_MLTX'                  THEN 'MATERIALLONGTEXT'
                 WHEN 'BAPI_MLAN'                  THEN 'TAXCLASSIFICATIONS'
                 WHEN 'BAPI1003_KEY'               THEN 'CLASSKEY'
                 WHEN 'BAPI1003_ALLOC_VALUES_CHAR' THEN 'ALLOCVALUESCHAR'
                 WHEN 'BAPI1003_ALLOC_VALUES_NUM'  THEN 'ALLOCVALUESNUM'
                 WHEN 'BAPI1003_ALLOC_VALUES_CURR' THEN 'ALLOCVALUESCURR'
                 ELSE lv_struct ).                    "parameter name given directly

    IF lc_tables CS | { ev_param } |.
      ev_table = abap_true.
    ELSEIF lc_single NS | { ev_param } |.
      IF lc_single2 NS | { ev_param } |.
        CLEAR ev_param.
      ENDIF.
      "not supported
    ENDIF.
  ENDMETHOD.

  METHOD target_exists.
    "Check that BAPI parameter and component of a mapping exist in the template
    "structure TY_BAPI (including the fixed components).
    FIELD-SYMBOLS: <lt_tab> TYPE STANDARD TABLE,
                   <ls_str> TYPE any,
                   <lv_cmp> TYPE any.
    DATA ls_probe TYPE ty_bapi.

    IF is_target-table = abap_true.
      ASSIGN COMPONENT is_target-param OF STRUCTURE ls_probe TO <lt_tab>.
      CHECK sy-subrc = 0.
      APPEND INITIAL LINE TO <lt_tab> ASSIGNING <ls_str>.
    ELSE.
      ASSIGN COMPONENT is_target-param OF STRUCTURE ls_probe TO <ls_str>.
      CHECK sy-subrc = 0.
    ENDIF.

    ASSIGN COMPONENT is_target-comp OF STRUCTURE <ls_str> TO <lv_cmp>.
    CHECK sy-subrc = 0.
    LOOP AT is_target-fixed INTO DATA(ls_fixed).
      ASSIGN COMPONENT ls_fixed-comp OF STRUCTURE <ls_str> TO <lv_cmp>.
      CHECK sy-subrc <> 0.
      RETURN.                                         "fixed component unknown
    ENDLOOP.
    rv_exists = abap_true.
  ENDMETHOD.

  METHOD get_line.
    "Line of a TABLES parameter identified by a line key
    FIELD-SYMBOLS: <lt_tab>  TYPE STANDARD TABLE,
                   <ls_line> TYPE any.

    CLEAR er_line.
    ASSIGN COMPONENT iv_param OF STRUCTURE cs_bapi TO <lt_tab>.
    CHECK sy-subrc = 0.

    READ TABLE cs_bapi-line_keys INTO DATA(ls_key)
         WITH KEY param = iv_param key = iv_key.
    IF sy-subrc = 0.
      READ TABLE <lt_tab> ASSIGNING <ls_line> INDEX ls_key-idx.
    ELSE.
      APPEND INITIAL LINE TO <lt_tab> ASSIGNING <ls_line>.
      APPEND VALUE #( param = iv_param key = iv_key idx = lines( <lt_tab> ) )
        TO cs_bapi-line_keys.
    ENDIF.
    er_line = REF #( <ls_line> ).
  ENDMETHOD.

  METHOD map_value.
    "Move one template value into the BAPI structure given by the mapping target.
    "Table parameters: the line is identified by the line key (fixed values and the
    "suffix _n of the column). EV_ERROR is filled if the conversion fails.
    FIELD-SYMBOLS: <ls_tgt> TYPE any,
                   <lv_tgt> TYPE any,
                   <lv_fix> TYPE any.
    DATA: lv_suffix TYPE string,
          lv_key    TYPE string,
          lr_line   TYPE REF TO data,
          lv_value  TYPE string.

    CLEAR ev_error.
    lv_value = iv_value.

    "--- target structure (single parameter or line of a table parameter)
    IF is_target-table = abap_true.
      lv_key = is_target-linekey.
      IF lv_key IS INITIAL.
        "fields ending with _<n> (CHAR_NAME_1 / CHAR_VALUE_1) share line <n>
        FIND PCRE `_(\d+)$` IN iv_field SUBMATCHES lv_suffix.
        lv_key = |{ REDUCE string( INIT k = `` FOR f IN is_target-fixed
                                   NEXT k = |{ k }{ f-comp }={ f-value };| ) }| &&
                 |#{ COND string( WHEN lv_suffix IS INITIAL THEN `1` ELSE lv_suffix ) }|.
      ENDIF.
      get_line( EXPORTING iv_param = is_target-param
                          iv_key   = lv_key
                IMPORTING er_line  = lr_line
                CHANGING  cs_bapi  = cs_bapi ).
      IF lr_line IS BOUND.
        ASSIGN lr_line->* TO <ls_tgt>.
      ENDIF.
    ELSE.
      ASSIGN COMPONENT is_target-param OF STRUCTURE cs_bapi TO <ls_tgt>.
    ENDIF.

    IF <ls_tgt> IS NOT ASSIGNED.
      ev_error = |BAPI parameter { is_target-param } not available|.
      RETURN.
    ENDIF.

    "--- fixed component values (e.g. TEXT_ID=BEST)
    LOOP AT is_target-fixed INTO DATA(ls_fixed).
      ASSIGN COMPONENT ls_fixed-comp OF STRUCTURE <ls_tgt> TO <lv_fix>.
      IF sy-subrc = 0.
        <lv_fix> = ls_fixed-value.
      ENDIF.
    ENDLOOP.

    "--- target field
    ASSIGN COMPONENT is_target-comp OF STRUCTURE <ls_tgt> TO <lv_tgt>.
    IF sy-subrc <> 0.
      ev_error = |Field { is_target-param }-{ is_target-comp } does not exist|.
      RETURN.
    ENDIF.

    "Material long text: one text line only (132 characters)
    IF is_target-param = 'MATERIALLONGTEXT' AND is_target-comp = 'TEXT_LINE' AND
       strlen( lv_value ) > gc_max_longtext.
      ev_error = |Long text has { strlen( lv_value ) } characters - maximum is { gc_max_longtext }|.
      RETURN.
    ENDIF.

    move_value( EXPORTING iv_value  = lv_value
                IMPORTING ev_error  = ev_error
                CHANGING  cv_target = <lv_tgt> ).
  ENDMETHOD.

  METHOD move_value.
    "Type-driven conversion of a template value into a BAPI field
    DATA: ls_dfies TYPE dfies,
          lv_date  TYPE d,
          lv_fm    TYPE rs38l_fnam.

    CLEAR ev_error.
    DATA(lo_elem)  = CAST cl_abap_elemdescr( cl_abap_typedescr=>describe_by_data( cv_target ) ).
    DATA(lv_value) = iv_value.

    TRY.
        CASE lo_elem->type_kind.

          WHEN cl_abap_typedescr=>typekind_string.
            cv_target = lv_value.

          WHEN cl_abap_typedescr=>typekind_date.
            IF lv_value CO '0123456789' AND strlen( lv_value ) <= 5.
              lv_date = '18991230'.                       "Excel serial date
              lv_date = lv_date + CONV i( lv_value ).
            ELSEIF lv_value CO '0123456789' AND strlen( lv_value ) = 8.
              lv_date = lv_value.                         "YYYYMMDD
            ELSE.
              CALL FUNCTION 'CONVERT_DATE_TO_INTERNAL'   "user format
                EXPORTING
                  date_external = lv_value
                IMPORTING
                  date_internal = lv_date
                EXCEPTIONS
                  OTHERS        = 1.
              IF sy-subrc <> 0.
                CLEAR lv_date.
              ENDIF.
            ENDIF.
            IF lv_date IS INITIAL OR CONV i( lv_date ) = 0.
              ev_error = |Invalid date '{ lv_value }'|.
              RETURN.
            ENDIF.
            cv_target = lv_date.

          WHEN cl_abap_typedescr=>typekind_packed OR cl_abap_typedescr=>typekind_int
            OR cl_abap_typedescr=>typekind_int1   OR cl_abap_typedescr=>typekind_int2
            OR cl_abap_typedescr=>typekind_float
            OR cl_abap_typedescr=>typekind_decfloat16
            OR cl_abap_typedescr=>typekind_decfloat34.
            CONDENSE lv_value NO-GAPS.
            IF lv_value CS '.'.
              REPLACE ALL OCCURRENCES OF ',' IN lv_value WITH ''.   "1,234.50
            ELSE.
              REPLACE ALL OCCURRENCES OF ',' IN lv_value WITH '.'.  "12,5
            ENDIF.
            cv_target = lv_value.                         "raises on bad format

          WHEN cl_abap_typedescr=>typekind_char OR cl_abap_typedescr=>typekind_num.
            IF lo_elem->is_ddic_type( ) = abap_true.
              lo_elem->get_ddic_field( RECEIVING p_flddescr = ls_dfies EXCEPTIONS OTHERS = 1 ).
              IF sy-subrc <> 0.
                CLEAR ls_dfies.
              ENDIF.
            ENDIF.

            IF ls_dfies-convexit IS NOT INITIAL.          "ALPHA, MATN1, CUNIT, ISOLA ...
              lv_fm = |CONVERSION_EXIT_{ ls_dfies-convexit }_INPUT|.
              CALL FUNCTION lv_fm
                EXPORTING
                  input         = lv_value
                IMPORTING
                  output        = cv_target
                EXCEPTIONS
                  error_message = 1
                  OTHERS        = 2.
              IF sy-subrc <> 0.
                CLEAR cv_target.
                ev_error = |Value '{ lv_value }' rejected by conversion exit { ls_dfies-convexit }|.
              ENDIF.
              RETURN.
            ENDIF.

            DATA(lv_maxlen) = lo_elem->length / cl_abap_char_utilities=>charsize.
            IF strlen( lv_value ) > lv_maxlen.
              ev_error = |Value '{ lv_value }' exceeds maximum length { lv_maxlen }|.
              RETURN.
            ENDIF.
            IF lo_elem->type_kind = cl_abap_typedescr=>typekind_num AND lv_value CN '0123456789'.
              ev_error = |Value '{ lv_value }' must be numeric|.
              RETURN.
            ENDIF.
            cv_target = lv_value.

          WHEN OTHERS.
            cv_target = lv_value.
        ENDCASE.

      CATCH cx_sy_conversion_error cx_sy_dyn_call_error INTO DATA(lx_conv).
        CLEAR cv_target.
        ev_error = |Invalid value '{ lv_value }': { lx_conv->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.

  METHOD set_x.
    "Same type as data field -> key field (PLANT, SALES_ORG ...): copy value
    "otherwise BAPIUPDATE flag
    IF cl_abap_typedescr=>describe_by_data( cv_x )->absolute_name =
       cl_abap_typedescr=>describe_by_data( iv_value )->absolute_name.
      cv_x = iv_value.
    ELSE.
      cv_x = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD set_all_x.
    "Build X-structure from all filled components of the data structure
    FIELD-SYMBOLS: <lv_data> TYPE any,
                   <lv_x>    TYPE any.
    DATA(lo_x) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( cs_x ) ).
    LOOP AT lo_x->components INTO DATA(ls_comp).
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_data TO <lv_data>.
      CHECK sy-subrc = 0.
      CHECK <lv_data> IS NOT INITIAL.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE cs_x TO <lv_x>.
      CHECK sy-subrc = 0.
      set_x( EXPORTING iv_value = <lv_data> CHANGING cv_x = <lv_x> ).
    ENDLOOP.
  ENDMETHOD.

  METHOD merge_struct.
    "Copy all non-initial components of IS_SRC into CS_TGT
    FIELD-SYMBOLS: <lv_src> TYPE any,
                   <lv_tgt> TYPE any.
    DO.
      ASSIGN COMPONENT sy-index OF STRUCTURE is_src TO <lv_src>.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      CHECK <lv_src> IS NOT INITIAL.
      ASSIGN COMPONENT sy-index OF STRUCTURE cs_tgt TO <lv_tgt>.
      IF sy-subrc = 0.
        <lv_tgt> = <lv_src>.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD append_unique.
    "Append the line unless an identical line exists.
    FIELD-SYMBOLS <ls_line> TYPE any.
    LOOP AT ct_tab ASSIGNING <ls_line>.
      IF <ls_line> = is_line.
        RETURN.
      ENDIF.
    ENDLOOP.
    APPEND is_line TO ct_tab.
  ENDMETHOD.

  METHOD add_line.
    "Add a line to a TABLES parameter of the BAPI call. Lines with the
    "same org. key (e.g. PLANT) are merged, others are appended.
    FIELD-SYMBOLS: <lt_tab>  TYPE STANDARD TABLE,
                   <ls_line> TYPE any,
                   <lv_new>  TYPE any,
                   <lv_old>  TYPE any.
    DATA: lt_keys TYPE string_table,
          lv_same TYPE abap_bool.

    ASSIGN COMPONENT iv_param OF STRUCTURE cs_call TO <lt_tab>.
    CHECK sy-subrc = 0.

    DATA(lv_keys) = SWITCH string( iv_param
      WHEN 'CLIENTDATA'          THEN ``                          "one line per material
      WHEN 'PLANTDATA'           THEN `PLANT`
      WHEN 'FORECASTPARAMETERS'  THEN `PLANT`
      WHEN 'PLANNINGDATA'        THEN `PLANT`
      WHEN 'STORAGELOCATIONDATA' THEN `PLANT STGE_LOC`
      WHEN 'VALUATIONDATA'       THEN `VAL_AREA VAL_TYPE`
      WHEN 'WAREHOUSENUMBERDATA' THEN `WHSE_NO`
      WHEN 'SALESDATA'           THEN `SALES_ORG DISTR_CHAN`
      WHEN 'STORAGETYPEDATA'     THEN `WHSE_NO STGE_TYPE`
      WHEN 'MATERIALDESCRIPTION' THEN `LANGU LANGU_ISO`
      WHEN 'UNITSOFMEASURE'      THEN `ALT_UNIT ALT_UNIT_ISO`
      WHEN 'TAXCLASSIFICATIONS'  THEN `DEPCOUNTRY DEPCOUNTRY_ISO`
      WHEN 'INTERNATIONALARTNOS' THEN `UNIT UNIT_ISO EAN_UPC`
      ELSE `*` ).                                                "append (long texts)

    IF lv_keys = `*`.
      append_unique( EXPORTING is_line = is_line CHANGING ct_tab = <lt_tab> ).
      APPEND VALUE #( param = iv_param idx = lines( <lt_tab> ) row = iv_row ) TO cs_call-origin.
      RETURN.
    ENDIF.

    SPLIT lv_keys AT space INTO TABLE lt_keys.
    LOOP AT <lt_tab> ASSIGNING <ls_line>.
      DATA(lv_idx) = sy-tabix.
      lv_same = abap_true.
      LOOP AT lt_keys INTO DATA(lv_key) WHERE table_line IS NOT INITIAL.
        ASSIGN COMPONENT lv_key OF STRUCTURE is_line TO <lv_new>.
        CHECK sy-subrc = 0.
        ASSIGN COMPONENT lv_key OF STRUCTURE <ls_line> TO <lv_old>.
        CHECK sy-subrc = 0.
        IF <lv_new> <> <lv_old>.
          lv_same = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_same = abap_true.
        merge_struct( EXPORTING is_src = is_line CHANGING cs_tgt = <ls_line> ).
        APPEND VALUE #( param = iv_param idx = lv_idx row = iv_row ) TO cs_call-origin.
        RETURN.
      ENDIF.
    ENDLOOP.

    APPEND is_line TO <lt_tab>.
    APPEND VALUE #( param = iv_param idx = lines( <lt_tab> ) row = iv_row ) TO cs_call-origin.
  ENDMETHOD.

  METHOD set_func.
    "Update BAPI Function
    FIELD-SYMBOLS: <lv_func> TYPE any.

    ASSIGN COMPONENT 'FUNCTION'      OF STRUCTURE cs_line TO <lv_func>.
    IF <lv_func> IS ASSIGNED.
      <lv_func> = iv_function.
    ENDIF.
  ENDMETHOD.

  METHOD set_matnr.
    "MATERIAL (18) and - on S/4HANA - MATERIAL_LONG (40)
    FIELD-SYMBOLS: <lv_short> TYPE any,
                   <lv_long>  TYPE any.
    ASSIGN COMPONENT 'MATERIAL'      OF STRUCTURE cs_line TO <lv_short>.
    ASSIGN COMPONENT 'MATERIAL_LONG' OF STRUCTURE cs_line TO <lv_long>.
    IF <lv_long> IS ASSIGNED.
      <lv_long> = iv_matnr.
      IF <lv_short> IS ASSIGNED.
        IF strlen( iv_matnr ) <= 18.
          <lv_short> = iv_matnr.
        ELSE.
          CLEAR <lv_short>.
        ENDIF.
      ENDIF.
    ELSEIF <lv_short> IS ASSIGNED.
      <lv_short> = iv_matnr.
    ENDIF.
  ENDMETHOD.

  METHOD set_material_all.
    "Material number + function in every line of every TABLES parameter
    "Create: INS / Update: UPD / Extend: INS for new org. levels, else UPD
    FIELD-SYMBOLS: <lt_tab>  TYPE STANDARD TABLE,
                   <ls_line> TYPE any.

    DATA(lv_opid) = lcl_screen=>get_operation( ).

    DATA(lo_call) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( cs_call ) ).
    LOOP AT lo_call->components INTO DATA(ls_comp) WHERE type_kind = cl_abap_typedescr=>typekind_table.
      CHECK ls_comp-name <> 'ORIGIN'.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE cs_call TO <lt_tab>.
      CHECK sy-subrc = 0.
      LOOP AT <lt_tab> ASSIGNING <ls_line>.
        set_matnr( EXPORTING iv_matnr = iv_matnr CHANGING cs_line = <ls_line> ).

        DATA(lv_func) = SWITCH bapifn( lv_opid
                          WHEN gc_op-create THEN 'INS'
                          WHEN gc_op-update THEN 'UPD'
                          ELSE extend_func( iv_param = CONV #( ls_comp-name )
                                            iv_matnr = iv_matnr
                                            is_line  = <ls_line> ) ).
        set_func( EXPORTING iv_function = lv_func CHANGING cs_line = <ls_line> ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD extend_func.
    "Extend: org. level not yet maintained for the material -> INS,
    "existing data (client level, existing org. levels) -> UPD
    FIELD-SYMBOLS: <lv_k1> TYPE any,
                   <lv_k2> TYPE any.
    DATA lv_dummy TYPE matnr.

    rv_func = 'UPD'.

    CASE iv_param.
      WHEN 'PLANTDATA' OR 'FORECASTPARAMETERS' OR 'PLANNINGDATA'.
        ASSIGN COMPONENT 'PLANT' OF STRUCTURE is_line TO <lv_k1>.
        CHECK sy-subrc = 0.
        SELECT SINGLE matnr FROM marc INTO @lv_dummy
          WHERE matnr = @iv_matnr AND werks = @<lv_k1>.

      WHEN 'STORAGELOCATIONDATA'.
        ASSIGN COMPONENT 'PLANT'    OF STRUCTURE is_line TO <lv_k1>.
        ASSIGN COMPONENT 'STGE_LOC' OF STRUCTURE is_line TO <lv_k2>.
        CHECK <lv_k1> IS ASSIGNED AND <lv_k2> IS ASSIGNED.
        SELECT SINGLE matnr FROM mard INTO @lv_dummy
          WHERE matnr = @iv_matnr AND werks = @<lv_k1> AND lgort = @<lv_k2>.

      WHEN 'VALUATIONDATA'.
        ASSIGN COMPONENT 'VAL_AREA' OF STRUCTURE is_line TO <lv_k1>.
        ASSIGN COMPONENT 'VAL_TYPE' OF STRUCTURE is_line TO <lv_k2>.
        CHECK <lv_k1> IS ASSIGNED AND <lv_k2> IS ASSIGNED.
        SELECT SINGLE matnr FROM mbew INTO @lv_dummy
          WHERE matnr = @iv_matnr AND bwkey = @<lv_k1> AND bwtar = @<lv_k2>.

      WHEN 'SALESDATA'.
        ASSIGN COMPONENT 'SALES_ORG'  OF STRUCTURE is_line TO <lv_k1>.
        ASSIGN COMPONENT 'DISTR_CHAN' OF STRUCTURE is_line TO <lv_k2>.
        CHECK <lv_k1> IS ASSIGNED AND <lv_k2> IS ASSIGNED.
        SELECT SINGLE matnr FROM mvke INTO @lv_dummy
          WHERE matnr = @iv_matnr AND vkorg = @<lv_k1> AND vtweg = @<lv_k2>.

      WHEN 'WAREHOUSENUMBERDATA'.
        ASSIGN COMPONENT 'WHSE_NO' OF STRUCTURE is_line TO <lv_k1>.
        CHECK sy-subrc = 0.
        SELECT SINGLE matnr FROM mlgn INTO @lv_dummy
          WHERE matnr = @iv_matnr AND lgnum = @<lv_k1>.

      WHEN 'STORAGETYPEDATA'.
        ASSIGN COMPONENT 'WHSE_NO'   OF STRUCTURE is_line TO <lv_k1>.
        ASSIGN COMPONENT 'STGE_TYPE' OF STRUCTURE is_line TO <lv_k2>.
        CHECK <lv_k1> IS ASSIGNED AND <lv_k2> IS ASSIGNED.
        SELECT SINGLE matnr FROM mlgt INTO @lv_dummy
          WHERE matnr = @iv_matnr AND lgnum = @<lv_k1> AND lgtyp = @<lv_k2>.

      WHEN 'TAXCLASSIFICATIONS'.
        ASSIGN COMPONENT 'DEPCOUNTRY' OF STRUCTURE is_line TO <lv_k1>.
        CHECK sy-subrc = 0.
        SELECT SINGLE matnr FROM mlan INTO @lv_dummy
          WHERE matnr = @iv_matnr AND aland = @<lv_k1>.

      WHEN OTHERS.
        RETURN.                                       "client-level data
    ENDCASE.

    IF sy-subrc <> 0.
      rv_func = 'INS'.                                "new org. level
    ENDIF.
  ENDMETHOD.

  METHOD build_x_tables.
    "For each parameter with an X counterpart (PLANTDATA -> PLANTDATAX ...)
    "one X line per data line: key fields copied, other filled fields = 'X'
    FIELD-SYMBOLS: <lt_data> TYPE STANDARD TABLE,
                   <lt_x>    TYPE STANDARD TABLE,
                   <ls_data> TYPE any,
                   <ls_x>    TYPE any.
    DATA(lo_call) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( cs_call ) ).
    LOOP AT lo_call->components INTO DATA(ls_comp) WHERE type_kind = cl_abap_typedescr=>typekind_table.
      DATA(lv_xname) = |{ ls_comp-name }X|.
      ASSIGN COMPONENT lv_xname OF STRUCTURE cs_call TO <lt_x>.
      CHECK sy-subrc = 0.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE cs_call TO <lt_data>.
      CHECK sy-subrc = 0.
      CLEAR <lt_x>.
      LOOP AT <lt_data> ASSIGNING <ls_data>.
        APPEND INITIAL LINE TO <lt_x> ASSIGNING <ls_x>.
        set_all_x( EXPORTING is_data = <ls_data> CHANGING cs_x = <ls_x> ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_default.
    "Set component if it exists and is still initial
    FIELD-SYMBOLS <lv_comp> TYPE any.
    ASSIGN COMPONENT iv_comp OF STRUCTURE cs_line TO <lv_comp>.
    IF sy-subrc = 0 AND <lv_comp> IS INITIAL.
      <lv_comp> = iv_value.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_FILE_READER - .xlsx / .csv
*======================================================================*
CLASS lcl_file_reader IMPLEMENTATION.

  METHOD get_extension.
    "File extension in lower case (xlsx / csv).
    DATA(lv_file) = to_lower( iv_file ).
    FIND PCRE `\.([a-z0-9]+)$` IN lv_file SUBMATCHES rv_ext.
  ENDMETHOD.

  METHOD read.
    "Read the template file from the PC or the application server and return the
    "rows as raw string table. Supported: .xlsx and .csv.
    CASE get_extension( iv_file ).
      WHEN 'xlsx'.
        rt_raw = parse_xlsx( iv_xdata = read_binary( iv_file = iv_file iv_server = iv_server )
                             iv_file  = iv_file ).
      WHEN 'csv'.
        rt_raw = parse_csv( read_text_lines( iv_file = iv_file iv_server = iv_server ) ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = |File { iv_file } not supported - only .xlsx and .csv files are allowed|.
    ENDCASE.

    IF lines( rt_raw ) < gc_data_row.
      RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = 'Template contains no data rows'.
    ENDIF.
  ENDMETHOD.

  METHOD read_binary.
    "Read a file as xstring from the PC (GUI) or the application server.
    "A local file can not be read in background.
    IF iv_server = abap_false.
      IF sy-batch = abap_true.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = 'Local file cannot be read in background - use application server'.
      ENDIF.
      DATA: lt_bin TYPE solix_tab,
            lv_len TYPE i.
      cl_gui_frontend_services=>gui_upload(
        EXPORTING  filename   = iv_file
                   filetype   = 'BIN'
        IMPORTING  filelength = lv_len
        CHANGING   data_tab   = lt_bin
        EXCEPTIONS OTHERS     = 1 ).
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = |Error uploading file { iv_file }|.
      ENDIF.
      rv_xdata = cl_bcs_convert=>solix_to_xstring( it_solix = lt_bin iv_size = lv_len ).
    ELSE.
      TRY.
          OPEN DATASET iv_file FOR INPUT IN BINARY MODE.
          IF sy-subrc <> 0.
            RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = |Cannot open file { iv_file }|.
          ENDIF.
          READ DATASET iv_file INTO rv_xdata.
          CLOSE DATASET iv_file.
        CATCH cx_sy_file_open cx_sy_file_authority cx_sy_file_io INTO DATA(lx_file).
          RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = lx_file->get_text( ).
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  METHOD read_text_lines.
    "Read a text file line by line from the PC (GUI) or the application server.
    DATA lv_line TYPE string.

    IF iv_server = abap_false.
      IF sy-batch = abap_true.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = 'Local file cannot be read in background - use application server'.
      ENDIF.
      cl_gui_frontend_services=>gui_upload(
        EXPORTING  filename = iv_file
                   filetype = 'ASC'
        CHANGING   data_tab = rt_lines
        EXCEPTIONS OTHERS   = 1 ).
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = |Error uploading file { iv_file }|.
      ENDIF.
    ELSE.
      TRY.
          OPEN DATASET iv_file FOR INPUT IN TEXT MODE ENCODING DEFAULT.
*                                   SKIPPING BYTE-ORDER MARK.
          IF sy-subrc <> 0.
            RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = |Cannot open file { iv_file }|.
          ENDIF.
          DO.
            READ DATASET iv_file INTO lv_line.
            IF sy-subrc <> 0.
              EXIT.
            ENDIF.
            APPEND lv_line TO rt_lines.
          ENDDO.
          CLOSE DATASET iv_file.
        CATCH cx_sy_file_open cx_sy_file_authority cx_sy_file_io
              cx_sy_conversion_codepage INTO DATA(lx_file).
          RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = lx_file->get_text( ).
      ENDTRY.
    ENDIF.

    "Remove UTF-8 BOM and CR
    IF rt_lines IS NOT INITIAL.
      ASSIGN rt_lines[ 1 ] TO FIELD-SYMBOL(<lv_first>).
      REPLACE ALL OCCURRENCES OF cl_abap_conv_in_ce=>uccp( 'FEFF' ) IN <lv_first> WITH ``.
    ENDIF.
    LOOP AT rt_lines ASSIGNING FIELD-SYMBOL(<lv_line>).
      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf(1) IN <lv_line> WITH ``.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_xlsx.
    "Convert the content of an .xlsx file to raw rows (CL_FDT_XL_SPREADSHEET).
    FIELD-SYMBOLS: <lt_ws>   TYPE STANDARD TABLE,
                   <ls_line> TYPE any,
                   <lv_cell> TYPE any.
    DATA: lo_xl     TYPE REF TO cl_fdt_xl_spreadsheet,
          lt_values TYPE string_table.

    TRY.
        lo_xl = NEW #( document_name = iv_file xdocument = iv_xdata ).
      CATCH cx_fdt_excel_core INTO DATA(lx_xl).
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = |File is not a valid XLSX file: { lx_xl->get_text( ) }|.
    ENDTRY.

    lo_xl->if_fdt_doc_spreadsheet~get_worksheet_names( IMPORTING worksheet_names = DATA(lt_ws) ).
    IF lt_ws IS INITIAL.
      RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = 'XLSX file contains no worksheet'.
    ENDIF.

    "Template = first worksheet
    DATA(lr_data) = lo_xl->if_fdt_doc_spreadsheet~get_itab_from_worksheet( lt_ws[ 1 ] ).
    ASSIGN lr_data->* TO <lt_ws>.
    CHECK sy-subrc = 0.

    LOOP AT <lt_ws> ASSIGNING <ls_line>.
      CLEAR lt_values.
      DO.
        ASSIGN COMPONENT sy-index OF STRUCTURE <ls_line> TO <lv_cell>.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        APPEND CONV string( <lv_cell> ) TO lt_values.
      ENDDO.
      APPEND lt_values TO rt_raw.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_csv.
    "Convert the lines of a .csv file to raw rows. The separator is detected in the
    "header line (; , or TAB).
    CHECK it_lines IS NOT INITIAL.

    "Separator = most frequent of ; , TAB in the header line
    DATA(lv_hdr)   = it_lines[ 1 ].
    DATA(lv_tab)   = CONV string( cl_abap_char_utilities=>horizontal_tab ).
    DATA(lv_semi)  = count( val = lv_hdr sub = `;` ).
    DATA(lv_comma) = count( val = lv_hdr sub = `,` ).
    DATA(lv_tabs)  = count( val = lv_hdr sub = lv_tab ).
    DATA(lv_sep)   = COND string( WHEN lv_tabs > lv_semi AND lv_tabs > lv_comma THEN lv_tab
                                  WHEN lv_semi > lv_comma                     THEN `;`
                                  ELSE                                             `,` ).

    LOOP AT it_lines INTO DATA(lv_line).
      APPEND split_csv_line( iv_line = lv_line iv_sep = lv_sep ) TO rt_raw.
    ENDLOOP.
  ENDMETHOD.

  METHOD split_csv_line.
    "CSV with quoted fields ("a;b" and "" as escaped quote)
    DATA: lv_field  TYPE string,
          lv_quoted TYPE abap_bool,
          lv_pos    TYPE i.

    DATA(lv_len) = strlen( iv_line ).
    WHILE lv_pos < lv_len.
      DATA(lv_char) = substring( val = iv_line off = lv_pos len = 1 ).
      IF lv_quoted = abap_true.
        IF lv_char = `"`.
          DATA(lv_next) = lv_pos + 1.
          IF lv_next < lv_len AND substring( val = iv_line off = lv_next len = 1 ) = `"`.
            lv_field = lv_field && `"`.
            lv_pos = lv_pos + 1.
          ELSE.
            lv_quoted = abap_false.
          ENDIF.
        ELSE.
          lv_field = lv_field && lv_char.
        ENDIF.
      ELSEIF lv_char = `"`.
        lv_quoted = abap_true.
      ELSEIF lv_char = iv_sep.
        APPEND lv_field TO rt_fields.
        CLEAR lv_field.
      ELSE.
        lv_field = lv_field && lv_char.
      ENDIF.
      lv_pos = lv_pos + 1.
    ENDWHILE.
    APPEND lv_field TO rt_fields.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_CONFIG - variant, field catalogue, conditional mandatory rules
*======================================================================*
CLASS lcl_config IMPLEMENTATION.

  METHOD view_tables.
    "View table per selection-screen checkbox
    rt_tab = VALUE #( ( view = gc_view-basic  tabname = 'ZTMM_BASIC_DATA'  active = p_basic )
                      ( view = gc_view-class  tabname = 'ZTMM_CLASS_DATA'  active = p_class )
                      ( view = gc_view-purch  tabname = 'ZTMM_PURCH_DATA'  active = p_purch )
                      ( view = gc_view-mrp    tabname = 'ZTMM_MRP_DATA'    active = p_mrp )
                      ( view = gc_view-frcst  tabname = 'ZTMM_FRCST_DATA'  active = p_frcst )
                      ( view = gc_view-plntst tabname = 'ZTMM_PLNTST_DATA' active = p_plntst )
                      ( view = gc_view-sales  tabname = 'ZTMM_SALES_DATA'  active = p_sales )
                      ( view = gc_view-val    tabname = 'ZTMM_VAL_DATA'    active = p_val ) ).
  ENDMETHOD.

  METHOD control_columns.
    "Template columns that steer processing (not in the view tables)
    rt_cols = VALUE #( ( gc_col-action )     ( gc_col-message )    ( gc_col-profile )
                       ( gc_col-ref_matnr )  ( gc_col-ref_werks )  ( gc_col-ref_lgort )
                       ( gc_col-ref_vkorg )  ( gc_col-ref_vtweg )  ( gc_col-ref_ekorg )
                       ( gc_col-def_mode )
                       ( gc_col-copy_basic ) ( gc_col-copy_purch ) ( gc_col-copy_mrp ) ( gc_col-copy_frcst )
                       ( gc_col-copy_sales ) ( gc_col-copy_acct )  ( gc_col-copy_class )
                       ( gc_col-sales_text ) ).
  ENDMETHOD.

  METHOD constructor.
    "Keep the log for the messages of the configuration.
    mo_log = io_log.
  ENDMETHOD.

  METHOD load.
    "Load the configuration: active variant, field catalogue of the selected view
    "tables, conditional mandatory rules and default values.
    get_variant( ).        "5.2
    get_fields( ).         "5.3 / 5.4
    get_cond_rules( ).
    get_defaults( ).       "default values
  ENDMETHOD.

  METHOD get_variant.
    "Active variant (ZTMM_MATMAS_MAST) for material type, industry sector, business
    "profile and operation selected on the screen. No variant = error.
    DATA(lv_opid) = lcl_screen=>get_operation( ).

    SELECT * FROM ztmm_matmas_mast
      INTO TABLE @DATA(lt_mast)
      WHERE mat_type     = @p_mtart
        AND ind_sec      = @p_indsec
        AND bus_prof     = @p_busprf
        AND operation_id = @lv_opid
        AND active_flag  = @abap_true
        AND valid_from  <= @sy-datum
        AND ( valid_to  >= @sy-datum OR valid_to = '00000000' ).

    IF lt_mast IS INITIAL.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING
          iv_text = |No active variant in ZTMM_MATMAS_MAST for { p_mtart } / { p_indsec } / | &&
                    |{ p_busprf } / operation { lv_opid }|.
    ENDIF.

    SORT lt_mast BY valid_from DESCENDING.
    mv_variant = lt_mast[ 1 ]-variant_view.

    mo_log->add( iv_type = 'S' iv_text = |Active variant { mv_variant } determined| ).
  ENDMETHOD.

  METHOD get_fields.
    "Field catalogue: read the view tables (ZTMM_*_DATA) of the selected views for
    "the active variant and parse the BAPI mapping of each field.
    DATA lt_db TYPE STANDARD TABLE OF ztmm_basic_data WITH EMPTY KEY.

    CLEAR mt_fcat.
    DATA(lt_views) = view_tables( ).

    LOOP AT lt_views INTO DATA(ls_view) WHERE active = abap_true.
      CLEAR lt_db.
      TRY.
          "all view tables have the same structure -> dynamic table name
          SELECT * FROM (ls_view-tabname)
            INTO CORRESPONDING FIELDS OF TABLE @lt_db
            WHERE variant_view = @mv_variant.
        CATCH cx_sy_dynamic_osql_error INTO DATA(lx_sql).
          mo_log->add( iv_type = 'E' iv_text = |{ ls_view-tabname }: { lx_sql->get_text( ) }| ).
          CONTINUE.
      ENDTRY.

      IF lt_db IS INITIAL.
        mo_log->add( iv_type = 'W' iv_view = ls_view-view
                     iv_text = |No fields maintained in { ls_view-tabname } for variant { mv_variant }| ).
        CONTINUE.
      ENDIF.

      LOOP AT lt_db INTO DATA(ls_db).
        DATA(ls_fcat) = CORRESPONDING ty_fcat( ls_db ).
        ls_fcat-temp_field_name = to_upper( lcl_mapper=>trim( ls_fcat-temp_field_name ) ).
        ls_fcat-view            = ls_view-view.
        ls_fcat-targets         = parse_targets( ls_fcat ).
        APPEND ls_fcat TO mt_fcat.
      ENDLOOP.
    ENDLOOP.

    IF mt_fcat IS INITIAL.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING
          iv_text = |No field configuration found for variant { mv_variant } and the selected views|.
    ENDIF.
  ENDMETHOD.

  METHOD get_defaults.
    "Default values of the template fields for the screen selection
    "(material type, business profile) and the active variant view
    CLEAR mt_deflt.
    SELECT * FROM ztmm_deflt_data
      INTO TABLE @mt_deflt
      WHERE mtart        = @p_mtart
        AND bus_prof     = @p_busprf
        AND variant_view = @mv_variant.
    LOOP AT mt_deflt ASSIGNING FIELD-SYMBOL(<ls_def>).
      <ls_def>-temp_field_name = to_upper( lcl_mapper=>trim( <ls_def>-temp_field_name ) ).
    ENDLOOP.
    mo_log->add( iv_type = 'S'
                 iv_text = |{ lines( mt_deflt ) } default value(s) read from ZTMM_DEFLT_DATA| ).
  ENDMETHOD.

  METHOD get_cond_rules.
    "Conditional mandatory rules (ZTMM_COND_MAND) of the active variant.
    SELECT * FROM ztmm_cond_mand
      INTO TABLE @mt_cond
      WHERE mat_type     = @p_mtart
        AND ind_sec      = @p_indsec
        AND bus_prof     = @p_busprf
        AND variant_view = @mv_variant.

    LOOP AT mt_cond ASSIGNING FIELD-SYMBOL(<ls_cond>).
      <ls_cond>-source_field  = to_upper( lcl_mapper=>trim( <ls_cond>-source_field ) ).
      <ls_cond>-condmat_field = to_upper( lcl_mapper=>trim( <ls_cond>-condmat_field ) ).
    ENDLOOP.

    LOOP AT mt_fcat INTO DATA(ls_fcat) WHERE cond_mandatory = abap_true.
      IF NOT line_exists( mt_cond[ source_field = ls_fcat-temp_field_name ] ).
        mo_log->add( iv_type = 'W' iv_view = ls_fcat-view iv_field = ls_fcat-temp_field_name
                     iv_fdesc = ls_fcat-description
                     iv_text = 'Conditional mandatory, but no rule maintained in ZTMM_COND_MAND' ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_targets.
    "BAPI_FIELD_NAME: target{,target}  target = [STRUCT-]FIELD{;QUAL=VALUE}
    DATA: lt_parts  TYPE string_table,
          lt_quals  TYPE string_table,
          lv_struct TYPE string,
          lv_comp   TYPE string.

    DATA(lv_def)     = to_upper( condense( val = CONV string( is_fcat-bapi_field_name )
                                           from = ` ` to = `` ) ).
    DATA(lv_def_str) = to_upper( lcl_mapper=>trim( is_fcat-bapi_struct_name ) ).

    IF ( is_fcat-mandatory = 'X' AND ( lv_def IS INITIAL OR lv_def_str IS INITIAL ) ).

      mo_log->add( iv_type = 'E'
                   iv_view = is_fcat-view
                   iv_field = is_fcat-temp_field_name
                   iv_fdesc = is_fcat-description
                   iv_text = 'No BAPI field/Structure maintained for mandatory field' ).
      RETURN.
    ENDIF.

    IF lv_def IS INITIAL.
      IF is_fcat-system_derived = abap_false.
      ENDIF.
      RETURN.
    ENDIF.

    SPLIT lv_def AT ',' INTO TABLE lt_parts.
    LOOP AT lt_parts INTO DATA(lv_part).
      SPLIT lv_part AT ';' INTO TABLE lt_quals.
      CHECK lt_quals IS NOT INITIAL.
      DATA(lv_tgt) = lt_quals[ 1 ].
      DELETE lt_quals INDEX 1.

      lv_struct = lv_def_str.
      lv_comp   = lv_tgt.
      IF lv_tgt CS '-'.
        SPLIT lv_tgt AT '-' INTO lv_struct lv_comp.
      ENDIF.

      DATA(ls_target) = VALUE ty_target( comp = lv_comp ).
      lcl_mapper=>resolve_param( EXPORTING iv_struct = lv_struct
                                 IMPORTING ev_param  = ls_target-param
                                           ev_table  = ls_target-table ).
      IF ls_target-param IS INITIAL.
        mo_log->add( iv_type = 'W' iv_view = is_fcat-view iv_field = is_fcat-temp_field_name
                     iv_fdesc = is_fcat-description
                     iv_text = |BAPI structure { lv_struct } not supported - target { lv_tgt } ignored| ).
        CONTINUE.
      ENDIF.

      LOOP AT lt_quals INTO DATA(lv_qual).
        SPLIT lv_qual AT '=' INTO DATA(lv_qkey) DATA(lv_qval).
        IF lv_qkey = 'LINE'.
          ls_target-linekey = lv_qval.
        ELSE.
          APPEND VALUE #( comp = lv_qkey value = lv_qval ) TO ls_target-fixed.
        ENDIF.
      ENDLOOP.

      IF lcl_mapper=>target_exists( ls_target ) = abap_false.
        mo_log->add( iv_type = 'W' iv_view = is_fcat-view iv_field = is_fcat-temp_field_name
                     iv_fdesc = is_fcat-description
                     iv_text = |Field { ls_target-param }-{ ls_target-comp } does not exist - target ignored| ).
        CONTINUE.
      ENDIF.
      APPEND ls_target TO rt_target.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_MATERIAL_BAPI - simulate / post
*======================================================================*
CLASS lcl_material_bapi IMPLEMENTATION.

  METHOD constructor.
    "Keep the log for the messages of the BAPI calls.
    mo_log = io_log.
  ENDMETHOD.

  METHOD get_material_number.
    "Material number of a template row: external number from MATNR or internal
    "number (BAPI_MATERIAL_GETINTNUMBER). Test run without MATNR: temporary number.
    FIELD-SYMBOLS <lv_num> TYPE any.
    DATA: lt_number TYPE STANDARD TABLE OF bapimatinr,
          ls_return TYPE bapireturn1.

    "External number from template
    IF lcl_mapper=>is_dummy_key( is_row-matkey ) = abap_false.
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input  = is_row-matkey
        IMPORTING
          output = rv_matnr
        EXCEPTIONS
          OTHERS = 1.
      IF sy-subrc <> 0.
        CLEAR rv_matnr.
        mo_log->add( iv_type = 'E' is_row = is_row iv_text = 'Invalid material number' ).
      ENDIF.
      RETURN.
    ENDIF.

    "Internal numbering (Create only)
    IF lcl_screen=>get_operation( ) <> gc_op-create.
      mo_log->add( iv_type = 'E' is_row = is_row iv_text = 'MATNR is required for Update / Extend' ).
      RETURN.
    ENDIF.
    IF p_test = abap_true AND lcl_mapper=>is_dummy_key( is_row-matkey ) = abap_true.
      rv_matnr = lcl_template=>get_temp_matnr( is_row ).
    ELSE.
      CALL FUNCTION 'BAPI_MATERIAL_GETINTNUMBER'
        EXPORTING
          material_type    = p_mtart
          industry_sector  = p_indsec
          required_numbers = 1
        IMPORTING
          return           = ls_return
        TABLES
          material_number  = lt_number.
      IF ls_return-type CA 'EA' OR lt_number IS INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row
                     iv_text = |Internal material number not assigned: { ls_return-message }| ).
        RETURN.
      ENDIF.

      READ TABLE lt_number INTO DATA(ls_number) INDEX 1.
      ASSIGN COMPONENT 'MATERIAL_LONG' OF STRUCTURE ls_number TO <lv_num>.   "S/4HANA
      IF sy-subrc <> 0 OR <lv_num> IS INITIAL.
        ASSIGN COMPONENT 'MATERIAL' OF STRUCTURE ls_number TO <lv_num>.
      ENDIF.
      rv_matnr = <lv_num>.
      mo_log->add( iv_type = 'S' is_row = is_row iv_matnr = rv_matnr
                   iv_text = |Internal material number { rv_matnr ALPHA = OUT } assigned| ).
    ENDIF.
  ENDMETHOD.

  METHOD get_reference.
    "Read reference material via BAPI_MATERIAL_GET_ALL - called dynamically
    "so that the report also activates on releases without this BAPI
    TYPES: BEGIN OF lty_reftab,
             param TYPE fieldname,
             data  TYPE REF TO data,
           END OF lty_reftab.
    CONSTANTS lc_ref_tables TYPE string VALUE
      ` MATERIALDESCRIPTION UNITSOFMEASURE MATERIALLONGTEXT TAXCLASSIFICATIONS `.
    FIELD-SYMBOLS: <ls_ga>  TYPE any,
                   <lt_src> TYPE STANDARD TABLE,
                   <lt_tgt> TYPE STANDARD TABLE,
                   <ls_src> TYPE any,
                   <ls_tgt> TYPE any.
    DATA: lt_ptab   TYPE abap_func_parmbind_tab,
          lt_return TYPE STANDARD TABLE OF bapiret2,
          lt_reftab TYPE STANDARD TABLE OF lty_reftab WITH EMPTY KEY,
          lr_mara   TYPE REF TO data,
          lr_marc   TYPE REF TO data,
          lr_mpop   TYPE REF TO data,
          lr_mpgd   TYPE REF TO data,
          lr_mbew   TYPE REF TO data,
          lr_mvke   TYPE REF TO data,
          lr_tab    TYPE REF TO data,
          lv_mat18  TYPE c LENGTH 18,
          lv_mat40  TYPE c LENGTH 40,
          lv_bwkey  TYPE bwkey.

    DATA(lv_key) = |{ iv_matnr }/{ iv_werks }/{ iv_vkorg }/{ iv_vtweg }/{ iv_bwkey }|.
    READ TABLE mt_cache INTO DATA(ls_cache) WITH KEY key = lv_key.
    IF sy-subrc = 0.
      rs_ref = ls_cache-data.
      RETURN.
    ENDIF.

    TRY.
        CREATE DATA lr_mara TYPE ('BAPI_MARA_GA').
        CREATE DATA lr_marc TYPE ('BAPI_MARC_GA').
        CREATE DATA lr_mpop TYPE ('BAPI_MPOP_GA').
        CREATE DATA lr_mpgd TYPE ('BAPI_MPGD_GA').
        CREATE DATA lr_mbew TYPE ('BAPI_MBEW_GA').
        CREATE DATA lr_mvke TYPE ('BAPI_MVKE_GA').
      CATCH cx_sy_create_data_error.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = 'Reference copy not supported in this release (BAPI_MATERIAL_GET_ALL)'.
    ENDTRY.

    "S/4HANA: 40-char material number in MATERIAL_LONG
    cl_abap_typedescr=>describe_by_name( EXPORTING  p_name      = 'BAPIMATALL-MATERIAL_LONG'
                                         EXCEPTIONS type_not_found = 1
                                                    OTHERS         = 2 ).
    IF sy-subrc = 0.
      lv_mat40 = iv_matnr.
      INSERT VALUE #( name = 'MATERIAL_LONG' kind = abap_func_exporting value = REF #( lv_mat40 ) ) INTO TABLE lt_ptab.
    ELSE.
      lv_mat18 = iv_matnr.
      INSERT VALUE #( name = 'MATERIAL'      kind = abap_func_exporting value = REF #( lv_mat18 ) ) INTO TABLE lt_ptab.
    ENDIF.

    DATA(lv_werks) = iv_werks.
    DATA(lv_vkorg) = iv_vkorg.
    DATA(lv_vtweg) = iv_vtweg.
    lv_bwkey = iv_bwkey.
    IF lv_werks IS NOT INITIAL.
      INSERT VALUE #( name = 'PLANT'      kind = abap_func_exporting value = REF #( lv_werks ) ) INTO TABLE lt_ptab.
    ENDIF.
    IF lv_bwkey IS NOT INITIAL.
      INSERT VALUE #( name = 'VAL_AREA'   kind = abap_func_exporting value = REF #( lv_bwkey ) ) INTO TABLE lt_ptab.
    ENDIF.
    IF lv_vkorg IS NOT INITIAL.
      INSERT VALUE #( name = 'SALESORG'   kind = abap_func_exporting value = REF #( lv_vkorg ) ) INTO TABLE lt_ptab.
      INSERT VALUE #( name = 'DISTR_CHAN' kind = abap_func_exporting value = REF #( lv_vtweg ) ) INTO TABLE lt_ptab.
    ENDIF.
    INSERT VALUE #( name = 'CLIENTDATA'         kind = abap_func_importing value = lr_mara ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'PLANTDATA'          kind = abap_func_importing value = lr_marc ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'FORECASTPARAMETERS' kind = abap_func_importing value = lr_mpop ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'PLANNINGDATA'       kind = abap_func_importing value = lr_mpgd ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'VALUATIONDATA'      kind = abap_func_importing value = lr_mbew ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'SALESDATA'          kind = abap_func_importing value = lr_mvke ) INTO TABLE lt_ptab.
    INSERT VALUE #( name = 'RETURN'             kind = abap_func_tables    value = REF #( lt_return ) ) INTO TABLE lt_ptab.

    "Table parameters (descriptions, units, long texts, tax) - only those
    "that exist in this release, with the line type of the interface
    SELECT parameter, structure FROM fupararef
      INTO TABLE @DATA(lt_fupar)
      WHERE funcname  = 'BAPI_MATERIAL_GET_ALL'
        AND r3state   = 'A'
        AND paramtype = 'T'.
    LOOP AT lt_fupar INTO DATA(ls_fupar).
      CHECK lc_ref_tables CS | { ls_fupar-parameter } |.
      TRY.
          CREATE DATA lr_tab TYPE STANDARD TABLE OF (ls_fupar-structure).
        CATCH cx_sy_create_data_error.
          CONTINUE.
      ENDTRY.
      INSERT VALUE #( name = ls_fupar-parameter kind = abap_func_tables value = lr_tab ) INTO TABLE lt_ptab.
      APPEND VALUE #( param = ls_fupar-parameter data = lr_tab ) TO lt_reftab.
    ENDLOOP.

    TRY.
        CALL FUNCTION 'BAPI_MATERIAL_GET_ALL' PARAMETER-TABLE lt_ptab.
      CATCH cx_sy_dyn_call_error INTO DATA(lx_dyn).
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING
            iv_text = |Reference material could not be read: { lx_dyn->get_text( ) }|.
    ENDTRY.

    LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EA'.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING
          iv_text = |Reference material { iv_matnr ALPHA = OUT }: { ls_ret-message }|.
    ENDLOOP.

    ASSIGN lr_mara->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-clientdata.
    ASSIGN lr_marc->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-plantdata.
    ASSIGN lr_mpop->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-forecastparameters.
    ASSIGN lr_mpgd->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-planningdata.
    ASSIGN lr_mbew->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-valuationdata.
    ASSIGN lr_mvke->* TO <ls_ga>. MOVE-CORRESPONDING <ls_ga> TO rs_ref-salesdata.

    LOOP AT lt_reftab INTO DATA(ls_reftab).
      ASSIGN ls_reftab-data->* TO <lt_src>.
      ASSIGN COMPONENT ls_reftab-param OF STRUCTURE rs_ref TO <lt_tgt>.
      CHECK sy-subrc = 0.
      LOOP AT <lt_src> ASSIGNING <ls_src>.
        APPEND INITIAL LINE TO <lt_tgt> ASSIGNING <ls_tgt>.
        MOVE-CORRESPONDING <ls_src> TO <ls_tgt>.
        "Tax lines: the country is the key of every line (MLAN). If the reference
        "structure names it differently than BAPIE1MLAN (DEPCOUNTRY), MOVE-CORRESPONDING
        "leaves it empty and all lines get the same (empty) key - then only one line
        "is kept. Take the country from the source field whose name says so.
        IF ls_reftab-param = 'TAXCLASSIFICATIONS'.
          DATA(lo_src) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( <ls_src> ) ).
          LOOP AT lo_src->components INTO DATA(ls_scomp).
            DATA(lv_iso) = xsdbool( ls_scomp-name CS 'ISO' ).
            CHECK ls_scomp-name CS 'COUNTR' OR ls_scomp-name = 'ALAND'.
            ASSIGN COMPONENT ls_scomp-name OF STRUCTURE <ls_src> TO FIELD-SYMBOL(<lv_ctry>).
            CHECK sy-subrc = 0 AND <lv_ctry> IS NOT INITIAL.
            DATA(lv_tgt_name) = COND string( WHEN lv_iso = abap_true THEN `DEPCOUNTRY_ISO` ELSE `DEPCOUNTRY` ).
            ASSIGN COMPONENT lv_tgt_name OF STRUCTURE <ls_tgt> TO FIELD-SYMBOL(<lv_ctry_tgt>).
            IF sy-subrc = 0 AND <lv_ctry_tgt> IS INITIAL.
              <lv_ctry_tgt> = <lv_ctry>.
            ENDIF.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    APPEND VALUE #( key = lv_key data = rs_ref ) TO mt_cache.
  ENDMETHOD.

  METHOD save_sales_text.
    "Sales text of a sales area (text object MVKE, ID 0001, name = material +
    "sales org. + distribution channel). Not part of BAPI_MATERIAL_SAVEREPLICA,
    "saved with SAVE_TEXT after the material was posted. Lines of the cell are
    "split at line breaks and at the line length of the text editor (132).
    DATA: ls_header TYPE thead,
          lt_lines  TYPE STANDARD TABLE OF tline WITH EMPTY KEY,
          lv_name   TYPE tdobname,
          lv_rest   TYPE string,
          lv_len    TYPE i,
          lv_dummy  TYPE matnr.

    "Test run: nothing is written (the material may not exist yet)
    IF p_test = abap_true.
      mo_log->add( iv_type = 'S' is_row = is_row iv_matnr = iv_matnr iv_field = gc_col-sales_text
                   iv_text = |Simulation OK - sales text for sales area { is_row-vkorg }/{ is_row-vtweg } | &&
                             |checked, not saved in a test run| ).
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    "The sales area must exist for the material (created by the BAPI or before)
    SELECT SINGLE matnr FROM mvke INTO @lv_dummy
      WHERE matnr = @iv_matnr AND vkorg = @is_row-vkorg AND vtweg = @is_row-vtweg.
    IF sy-subrc <> 0.
      mo_log->add( iv_type = 'E' is_row = is_row iv_matnr = iv_matnr iv_field = gc_col-sales_text
                   iv_text = |Sales text not saved - sales area { is_row-vkorg }/{ is_row-vtweg } | &&
                             |does not exist for the material| ).
      RETURN.
    ENDIF.

    "Text lines: line breaks of the cell, long lines wrapped
    DATA(lv_text) = replace( val = iv_text sub = cl_abap_char_utilities=>cr_lf
                             with = cl_abap_char_utilities=>newline occ = 0 ).
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_split).
    LOOP AT lt_split INTO DATA(lv_line).
      IF lv_line IS INITIAL.
        APPEND VALUE #( tdformat = '*' ) TO lt_lines.
        CONTINUE.
      ENDIF.
      lv_rest = lv_line.
      WHILE lv_rest IS NOT INITIAL.
        lv_len = nmin( val1 = strlen( lv_rest ) val2 = gc_max_longtext ).
        APPEND VALUE #( tdformat = '*' tdline = lv_rest(lv_len) ) TO lt_lines.
        lv_rest = substring( val = lv_rest off = lv_len ).
      ENDWHILE.
    ENDLOOP.

    "Text name = MATNR (field length) + VKORG + VTWEG
    DESCRIBE FIELD iv_matnr LENGTH DATA(lv_mlen) IN CHARACTER MODE.
    lv_name = iv_matnr.
    lv_name+lv_mlen(4) = is_row-vkorg.
    DATA(lv_off) = lv_mlen + 4.
    lv_name+lv_off(2) = is_row-vtweg.

    ls_header = VALUE #( tdobject = gc_stext_object tdname = lv_name
                         tdid = gc_stext_id tdspras = sy-langu ).

    CALL FUNCTION 'SAVE_TEXT'
      EXPORTING
        header          = ls_header
        savemode_direct = abap_true
      TABLES
        lines           = lt_lines
      EXCEPTIONS
        id              = 1
        language        = 2
        name            = 3
        object          = 4
        OTHERS          = 5.
    IF sy-subrc <> 0.
      DATA(lv_subrc) = sy-subrc.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      mo_log->add( iv_type = 'E' is_row = is_row iv_matnr = iv_matnr iv_field = gc_col-sales_text
                   iv_text = |Sales text for sales area { is_row-vkorg }/{ is_row-vtweg } | &&
                             |not saved (SAVE_TEXT subrc { lv_subrc })| ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.
    mo_log->add( iv_type = 'S' is_row = is_row iv_matnr = iv_matnr iv_field = gc_col-sales_text
                 iv_text = |Posted - sales text for sales area { is_row-vkorg }/{ is_row-vtweg } | &&
                           |({ lines( lt_lines ) } line(s))| ).
    rv_ok = abap_true.
  ENDMETHOD.

  METHOD save_material.
    "BAPI_MATERIAL_SAVEREPLICA - one call per material with all org. levels
    "Test run: TESTRUN = 'X' -> complete check without database update
    FIELD-SYMBOLS: <lv_param> TYPE any,
                   <lv_line>  TYPE any.
    DATA: ls_call   TYPE ty_call,
          ls_return TYPE bapiret2,
          lt_retmsg TYPE STANDARD TABLE OF bapie1ret2.

    ls_call = is_call.                          "TABLES parameters must be changeable
    DATA(ls_first) = VALUE ty_row( it_rows[ 1 ] OPTIONAL ).

    CALL FUNCTION 'BAPI_MATERIAL_SAVEREPLICA'
      EXPORTING
        noappllog            = abap_true
        nochangedoc          = abap_false
        testrun              = p_test
        inpfldcheck          = space
      IMPORTING
        return               = ls_return
      TABLES
        headdata             = ls_call-headdata
        clientdata           = ls_call-clientdata
        clientdatax          = ls_call-clientdatax
        plantdata            = ls_call-plantdata
        plantdatax           = ls_call-plantdatax
        forecastparameters   = ls_call-forecastparameters
        forecastparametersx  = ls_call-forecastparametersx
        planningdata         = ls_call-planningdata
        planningdatax        = ls_call-planningdatax
        storagelocationdata  = ls_call-storagelocationdata
        storagelocationdatax = ls_call-storagelocationdatax
        valuationdata        = ls_call-valuationdata
        valuationdatax       = ls_call-valuationdatax
        warehousenumberdata  = ls_call-warehousenumberdata
        warehousenumberdatax = ls_call-warehousenumberdatax
        salesdata            = ls_call-salesdata
        salesdatax           = ls_call-salesdatax
        storagetypedata      = ls_call-storagetypedata
        storagetypedatax     = ls_call-storagetypedatax
        materialdescription  = ls_call-materialdescription
        unitsofmeasure       = ls_call-unitsofmeasure
        unitsofmeasurex      = ls_call-unitsofmeasurex
        internationalartnos  = ls_call-internationalartnos
        materiallongtext     = ls_call-materiallongtext
        taxclassifications   = ls_call-taxclassifications
        prtdata              = ls_call-prtdata
        prtdatax             = ls_call-prtdatax
        extensionin          = ls_call-extensionin
        extensioninx         = ls_call-extensioninx
        forecastvalues       = ls_call-forecastvalues
        unplndconsumption    = ls_call-unplndconsumption
        totalconsumption     = ls_call-totalconsumption
        returnmessages       = lt_retmsg
        clientdatacwm        = ls_call-clientdatacwm
        clientdatacwmx       = ls_call-clientdatacwmx
        unitsofmeasurecwm    = ls_call-unitsofmeasurecwm
        unitsofmeasurecwmx   = ls_call-unitsofmeasurecwmx
        valuationdatacwm     = ls_call-valuationdatacwm
        valuationdatacwmx    = ls_call-valuationdatacwmx
        matplstadata         = ls_call-matplstadata
        matplstadatax        = ls_call-matplstadatax
        marc_aps_extdata     = ls_call-marc_aps_extdata
        marc_aps_extdatax    = ls_call-marc_aps_extdatax
        demand_penaltydata   = ls_call-demand_penaltydata
        demand_penaltydatax  = ls_call-demand_penaltydatax.

    rv_ok = COND #( WHEN ls_return-type CA 'EA' THEN abap_false ELSE abap_true ).

    LOOP AT lt_retmsg ASSIGNING FIELD-SYMBOL(<ls_rm>) WHERE type CA 'EAW'.
      "Template row of the BAPI line the message refers to (PARAMETER / ROW)
      DATA(ls_row) = ls_first.
      ASSIGN COMPONENT 'PARAMETER' OF STRUCTURE <ls_rm> TO <lv_param>.
      IF sy-subrc = 0.
        ASSIGN COMPONENT 'ROW' OF STRUCTURE <ls_rm> TO <lv_line>.
        IF sy-subrc = 0.
          READ TABLE is_call-origin INTO DATA(ls_origin)
               WITH KEY param = to_upper( <lv_param> ) idx = <lv_line>.
          IF sy-subrc = 0.
            ls_row = VALUE #( it_rows[ KEY k_row COMPONENTS row = ls_origin-row ] DEFAULT ls_first ).
          ENDIF.
        ENDIF.
      ENDIF.

      mo_log->add( iv_type  = COND #( WHEN <ls_rm>-type = 'W' THEN 'W' ELSE 'E' )
                   iv_text  = |[{ <ls_rm>-id }/{ <ls_rm>-number }] { <ls_rm>-message }|
                   is_row   = ls_row
                   iv_matnr = iv_matnr ).
      IF <ls_rm>-type CA 'EA'.
        rv_ok = abap_false.
      ENDIF.
    ENDLOOP.

    rv_ok = finish_luw(
      iv_ok    = rv_ok
      iv_what  = |Material ({ lines( is_call-plantdata ) } plant(s), | &&
                 |{ lines( is_call-salesdata ) } sales area(s), | &&
                 |{ lines( is_call-valuationdata ) } valuation area(s))|
      iv_msg   = COND string( WHEN ls_return-message IS INITIAL THEN `processed`
                              ELSE ls_return-message )
      is_row   = ls_first
      iv_matnr = iv_matnr ).
  ENDMETHOD.

  METHOD classify.
    "Assign the material to its class and set the characteristic values
    "(BAPI_OBJCL_CREATE / BAPI_OBJCL_CHANGE). Existing values are kept, values of
    "the template overwrite those of the same characteristic.
    DATA: lv_objkey TYPE bapi1003_key-object,
          lt_char   TYPE STANDARD TABLE OF bapi1003_alloc_values_char,
          lt_num    TYPE STANDARD TABLE OF bapi1003_alloc_values_num,
          lt_curr   TYPE STANDARD TABLE OF bapi1003_alloc_values_curr,
          lt_return TYPE STANDARD TABLE OF bapiret2.

    lv_objkey = iv_matnr.
    DATA(lv_class) = is_class-classkey-classnum.
    DATA(lv_ctype) = COND klassenart( WHEN is_class-classkey-classtype IS INITIAL
                                      THEN gc_def_classtype ELSE is_class-classkey-classtype ).

    "Existing assignment (+ current values, BAPI_OBJCL_CHANGE replaces all values)
    CALL FUNCTION 'BAPI_OBJCL_GETDETAIL'
      EXPORTING
        objectkey       = lv_objkey
        objecttable     = gc_objtab_mara
        classnum        = lv_class
        classtype       = lv_ctype
      TABLES
        allocvaluesnum  = lt_num
        allocvalueschar = lt_char
        allocvaluescurr = lt_curr
        return          = lt_return.
    DATA(lv_exists) = COND abap_bool( WHEN line_exists( lt_return[ type = 'E' ] )
                                      THEN abap_false ELSE abap_true ).

    "Template values overwrite existing values of the same characteristic
    LOOP AT is_class-allocvalueschar INTO DATA(ls_char).
      DELETE lt_char WHERE charact = ls_char-charact.
    ENDLOOP.
    APPEND LINES OF is_class-allocvalueschar TO lt_char.
    LOOP AT is_class-allocvaluesnum INTO DATA(ls_num).
      DELETE lt_num WHERE charact = ls_num-charact.
    ENDLOOP.
    APPEND LINES OF is_class-allocvaluesnum TO lt_num.
    LOOP AT is_class-allocvaluescurr INTO DATA(ls_curr).
      DELETE lt_curr WHERE charact = ls_curr-charact.
    ENDLOOP.
    APPEND LINES OF is_class-allocvaluescurr TO lt_curr.

    sync_long_values( CHANGING ct_char = lt_char ).

    CLEAR lt_return.
    IF lv_exists = abap_true.
      CALL FUNCTION 'BAPI_OBJCL_CHANGE'
        EXPORTING
          objectkey          = lv_objkey
          objecttable        = gc_objtab_mara
          classnum           = lv_class
          classtype          = lv_ctype
          status             = '1'
        TABLES
          allocvaluesnumnew  = lt_num
          allocvaluescharnew = lt_char
          allocvaluescurrnew = lt_curr
          return             = lt_return.
    ELSE.
      CALL FUNCTION 'BAPI_OBJCL_CREATE'
        EXPORTING
          objectkeynew    = lv_objkey
          objecttablenew  = gc_objtab_mara
          classnumnew     = lv_class
          classtypenew    = lv_ctype
          status          = '1'
        TABLES
          allocvaluesnum  = lt_num
          allocvalueschar = lt_char
          allocvaluescurr = lt_curr
          return          = lt_return.
    ENDIF.

    rv_ok = abap_true.
    LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EAW'.
      mo_log->add( iv_type = COND #( WHEN ls_ret-type = 'W' THEN 'W' ELSE 'E' )
                   iv_text = |[{ ls_ret-id }/{ ls_ret-number }] { ls_ret-message }|
                   is_row = is_row iv_matnr = iv_matnr iv_view = gc_view-class ).
      IF ls_ret-type CA 'EA'.
        rv_ok = abap_false.
      ENDIF.
    ENDLOOP.

    rv_ok = finish_luw( iv_ok = rv_ok
                        iv_what = |Classification { lv_ctype }/{ lv_class }|
                        iv_msg = COND string( WHEN lv_exists = abap_true THEN `assignment changed`
                                              ELSE `assignment created` )
                        is_row = is_row iv_matnr = iv_matnr ).
  ENDMETHOD.

  METHOD get_ref_classification.
    "Classification of a reference material, class type IV_CTYPE (default
    "001): class IV_CLASS or - if not given - all classes of this type
    "(first class = main class, the others are returned in EXTRA_CLASS)
    DATA: lt_alloc  TYPE STANDARD TABLE OF bapi1003_alloc_list,
          lt_char   TYPE STANDARD TABLE OF bapi1003_alloc_values_char,
          lt_num    TYPE STANDARD TABLE OF bapi1003_alloc_values_num,
          lt_curr   TYPE STANDARD TABLE OF bapi1003_alloc_values_curr,
          lt_return TYPE STANDARD TABLE OF bapiret2,
          lv_objkey TYPE bapi1003_key-object,
          lv_class  TYPE bapi1003_key-classnum,
          lv_ctype  TYPE bapi1003_key-classtype.

    lv_ctype = COND #( WHEN iv_ctype IS INITIAL THEN gc_def_classtype ELSE iv_ctype ).
    DATA(lv_key) = |{ iv_matnr }/{ lv_ctype }/{ iv_class }|.
    READ TABLE mt_clcache INTO DATA(ls_cache) WITH KEY key = lv_key.
    IF sy-subrc = 0.
      rs_class = ls_cache-data.
      RETURN.
    ENDIF.

    lv_objkey = iv_matnr.
    DATA(lt_classes) = VALUE tt_fieldname( ).
    IF iv_class IS NOT INITIAL.
      APPEND CONV fieldname( to_upper( iv_class ) ) TO lt_classes.
    ELSE.
      "all classes of the type (several classes: first = main class, others = extra_class)
      CALL FUNCTION 'BAPI_OBJCL_GETCLASSES'
        EXPORTING
          objectkey_imp   = lv_objkey
          objecttable_imp = gc_objtab_mara
          classtype_imp   = lv_ctype
        TABLES
          alloclist       = lt_alloc
          return          = lt_return.
      LOOP AT lt_alloc INTO DATA(ls_alloc).
        APPEND CONV fieldname( ls_alloc-classnum ) TO lt_classes.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_classes INTO DATA(lv_cls).
      lv_class = lv_cls.
      CLEAR: lt_return, lt_char, lt_num, lt_curr.
      CALL FUNCTION 'BAPI_OBJCL_GETDETAIL'
        EXPORTING
          objectkey       = lv_objkey
          objecttable     = gc_objtab_mara
          classnum        = lv_class
          classtype       = lv_ctype
        TABLES
          allocvaluesnum  = lt_num
          allocvalueschar = lt_char
          allocvaluescurr = lt_curr
          return          = lt_return.
      CHECK NOT line_exists( lt_return[ type = 'E' ] ).
      "VALUE_CHAR can hold the value in the logon language (text), not the
      "key: take the language-neutral value, which is what the class master
      "(value list, length) and the BAPI expect
      LOOP AT lt_char ASSIGNING FIELD-SYMBOL(<ls_nchar>).
        ASSIGN COMPONENT 'VALUE_NEUTRAL' OF STRUCTURE <ls_nchar> TO FIELD-SYMBOL(<lv_neutral>).
        IF sy-subrc = 0 AND <lv_neutral> IS NOT INITIAL.
          <ls_nchar>-value_char = <lv_neutral>.
        ENDIF.
      ENDLOOP.
      sync_long_values( CHANGING ct_char = lt_char ).
      IF rs_class-classkey-classnum IS INITIAL.
        rs_class-classkey-classnum  = lv_class.
        rs_class-classkey-classtype = lv_ctype.
        rs_class-allocvalueschar    = lt_char.
        rs_class-allocvaluesnum     = lt_num.
        rs_class-allocvaluescurr    = lt_curr.
      ELSE.
        APPEND VALUE #( classkey        = VALUE #( classnum = lv_class classtype = lv_ctype )
                        allocvalueschar = lt_char
                        allocvaluesnum  = lt_num
                        allocvaluescurr = lt_curr ) TO rs_class-extra_class.
      ENDIF.
    ENDLOOP.

    APPEND VALUE #( key = lv_key data = rs_class ) TO mt_clcache.
  ENDMETHOD.

  METHOD sync_long_values.
    "S/4HANA (CLS_S4_CONV/004): short and long value of a characteristic
    "must be equal - VALUE_CHAR = VALUE_CHAR_LONG, VALUE_NEUTRAL = VALUE_NEUTRAL_LONG
    FIELD-SYMBOLS: <lv_short> TYPE any,
                   <lv_long>  TYPE any.
    LOOP AT ct_char ASSIGNING FIELD-SYMBOL(<ls_char>).
      DO 2 TIMES.
        DATA(lv_short) = COND string( WHEN sy-index = 1 THEN `VALUE_CHAR`    ELSE `VALUE_NEUTRAL` ).
        DATA(lv_long)  = COND string( WHEN sy-index = 1 THEN `VALUE_CHAR_LONG` ELSE `VALUE_NEUTRAL_LONG` ).
        ASSIGN COMPONENT lv_short OF STRUCTURE <ls_char> TO <lv_short>.
        CHECK sy-subrc = 0.
        ASSIGN COMPONENT lv_long OF STRUCTURE <ls_char> TO <lv_long>.
        CHECK sy-subrc = 0.
        <lv_long> = <lv_short>.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.

  METHOD finish_luw.
    "Test run: material BAPI ran with TESTRUN = 'X', classification is
    "undone by rollback - otherwise commit / rollback
    DATA ls_commit TYPE bapiret2.
    rv_ok = iv_ok.

    IF p_test = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      CALL FUNCTION 'DEQUEUE_ALL'.
      mo_log->add( iv_type = COND #( WHEN rv_ok = abap_true THEN 'S' ELSE 'E' )
                   iv_text = |Simulation { COND string( WHEN rv_ok = abap_true THEN `OK` ELSE `failed` ) } | &&
                             |- { iv_what }: { iv_msg }|
                   is_row = is_row iv_matnr = iv_matnr ).
    ELSEIF rv_ok = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait   = abap_true
        IMPORTING
          return = ls_commit.
      IF ls_commit-type CA 'EA'.
        rv_ok = abap_false.
        mo_log->add( iv_type = 'E' is_row = is_row iv_matnr = iv_matnr
                     iv_text = |Commit failed - { iv_what }: { ls_commit-message }| ).
      ELSE.
        mo_log->add( iv_type = 'S' is_row = is_row iv_matnr = iv_matnr
                     iv_text = |Posted - { iv_what }: { iv_msg }| ).
      ENDIF.
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      mo_log->add( iv_type = 'E' is_row = is_row iv_matnr = iv_matnr
                   iv_text = |Posting failed - { iv_what }: { iv_msg }| ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_OUTPUT - ALV, file on application server, e-mail
*======================================================================*
CLASS lcl_output IMPLEMENTATION.

  METHOD constructor.
    "Keep the log that is shown as output.
    mo_log = io_log.
  ENDMETHOD.

  METHOD publish.
    "Create the ALV of the log, then (not in a test run) write the output file to
    "the application server and send it by e-mail. Warnings are added to the log
    "if path or recipients are missing.
    mt_out = mo_log->mt_msg.
    CHECK build_alv( ) = abap_true.

    DATA(lv_xlsx) = to_xlsx( ).

    "Server file and e-mail: not in a test run; missing path / recipient -> warning
    IF p_test = abap_true.
      IF p_file3 IS NOT INITIAL OR s_email[] IS NOT INITIAL.
        mo_log->add( iv_type = 'W'
                     iv_text = 'Test run - output file on server and e-mail skipped' ).
      ENDIF.
    ELSE.
      IF p_file3 IS INITIAL.
        mo_log->add( iv_type = 'W' iv_text = 'No server path entered - output file not created' ).
      ELSE.
        save_to_server( lv_xlsx ).
      ENDIF.
      IF s_email[] IS INITIAL.
        mo_log->add( iv_type = 'W' iv_text = 'No e-mail recipient entered - e-mail not sent' ).
      ELSE.
        send_mail( lv_xlsx ).
      ENDIF.
    ENDIF.

    "messages of save / mail step
    mt_out = mo_log->mt_msg.
    IF sy-batch = abap_false.
      mo_alv->refresh( ).
      mo_alv->display( ).
    ENDIF.
  ENDMETHOD.

  METHOD build_alv.
    "ALV (CL_SALV_TABLE) of the log with title and column texts.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_alv
                                CHANGING  t_table      = mt_out ).
        mo_alv->get_functions( )->set_all( abap_true ).
        mo_alv->get_display_settings( )->set_list_header( CONV lvc_title(
          |Material { SWITCH string( lcl_screen=>get_operation( )
                                    WHEN gc_op-create THEN `Create`
                                    WHEN gc_op-update THEN `Update`
                                    ELSE `Extend` ) } - | &&
          |{ COND string( WHEN p_test = abap_true THEN `Test run` ELSE `Update run` ) }| ) ).

        DATA(lo_cols) = mo_alv->get_columns( ).
        lo_cols->set_optimize( ).
        CAST cl_salv_column_table( lo_cols->get_column( 'ICON' ) )->set_icon( if_salv_c_bool_sap=>true ).
        lo_cols->get_column( 'ICON'  )->set_long_text( 'Status' ).
        lo_cols->get_column( 'MSGTY' )->set_long_text( 'Type' ).
        lo_cols->get_column( 'ROW'   )->set_long_text( 'Template Row' ).
        lo_cols->get_column( 'MATNR' )->set_long_text( 'Material' ).
        lo_cols->get_column( 'VIEW'  )->set_long_text( 'View' ).
        lo_cols->get_column( 'FIELD' )->set_long_text( 'Template Field' ).
        lo_cols->get_column( 'FDESC' )->set_long_text( 'Field Description' ).
        lo_cols->get_column( 'TEXT'  )->set_long_text( 'Message' ).
        rv_ok = abap_true.
      CATCH cx_salv_msg cx_salv_not_found.
        MESSAGE 'Error building the output ALV'(e10) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD to_xlsx.
    "Convert the ALV to xlsx (initial if the conversion fails).
    TRY.
        rv_xdata = mo_alv->to_xml( xml_type = if_salv_bs_xml=>c_type_xlsx ).
      CATCH cx_root.
        CLEAR rv_xdata.
    ENDTRY.
  ENDMETHOD.

  METHOD file_name.
    "File name of the output file: MATMAINT_<operation>_<date>_<time>.xlsx.
    rv_name = |MATMAINT_{ lcl_screen=>get_operation( ) }_{ sy-datum }_{ sy-uzeit }.xlsx|.
  ENDMETHOD.

  METHOD save_to_server.
    "Write the output file to the application server. P_FILE3 is a directory
    "(ending with / or \) or a complete file name.
    CHECK p_file3 IS NOT INITIAL AND iv_xdata IS NOT INITIAL.

    "P_FILE3 = directory (ending with / or \) or complete file name
    DATA(lv_file) = p_file3.
    DATA(lv_last) = substring( val = lv_file off = strlen( lv_file ) - 1 len = 1 ).
    IF lv_last = `/` OR lv_last = `\`.
      lv_file = lv_file && file_name( ).
    ELSEIF lcl_file_reader=>get_extension( lv_file ) <> 'xlsx'.
      lv_file = lv_file && `.xlsx`.
    ENDIF.

    TRY.
        OPEN DATASET lv_file FOR OUTPUT IN BINARY MODE.
        IF sy-subrc <> 0.
          mo_log->add( iv_type = 'W' iv_text = |Output file { lv_file } could not be opened| ).
          RETURN.
        ENDIF.
        TRANSFER iv_xdata TO lv_file.
        CLOSE DATASET lv_file.
        mo_log->add( iv_type = 'S' iv_text = |Output stored on application server: { lv_file }| ).
      CATCH cx_sy_file_open cx_sy_file_authority cx_sy_file_io INTO DATA(lx_file).
        mo_log->add( iv_type = 'W' iv_text = |Output file not written: { lx_file->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD send_mail.
    "Send the log (short summary text, xlsx attached) by e-mail to the
    "recipients of S_EMAIL.
    DATA lt_body TYPE soli_tab.
    CHECK s_email[] IS NOT INITIAL.

    TRY.
        DATA(lo_send) = cl_bcs=>create_persistent( ).

        lt_body = VALUE #(
          ( line = |Material maintenance - { COND string( WHEN p_test = abap_true THEN `test run` ELSE `update run` ) }| )
          ( line = |Material type { p_mtart } / industry sector { p_indsec } / business profile { p_busprf }| )
          ( line = |Errors: { mo_log->count( 'E' ) }   Warnings: { mo_log->count( 'W' ) }   | &&
                   |Success: { mo_log->count( 'S' ) }| )
          ( line = `The detailed log is attached.` ) ).

        DATA(lo_doc) = cl_document_bcs=>create_document(
          i_type    = 'RAW'
          i_text    = lt_body
          i_subject = CONV so_obj_des( |Material maintenance log { sy-datum DATE = USER } { sy-uzeit TIME = USER }| ) ).

        IF iv_xdata IS NOT INITIAL.
          DATA(lv_name) = file_name( ).
          lo_doc->add_attachment(
            i_attachment_type    = 'BIN'
            i_attachment_subject = CONV so_obj_des( lv_name )
            i_attachment_size    = CONV so_obj_len( xstrlen( iv_xdata ) )
            i_att_content_hex    = cl_bcs_convert=>xstring_to_solix( iv_xdata )
            i_attachment_header  = VALUE soli_tab( ( line = |&SO_FILENAME={ lv_name }| ) ) ).
        ENDIF.

        lo_send->set_document( lo_doc ).
        DATA(lv_rcpt) = ``.
        LOOP AT s_email INTO DATA(ls_email) WHERE sign = 'I' AND option = 'EQ' AND low IS NOT INITIAL.
          lo_send->add_recipient( cl_cam_address_bcs=>create_internet_address( ls_email-low ) ).
          lv_rcpt = COND #( WHEN lv_rcpt IS INITIAL THEN ls_email-low ELSE |{ lv_rcpt }, { ls_email-low }| ).
        ENDLOOP.
        IF lv_rcpt IS INITIAL.
          RETURN.
        ENDIF.
        lo_send->set_send_immediately( abap_true ).
        lo_send->send( ).
        COMMIT WORK.
        mo_log->add( iv_type = 'S' iv_text = |Output log sent to { lv_rcpt }| ).
      CATCH cx_bcs INTO DATA(lx_bcs).
        mo_log->add( iv_type = 'W' iv_text = |E-mail not sent: { lx_bcs->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_TEMPLATE - upload template as .xlsx
*======================================================================*
CLASS lcl_template IMPLEMENTATION.

  METHOD template_columns.
    "Structure of the upload template (column order)
    DATA(lv_cols) =
      `ACTION MESSAGE PROCESS_PROFILE REFERENCE_MATNR REF_WERKS REF_LGORT REF_VKORG REF_VTWEG REF_EKORG ` &&
      `DEFAULT_MODE COPY_BASIC COPY_PURCH COPY_MRP COPY_FRCST COPY_SALES COPY_ACCOUNTING ` &&
      `MATNR MTART MBRSH LGORT SPRAS MAKTX MEINS MATKL PRDHA EXTWG BRGEW NTGEW GEWEI VOLUM VOLEH ` &&
      `EAN11 NUMTP XCHPF IPRKZ MHDRZ MHDLP SERNP MTPOS_MARA SPART KZUMV LABOR LAENG BREIT HOEHE MEABM ` &&
      `CLASS_TYPE CLASS_NAME CHAR_NAME_1 CHAR_VALUE_1 CHAR_NAME_2 CHAR_VALUE_2 CHAR_NAME_3 CHAR_VALUE_3 ` &&
      `CHAR_NAME_4 CHAR_VALUE_4 CHAR_NAME_5 CHAR_VALUE_5 ` &&
      `VKORG VTWEG VMSTD MSTDV MTPOS KTGRM MVGR2 MVGR3 KONDM BONBA VRKME UMREZ UMREN VKGRU PROVG ` &&
      `TRAGR LADGR MTVFP AUTLF ANTLF AUMNG STAWN EXPME HERKL LOGGR CASNR MSTAV VALID_TO DWERK VERSG ` &&
      `MWST ZGST PRCTR ` &&
      `EKORG EKGRP PLIFZ BSTMI_P BSTMA_P BSTME_P INSMK KZKRI EINKZ UMLMC TAXIM AUTRU MFRPN MFRNR ` &&
      `WERKS DISMM DISPO DISLS BSTMA BSTFE MINBE EISBE MABST MTVFP_M FXHOR PERKZ BESKZ LGPRO LGFSB ` &&
      `FHORI DZEIT IPRKZ_M PRGRP PERIV SBDKZ KAUSF RGEKZ XCHAR2 RAUBE TEMPB MHDRZ2 MHDLP2 MAXLP ` &&
      `DISGR ABCIN BSTRF SHFLG SHZET STRGR VRMOD VINT1 VINT2 MTVFP2 CCFIX PRMOD ` &&
      `LGNUM LGTYP LGBKZ LTKZE LHMG1 LVSME LETY1 LTKZA ` &&
      `BWKEY BKLAS VPRSV STPRS VERPR BWTTY MLAST HKMAT ZKPRS ZKDAT ` &&
      `PO_TEXT SALES_TEXT PRODH_LVL1 PRODH_LVL2 PRODH_LVL3 PRODH_LVL4 PRODH_LVL5`.

    SPLIT lv_cols AT space INTO TABLE rt_cols.
    DELETE rt_cols WHERE table_line IS INITIAL.
  ENDMETHOD.

  METHOD get_temp_matnr.
    "Temporary material number for a test run when the template has no MATNR.
    rv_matnr = |TEMPMATNR_{ is_row-row }|.
  ENDMETHOD.

  METHOD download.
    "Generate the upload template as .xlsx: template columns plus the fields of the
    "active variant; the header colour shows mandatory / conditional mandatory /
    "system derived / control columns.
    DATA: lt_fcat    TYPE tt_fcat,
          lt_cols    TYPE tt_col,
          lv_variant TYPE string,
          lv_file    TYPE string,
          lv_path    TYPE string,
          lv_full    TYPE string,
          lv_action  TYPE i.

    "Field flags of the active variant (only if type / sector / profile selected)
    IF p_mtart IS NOT INITIAL AND p_indsec IS NOT INITIAL AND p_busprf IS NOT INITIAL.
      DATA(lo_cfg) = NEW lcl_config( NEW lcl_log( ) ).
      TRY.
          lo_cfg->load( ).
          lt_fcat    = lo_cfg->mt_fcat.
          lv_variant = lo_cfg->mv_variant.
        CATCH lcx_error.
          CLEAR: lt_fcat, lv_variant.
      ENDTRY.
    ENDIF.

    "Columns = template structure + fields of the variant not yet contained
    DATA(lt_names) = template_columns( ).
    LOOP AT lt_fcat INTO DATA(ls_fcat).
      IF NOT line_exists( lt_names[ table_line = ls_fcat-temp_field_name ] ).
        APPEND ls_fcat-temp_field_name TO lt_names.
      ENDIF.
    ENDLOOP.

    "Header colour per column
    DATA(lt_ctrl) = lcl_config=>control_columns( ).
    LOOP AT lt_names INTO DATA(lv_name).
      APPEND VALUE #(
        field = lv_name
        style = COND #(
          WHEN line_exists( lt_ctrl[ table_line = lv_name ] )
            THEN c_style-control
          WHEN line_exists( lt_fcat[ temp_field_name = lv_name mandatory = abap_true ] )
            THEN c_style-mandatory
          WHEN line_exists( lt_fcat[ temp_field_name = lv_name cond_mandatory = abap_true ] )
            THEN c_style-cond
          WHEN line_exists( lt_fcat[ temp_field_name = lv_name system_derived = abap_true ] ) AND
               NOT line_exists( lt_fcat[ temp_field_name = lv_name optional = abap_true ] )
            THEN c_style-system
          ELSE c_style-header ) ) TO lt_cols ##PRIMKEY[K_FIELD].
    ENDLOOP.

    DATA(lv_xlsx) = build_xlsx( it_cols = lt_cols it_fcat = lt_fcat iv_variant = lv_variant ).

    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING  default_file_name = |Material_Template{ COND string( WHEN lv_variant IS NOT INITIAL
                                                                     THEN |_{ lv_variant }| ) }.xlsx|
                 default_extension = 'xlsx'
                 file_filter       = 'Excel (*.xlsx)|*.xlsx'
      CHANGING   filename          = lv_file
                 path              = lv_path
                 fullpath          = lv_full
                 user_action       = lv_action
      EXCEPTIONS OTHERS            = 1 ).
    CHECK sy-subrc = 0 AND lv_action = cl_gui_frontend_services=>action_ok.

    DATA(lt_bin) = cl_bcs_convert=>xstring_to_solix( lv_xlsx ).
    cl_gui_frontend_services=>gui_download(
      EXPORTING  bin_filesize = xstrlen( lv_xlsx )
                 filename     = lv_full
                 filetype     = 'BIN'
      CHANGING   data_tab     = lt_bin
      EXCEPTIONS OTHERS       = 1 ).
    IF sy-subrc = 0.
      MESSAGE |Template downloaded to { lv_full }| TYPE 'S'.
    ELSE.
      MESSAGE 'Template could not be downloaded'(e11) TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD build_xlsx.
    "Build the template as .xlsx (Office Open XML packed with CL_ABAP_ZIP):
    "template sheet, information sheet and styles.
    DATA(lo_zip) = NEW cl_abap_zip( ).

    lo_zip->add( name    = '[Content_Types].xml'
                 content = utf8(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` &&
      `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` &&
      `<Default Extension="xml" ContentType="application/xml"/>` &&
      `<Override PartName="/xl/workbook.xml" ` &&
      `ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>` &&
      `<Override PartName="/xl/worksheets/sheet1.xml" ` &&
      `ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>` &&
      `<Override PartName="/xl/worksheets/sheet2.xml" ` &&
      `ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>` &&
      `<Override PartName="/xl/styles.xml" ` &&
      `ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>` &&
      `</Types>` ) ).

    lo_zip->add( name    = '_rels/.rels'
                 content = utf8(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` &&
      `<Relationship Id="rId1" ` &&
      `Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" ` &&
      `Target="xl/workbook.xml"/>` &&
      `</Relationships>` ) ).

    lo_zip->add( name    = 'xl/workbook.xml'
                 content = utf8(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ` &&
      `xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` &&
      `<sheets><sheet name="TEMPLATE" sheetId="1" r:id="rId1"/>` &&
      `<sheet name="FIELD_INFO" sheetId="2" r:id="rId2"/></sheets>` &&
      `</workbook>` ) ).

    lo_zip->add( name    = 'xl/_rels/workbook.xml.rels'
                 content = utf8(
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` &&
      `<Relationship Id="rId1" ` &&
      `Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ` &&
      `Target="worksheets/sheet1.xml"/>` &&
      `<Relationship Id="rId2" ` &&
      `Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ` &&
      `Target="worksheets/sheet2.xml"/>` &&
      `<Relationship Id="rId3" ` &&
      `Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" ` &&
      `Target="styles.xml"/>` &&
      `</Relationships>` ) ).

    lo_zip->add( name = 'xl/styles.xml'            content = utf8( styles( ) ) ).
    lo_zip->add( name = 'xl/worksheets/sheet1.xml' content = utf8( sheet_template( it_cols ) ) ).
    lo_zip->add( name = 'xl/worksheets/sheet2.xml' content = utf8( sheet_info( it_fcat    = it_fcat
                                                                               iv_variant = iv_variant ) ) ).
    rv_xlsx = lo_zip->save( ).
  ENDMETHOD.

  METHOD sheet_template.
    "Sheet 1 = upload template: row 1 technical field names, data from row 2
    DATA lv_cells TYPE string.

    LOOP AT it_cols INTO DATA(ls_col).
      DATA(lv_idx) = sy-tabix.
      lv_cells = lv_cells && cell( iv_col = lv_idx iv_row = 1 iv_value = ls_col-field iv_style = ls_col-style ).
    ENDLOOP.

    rv_xml =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<sheetViews><sheetView workbookViewId="0">` &&
      `<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>` &&
      `</sheetView></sheetViews>` &&
      |<cols><col min="1" max="{ lines( it_cols ) }" width="18" style="{ c_style-text }" customWidth="1"/></cols>| &&
      |<sheetData><row r="1">{ lv_cells }</row></sheetData>| &&
      `</worksheet>`.
  ENDMETHOD.

  METHOD sheet_info.
    "Sheet 2 = instructions, colour legend and field list of the variant
    TYPES: BEGIN OF lty_line,
             style  TYPE i,
             values TYPE string_table,
           END OF lty_line.
    DATA: lt_lines TYPE STANDARD TABLE OF lty_line WITH EMPTY KEY,
          lv_rows  TYPE string,
          lv_cells TYPE string.

    APPEND VALUE #( style  = c_style-bold
                    values = VALUE #( ( COND string( WHEN iv_variant IS INITIAL
                                                     THEN `Material upload template`
                                                     ELSE |Material upload template - variant { iv_variant }| ) ) ) )
      TO lt_lines.
    APPEND VALUE #( values = VALUE #(
      ( `Fill sheet TEMPLATE from row 2. Do not change row 1 (technical field names) - only the first worksheet is read.` ) ) )
      TO lt_lines.
    APPEND VALUE #( values = VALUE #(
      ( `One row per material and org. level (plant / sales area / valuation area). Save as .xlsx or .csv.` ) ) )
      TO lt_lines.
    APPEND INITIAL LINE TO lt_lines.
    APPEND VALUE #( style = c_style-bold      values = VALUE #( ( `Header colour` ) ( `Meaning` ) ) ) TO lt_lines.
    APPEND VALUE #( style = c_style-control   values = VALUE #( ( `Green` )  ( `Control column (action, reference copy)` ) ) ) TO lt_lines.
    APPEND VALUE #( style = c_style-mandatory values = VALUE #( ( `Red` )    ( `Mandatory for the variant` ) ) ) TO lt_lines.
    APPEND VALUE #( style = c_style-cond      values = VALUE #( ( `Orange` ) ( `Conditional mandatory (rules in ZTMM_COND_MAND)` ) ) ) TO lt_lines.
    APPEND VALUE #( style = c_style-system    values = VALUE #( ( `Grey` )   ( `System derived - value is not used` ) ) ) TO lt_lines.
    APPEND VALUE #( style = c_style-header    values = VALUE #( ( `Blue` )   ( `Optional / not maintained for the variant` ) ) ) TO lt_lines.
    APPEND INITIAL LINE TO lt_lines.

    IF it_fcat IS INITIAL.
      APPEND VALUE #( values = VALUE #(
        ( `Select material type, industry sector and business profile before downloading ` &&
          `to get the field flags of the active variant.` ) ) ) TO lt_lines.
    ELSE.
      APPEND VALUE #( style  = c_style-bold
                      values = VALUE #( ( `Field` ) ( `Description` ) ( `View` ) ( `Flag` ) ( `BAPI target` ) ) )
        TO lt_lines.
      LOOP AT it_fcat INTO DATA(ls_fcat).
        APPEND VALUE #(
          style  = c_style-text
          values = VALUE #(
            ( CONV string( ls_fcat-temp_field_name ) )
            ( CONV string( ls_fcat-description ) )
            ( CONV string( ls_fcat-view ) )
            ( COND string( WHEN ls_fcat-mandatory      = abap_true THEN `Mandatory`
                           WHEN ls_fcat-cond_mandatory = abap_true THEN `Conditional mandatory`
                           WHEN ls_fcat-optional       = abap_true THEN `Optional`
                           WHEN ls_fcat-system_derived = abap_true THEN `System derived`
                           ELSE `Optional` ) )
            ( condense( |{ ls_fcat-bapi_struct_name } { ls_fcat-bapi_field_name }| ) ) ) )
          TO lt_lines.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_lines INTO DATA(ls_line).
      DATA(lv_row) = sy-tabix.
      CLEAR lv_cells.
      LOOP AT ls_line-values INTO DATA(lv_value).
        DATA(lv_col) = sy-tabix.
        lv_cells = lv_cells && cell( iv_col = lv_col iv_row = lv_row iv_value = lv_value iv_style = ls_line-style ).
      ENDLOOP.
      lv_rows = lv_rows && |<row r="{ lv_row }">{ lv_cells }</row>|.
    ENDLOOP.

    rv_xml =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<cols><col min="1" max="1" width="22" customWidth="1"/>` &&
      `<col min="2" max="2" width="55" customWidth="1"/>` &&
      `<col min="3" max="5" width="24" customWidth="1"/></cols>` &&
      |<sheetData>{ lv_rows }</sheetData>| &&
      `</worksheet>`.
  ENDMETHOD.

  METHOD styles.
    "Fonts: 0 Arial, 1 Arial bold white, 2 Arial bold
    "Fills: 2 blue, 3 red, 4 orange, 5 grey, 6 green
    "cellXfs: see C_STYLE
    rv_xml =
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` &&
      `<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` &&
      `<fonts count="3">` &&
      `<font><sz val="10"/><name val="Arial"/></font>` &&
      `<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>` &&
      `<font><b/><sz val="10"/><name val="Arial"/></font>` &&
      `</fonts>` &&
      `<fills count="7">` &&
      `<fill><patternFill patternType="none"/></fill>` &&
      `<fill><patternFill patternType="gray125"/></fill>` &&
      `<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill>` &&
      `<fill><patternFill patternType="solid"><fgColor rgb="FFC00000"/><bgColor indexed="64"/></patternFill></fill>` &&
      `<fill><patternFill patternType="solid"><fgColor rgb="FFED7D31"/><bgColor indexed="64"/></patternFill></fill>` &&
      `<fill><patternFill patternType="solid"><fgColor rgb="FF7F7F7F"/><bgColor indexed="64"/></patternFill></fill>` &&
      `<fill><patternFill patternType="solid"><fgColor rgb="FF548235"/><bgColor indexed="64"/></patternFill></fill>` &&
      `</fills>` &&
      `<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>` &&
      `<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>` &&
      `<cellXfs count="8">` &&
      `<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>` &&
      `<xf numFmtId="49" fontId="1" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>` &&
      `<xf numFmtId="49" fontId="1" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>` &&
      `<xf numFmtId="49" fontId="1" fillId="4" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>` &&
      `<xf numFmtId="49" fontId="1" fillId="5" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>` &&
      `<xf numFmtId="49" fontId="1" fillId="6" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>` &&
      `<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>` &&
      `<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>` &&
      `</cellXfs>` &&
      `<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>` &&
      `</styleSheet>`.
  ENDMETHOD.

  METHOD cell.
    "XML of one text cell of the template sheet.
    rv_xml = |<c r="{ col_letter( iv_col ) }{ iv_row }" t="inlineStr" s="{ iv_style }">| &&
             |<is><t xml:space="preserve">| &&
             escape( val = CONV string( iv_value ) format = cl_abap_format=>e_xml_text ) &&
             |</t></is></c>|.
  ENDMETHOD.

  METHOD col_letter.
    "1 -> A, 26 -> Z, 27 -> AA ...
    DATA(lv_n) = iv_col.
    WHILE lv_n > 0.
      DATA(lv_m) = ( lv_n - 1 ) MOD 26.
      rv_col = substring( val = sy-abcde off = lv_m len = 1 ) && rv_col.
      lv_n = ( lv_n - 1 ) DIV 26.
    ENDWHILE.
  ENDMETHOD.

  METHOD utf8.
    "Convert XML text to UTF-8 (xstring).
    rv_x = cl_abap_codepage=>convert_to( iv_xml ).
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_SCREEN - selection screen
*======================================================================*
CLASS lcl_screen IMPLEMENTATION.

  METHOD initialization.
    "Initial screen values (text of the template download button).
    p_btn = 'Download Template'(b01).
  ENDMETHOD.

  METHOD get_operation.
    "Operation selected on the screen: create / update / extend.
    rv_opid = COND #( WHEN r_create = abap_true THEN gc_op-create
                      WHEN r_update = abap_true THEN gc_op-update
                      ELSE                           gc_op-extend ).
  ENDMETHOD.

  METHOD pbo.
    "Screen output: file input depends on PC / server, basic data checkbox is fixed
    "to X and not editable, listboxes are filled.
    LOOP AT SCREEN.
      CASE screen-group1.
        WHEN 'MD1'.
          screen-input = COND #( WHEN r_local = abap_true THEN '1' ELSE '0' ).
        WHEN 'MD2'.
          screen-input = COND #( WHEN r_unix  = abap_true THEN '1' ELSE '0' ).
      ENDCASE.
      "basic data is always processed: checkbox fixed to 'X', not editable
      IF screen-name = 'P_BASIC'.
        p_basic      = abap_true.
        screen-input = '0'.
      ENDIF.
      MODIFY SCREEN.
    ENDLOOP.
    set_listboxes( ).
  ENDMETHOD.

  METHOD set_listboxes.
    "Only values allowed in ZTMM_MATMAS_MAST for the selected action
    DATA: lt_vrm    TYPE vrm_values,
          lt_mtart  TYPE STANDARD TABLE OF mtart         WITH EMPTY KEY,
          lt_indsec TYPE STANDARD TABLE OF z_de_ind_sec  WITH EMPTY KEY,
          lt_busprf TYPE STANDARD TABLE OF z_de_bus_prof WITH EMPTY KEY,
          lr_mtart  TYPE RANGE OF mtart,
          lr_indsec TYPE RANGE OF z_de_ind_sec.

    DATA(lv_opid) = get_operation( ).

    "--- Material type
    SELECT DISTINCT mat_type FROM ztmm_matmas_mast
      INTO TABLE @lt_mtart
      WHERE operation_id = @lv_opid
        AND active_flag  = @abap_true
        AND valid_from  <= @sy-datum
        AND ( valid_to  >= @sy-datum OR valid_to = '00000000' ).
    IF lt_mtart IS NOT INITIAL.
      SELECT mtart, mtbez FROM t134t
        INTO TABLE @DATA(lt_t134t)
        FOR ALL ENTRIES IN @lt_mtart
        WHERE spras = @sy-langu AND mtart = @lt_mtart-table_line.
    ENDIF.
    lt_vrm = VALUE #( FOR lv_mtart IN lt_mtart
                      ( key  = lv_mtart
                        text = VALUE #( lt_t134t[ mtart = lv_mtart ]-mtbez OPTIONAL ) ) ).
    CALL FUNCTION 'VRM_SET_VALUES' EXPORTING id = 'P_MTART' values = lt_vrm EXCEPTIONS OTHERS = 0.
    IF p_mtart IS NOT INITIAL AND NOT line_exists( lt_mtart[ table_line = p_mtart ] ).
      CLEAR p_mtart.
    ENDIF.

    "--- Industry sector (for material type)
    IF p_mtart IS NOT INITIAL.
      lr_mtart = VALUE #( ( sign = 'I' option = 'EQ' low = p_mtart ) ).
    ENDIF.
    SELECT DISTINCT ind_sec FROM ztmm_matmas_mast
      INTO TABLE @lt_indsec
      WHERE operation_id = @lv_opid
        AND active_flag  = @abap_true
        AND mat_type    IN @lr_mtart
        AND valid_from  <= @sy-datum
        AND ( valid_to  >= @sy-datum OR valid_to = '00000000' ).
    IF lt_indsec IS NOT INITIAL.
      SELECT mbrsh, mbbez FROM t137t
        INTO TABLE @DATA(lt_t137t)
        FOR ALL ENTRIES IN @lt_indsec
        WHERE spras = @sy-langu AND mbrsh = @lt_indsec-table_line.
    ENDIF.
    lt_vrm = VALUE #( FOR lv_ind IN lt_indsec
                      ( key  = lv_ind
                        text = VALUE #( lt_t137t[ mbrsh = lv_ind ]-mbbez OPTIONAL ) ) ).
    CALL FUNCTION 'VRM_SET_VALUES' EXPORTING id = 'P_INDSEC' values = lt_vrm EXCEPTIONS OTHERS = 0.
    IF p_indsec IS NOT INITIAL AND NOT line_exists( lt_indsec[ table_line = p_indsec ] ).
      CLEAR p_indsec.
    ENDIF.

    "--- Business profile (for material type + industry sector)
    IF p_indsec IS NOT INITIAL.
      lr_indsec = VALUE #( ( sign = 'I' option = 'EQ' low = p_indsec ) ).
    ENDIF.
    SELECT DISTINCT bus_prof FROM ztmm_matmas_mast
      INTO TABLE @lt_busprf
      WHERE operation_id = @lv_opid
        AND active_flag  = @abap_true
        AND mat_type    IN @lr_mtart
        AND ind_sec     IN @lr_indsec
        AND valid_from  <= @sy-datum
        AND ( valid_to  >= @sy-datum OR valid_to = '00000000' ).
    lt_vrm = VALUE #( FOR lv_bp IN lt_busprf ( key = lv_bp text = lv_bp ) ).
    CALL FUNCTION 'VRM_SET_VALUES' EXPORTING id = 'P_BUSPRF' values = lt_vrm EXCEPTIONS OTHERS = 0.
    IF p_busprf IS NOT INITIAL AND NOT line_exists( lt_busprf[ table_line = p_busprf ] ).
      CLEAR p_busprf.
    ENDIF.
  ENDMETHOD.

  METHOD pai.
    "Screen input: template download button; check of the input before execute,
    "background run and print.
    CASE sscrfields-ucomm.
      WHEN 'BTN_CLK'.
        download_template( ).
      WHEN 'ONLI' OR 'SJOB' OR 'PRIN'.
        check_input( ).
    ENDCASE.
  ENDMETHOD.

  METHOD check_input.
    "Check the selection screen: material type / industry sector / business profile,
    "at least one view, template file and its extension, e-mail recipients.
    IF p_mtart IS INITIAL OR p_indsec IS INITIAL OR p_busprf IS INITIAL.
      MESSAGE 'Select material type, industry sector and business profile'(e01) TYPE 'E'.
    ENDIF.
    IF p_class IS INITIAL AND p_sales IS INITIAL AND p_purch  IS INITIAL AND
       p_mrp IS INITIAL AND p_frcst IS INITIAL AND p_plntst IS INITIAL AND p_val IS INITIAL AND
       p_basic IS INITIAL.
      MESSAGE 'Select at least one view'(e02) TYPE 'E'.
    ENDIF.
    DATA(lv_file) = COND string( WHEN r_local = abap_true THEN p_file1 ELSE p_file2 ).
    IF lv_file IS INITIAL.
      MESSAGE 'Enter the template file path'(e03) TYPE 'E'.
    ENDIF.
    DATA(lv_ext) = lcl_file_reader=>get_extension( lv_file ).
    IF lv_ext <> 'xlsx' AND lv_ext <> 'csv'.
      MESSAGE 'Only .xlsx and .csv files are allowed'(e04) TYPE 'E'.
    ENDIF.

    "e-mail recipients: single values in a valid address format
    LOOP AT s_email INTO DATA(ls_email).
      IF ls_email-sign <> 'I' OR ls_email-option <> 'EQ'.
        MESSAGE 'E-mail recipients: only single values can be included'(e05) TYPE 'E'.
      ENDIF.
      IF ls_email-low IS INITIAL OR
         NOT matches( val   = condense( ls_email-low )
                      pcre  = `[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}` ).
        MESSAGE |Invalid e-mail address: { ls_email-low }| TYPE 'E'.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD f4_local_file.
    "F4 help for the template file on the PC (file open dialog).
    DATA: lt_files TYPE filetable,
          lv_rc    TYPE i.
    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING  file_filter = 'Excel (*.xlsx)|*.xlsx|CSV (*.csv)|*.csv'
      CHANGING   file_table  = lt_files
                 rc          = lv_rc
      EXCEPTIONS OTHERS      = 1 ).
    IF sy-subrc = 0 AND lv_rc > 0.
      cv_file = lt_files[ 1 ]-filename.
    ENDIF.
  ENDMETHOD.

  METHOD download_template.
    "Download of the template file for the selected operation from the SMW0 objects
    "(create / update / extend).

    "Upload template (.xlsx) as reference for the user

    TYPES:
      BEGIN OF ty_template_result,
        operation_code TYPE char1,
        object_id      TYPE wwwdatatab-objid,
        file_name      TYPE string,
        mime_type      TYPE string,
        content        TYPE xstring,
      END OF ty_template_result.

    DATA: ls_result TYPE ty_template_result.

    DATA lv_object_id TYPE wwwdatatab-objid.
    DATA(lv_operation) = lcl_screen=>get_operation( ).

    CASE lv_operation.
      WHEN 'C'.
        lv_object_id = 'ZMMCREATE_CRT_XLSX'.
        ls_result-file_name = 'ZMMCREATE_Create_Template.xlsx'.
      WHEN 'U'.
        lv_object_id = 'ZMMCREATE_UPD_XLSX'.
        ls_result-file_name = 'ZMMCREATE_Update_Template.xlsx'.
      WHEN 'E'.
        lv_object_id = 'ZMMCREATE_EXT_XLSX'.
        ls_result-file_name = 'ZMMCREATE_Extend_Template.xlsx'.
    ENDCASE.

    ls_result-operation_code = lv_operation.
    ls_result-object_id      = lv_object_id.
    ls_result-mime_type      =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.

    DATA(lv_result) = download_from_smw0(
     iv_objid  = lv_object_id
     iv_target = '' ).

  ENDMETHOD.

  METHOD download_from_smw0.
    "Download a binary object (MIME) from SMW0 to a file on the PC. Returns true if
    "the file was saved.
    DATA: ls_key      TYPE wwwdatatab,
          lt_mime     TYPE STANDARD TABLE OF w3mime,
          lt_params   TYPE STANDARD TABLE OF wwwparams,
          lv_filesize TYPE i,
          lv_ext      TYPE string,
          lv_name     TYPE string,
          lv_path     TYPE string,
          lv_fullpath TYPE string,
          lv_target   TYPE string.
    rv_ok = abap_false.
    " 1. Read the object header (must exist as binary object, relid = 'MI')
    SELECT SINGLE * FROM wwwdata INTO CORRESPONDING FIELDS OF ls_key
      WHERE srtf2 = 0
        AND relid = 'MI'
        AND objid = iv_objid.
    IF sy-subrc <> 0.
      MESSAGE |SMW0 object { iv_objid } not found| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " 2. Get file size and extension from the object's parameters
    CALL FUNCTION 'WWWPARAMS_READ_ALL'
      EXPORTING
        TYPE  = ls_key-relid
        objid  = ls_key-objid
      TABLES
        params = lt_params
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc = 0.
      LOOP AT lt_params ASSIGNING FIELD-SYMBOL(<ls_p>).
        CASE <ls_p>-name.
          WHEN 'filesize'.      lv_filesize = <ls_p>-value.
          WHEN 'fileextension'. lv_ext      = <ls_p>-value.
        ENDCASE.
      ENDLOOP.
    ENDIF.
    " 3. Import binary content
    CALL FUNCTION 'WWWDATA_IMPORT'
      EXPORTING
        key               = ls_key
      TABLES
        mime              = lt_mime
      EXCEPTIONS
        wrong_object_type = 1
        import_error      = 2
        OTHERS            = 3.
    IF sy-subrc <> 0.
      MESSAGE |Import of { iv_objid } failed| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    " 4. Determine target path
    lv_target = iv_target.
    IF lv_target IS INITIAL.
      cl_gui_frontend_services=>file_save_dialog(
        EXPORTING
          default_file_name = |{ iv_objid }{ lv_ext }|
          default_extension = lv_ext
        CHANGING
          filename          = lv_name
          path              = lv_path
          fullpath          = lv_fullpath
        EXCEPTIONS
          OTHERS            = 1 ).
      IF sy-subrc <> 0 OR lv_fullpath IS INITIAL.
        RETURN.
      ENDIF.
      lv_target = lv_fullpath.
    ENDIF.
    " 5. Download to frontend
    cl_gui_frontend_services=>gui_download(
      EXPORTING
        bin_filesize = lv_filesize
        filename     = lv_target
        filetype     = 'BIN'
      CHANGING
        data_tab     = lt_mime
      EXCEPTIONS
        OTHERS       = 1 ).
    IF sy-subrc <> 0.
      MESSAGE |Download to { lv_target } failed| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    rv_ok = abap_true.
    MESSAGE |File downloaded to { lv_target }| TYPE 'S'.
  ENDMETHOD.

ENDCLASS.

*======================================================================*
* LCL_APP - controller
*======================================================================*
CLASS lcl_app IMPLEMENTATION.

  METHOD constructor.
    "Create the log, the configuration and the BAPI handler.
    mo_log    = NEW #( ).
    mo_config = NEW #( mo_log ).
    mo_bapi   = NEW #( mo_log ).
  ENDMETHOD.

  METHOD run.
    "Main flow: load configuration and template, derive and check data, validate
    "and map the rows, post the materials and show the log.
    TRY.
        mo_config->load( ).          "5.2 variant, 5.3/5.4 view tables
        load_template( ).            "5.1 read template
        check_defaults( ).           "ZTMM_DEFLT_DATA entries usable?
        derive_values( ).
        inherit_org_keys( ).         "empty WERKS / VKORG / VTWEG from REF_*
        check_columns( ).
        validate_and_map( ).         "5.5 validation + mapping to BAPI
      CATCH lcx_error INTO DATA(lx_error).
        mo_log->add( iv_type = 'E' iv_text = lx_error->get_text( ) ).
    ENDTRY.

    DATA(lv_err) = mo_log->count( 'E' ).

    IF mo_log->has_global_error( ) = abap_true.
      mo_log->add( iv_type = 'E'
                   iv_text = |{ COND string( WHEN p_test = abap_true THEN `Simulation` ELSE `Posting` ) } | &&
                             |not executed - correct the errors first| ).
    ELSE.
      process_materials( ).        "simulate / post
    ENDIF.

    NEW lcl_output( mo_log )->publish( ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* 5.1 - template
*----------------------------------------------------------------------*
  METHOD load_template.
    "Read the template: header row = technical field names, data rows = non-empty
    "cells (MT_CELL) and the list of rows with their keys (MT_ROW).
    DATA lv_has_data TYPE abap_bool.

    DATA(lv_file) = COND string( WHEN r_local = abap_true THEN p_file1 ELSE p_file2 ).
    DATA(lt_raw)  = lcl_file_reader=>read( iv_file = lv_file iv_server = r_unix ).

    "Header row: column index -> technical field name
    DATA(lt_hdr) = lt_raw[ gc_hdr_row ].
    LOOP AT lt_hdr INTO DATA(lv_hdr).
      DATA(lv_field) = CONV fieldname( to_upper( lcl_mapper=>trim( lv_hdr ) ) ).
      IF lv_field IS NOT INITIAL AND line_exists( mt_header[ table_line = lv_field ] ).
        mo_log->add( iv_type = 'W' iv_field = lv_field iv_text = 'Duplicate column - first occurrence used' ).
        CLEAR lv_field.
      ENDIF.
      APPEND lv_field TO mt_header.
    ENDLOOP.

    "Data rows: keep non-empty cells only
    LOOP AT lt_raw INTO DATA(lt_values) FROM gc_data_row.
      DATA(lv_row) = sy-tabix.                            "= row number in the file
      lv_has_data = abap_false.

      LOOP AT lt_values INTO DATA(lv_raw).
        DATA(lv_col) = sy-tabix.
        DATA(lv_colname) = VALUE fieldname( mt_header[ lv_col ] OPTIONAL ).
        CHECK lv_colname IS NOT INITIAL AND lv_colname <> gc_col-message.
        DATA(lv_value) = lcl_mapper=>trim( lv_raw ).
        CHECK lv_value IS NOT INITIAL.
        INSERT VALUE #( row = lv_row field = lv_colname value = lv_value ) INTO TABLE mt_cell.
        lv_has_data = abap_true.
      ENDLOOP.

      CHECK lv_has_data = abap_true.                      "skip empty lines
      DATA(lv_matnr) = to_upper( get_value( iv_row = lv_row iv_field = gc_col-matnr ) ).
      APPEND VALUE #( row    = lv_row
                      matkey = COND #( WHEN lv_matnr IS INITIAL THEN |#{ lv_row }| ELSE lv_matnr )
                      werks  = to_upper( get_value( iv_row = lv_row iv_field = gc_col-werks ) )
                      vkorg  = to_upper( get_value( iv_row = lv_row iv_field = gc_col-vkorg ) )
                      vtweg  = to_upper( get_value( iv_row = lv_row iv_field = gc_col-vtweg ) ) )
        TO mt_row.
    ENDLOOP.

    IF mt_row IS INITIAL.
      RAISE EXCEPTION TYPE lcx_error EXPORTING iv_text = 'Template contains no data rows'.
    ENDIF.
    mo_log->add( iv_type = 'S' iv_text = |Template { lv_file }: { lines( mt_row ) } data row(s) read| ).
  ENDMETHOD.

  METHOD check_defaults.
    "Default values (ZTMM_DEFLT_DATA) are used for Create only. An entry that
    "can not be applied is reported once as an error: field is a control
    "column / key field, or is not a field of the active variant / selected views.
    CHECK lcl_screen=>get_operation( ) = gc_op-create.

    DATA(lt_ctrl) = lcl_config=>control_columns( ).
    LOOP AT mo_config->mt_deflt INTO DATA(ls_def).
      DATA(lv_field) = CONV fieldname( ls_def-temp_field_name ).
      CHECK lv_field IS NOT INITIAL AND ls_def-def_field_value IS NOT INITIAL.
      IF lv_field = gc_col-matnr OR lv_field = gc_col-werks OR
         lv_field = gc_col-vkorg OR lv_field = gc_col-vtweg OR
         line_exists( lt_ctrl[ table_line = lv_field ] ).
        mo_log->add( iv_type = 'E' iv_field = lv_field
                     iv_text = |Default for { lv_field } in ZTMM_DEFLT_DATA not possible - control / key field| ).
      ELSEIF NOT line_exists( mo_config->mt_fcat[ KEY k_field COMPONENTS temp_field_name = lv_field ] ).
        mo_log->add( iv_type = 'E' iv_field = lv_field
                     iv_text = |Default for { lv_field } in ZTMM_DEFLT_DATA: field is not part of variant | &&
                               |{ mo_config->mv_variant } / selected views| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD apply_unit_defaults.
    "Unit of measure lines (MARM): ALT_UNIT (MEINH), NUMERATOR (UMREZ) and
    "DENOMINATR (UMREN) - priority: 1. template  2. reference material
    "3. default table ZTMM_DEFLT_DATA (APPLY_DEFAULTS) - what is still empty
    "is set here: ALT_UNIT = base unit (MEINS), NUMERATOR = 1, DENOMINATR = 1
    DATA(lv_base) = cs_bapi-clientdata-base_uom.
    CHECK lv_base IS NOT INITIAL.

    LOOP AT cs_bapi-unitsofmeasure ASSIGNING FIELD-SYMBOL(<ls_uom>).
      DATA(lv_set) = abap_false.
      IF <ls_uom>-alt_unit IS INITIAL AND <ls_uom>-alt_unit_iso IS INITIAL.
        <ls_uom>-alt_unit = lv_base.
        lv_set = abap_true.
      ENDIF.
      IF <ls_uom>-numerator IS INITIAL.
        <ls_uom>-numerator = 1.
        lv_set = abap_true.
      ENDIF.
      IF <ls_uom>-denominatr IS INITIAL.
        <ls_uom>-denominatr = 1.
        lv_set = abap_true.
      ENDIF.
      CHECK lv_set = abap_true.
      mo_log->add( iv_type = 'S' is_row = is_row iv_view = gc_view-basic
                   iv_text = |Unit of measure { <ls_uom>-alt_unit }: missing unit / numerator / | &&
                             |denominator set (base unit { lv_base }, 1 / 1)| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD apply_defaults.
    "Default values (ZTMM_DEFLT_DATA) - priority per field:
    "  1. template value  2. value copied from the reference material
    "  3. default value (this method, runs after the reference copy)
    "The field need not be a column of the template. The default is handled
    "like a template value (conversion, validation, mapping to the BAPI).
    "Create only; several entries for one field: the first one is used.
    CHECK lcl_screen=>get_operation( ) = gc_op-create.
    CHECK mo_config->mt_deflt IS NOT INITIAL.

    DATA(lt_ctrl) = lcl_config=>control_columns( ).

    LOOP AT mo_config->mt_deflt INTO DATA(ls_def).
      DATA(lv_field) = CONV fieldname( ls_def-temp_field_name ).
      DATA(lv_value) = lcl_mapper=>trim( ls_def-def_field_value ).
      CHECK lv_field IS NOT INITIAL AND lv_value IS NOT INITIAL.
      "entries that can not be used are reported in CHECK_DEFAULTS
      CHECK lv_field <> gc_col-matnr AND lv_field <> gc_col-werks AND
            lv_field <> gc_col-vkorg AND lv_field <> gc_col-vtweg.
      CHECK NOT line_exists( lt_ctrl[ table_line = lv_field ] ).
      CHECK line_exists( mo_config->mt_fcat[ KEY k_field COMPONENTS temp_field_name = lv_field ] ).

      CHECK NOT line_exists( mt_cell[   row = is_row-row field = lv_field ] ).   "template value
      CHECK NOT line_exists( mt_copied[ row = is_row-row field = lv_field ] ).   "reference value

      INSERT VALUE #( row = is_row-row field = lv_field value = lv_value ) INTO TABLE mt_cell.
      mo_log->add( iv_type = 'S' is_row = is_row iv_field = lv_field
                   iv_text = |Value { lv_value } for { lv_field } taken from default table ZTMM_DEFLT_DATA| ).

      LOOP AT mo_config->mt_fcat INTO DATA(ls_fcat) USING KEY k_field WHERE temp_field_name = lv_field.
        validate_row( EXPORTING is_row = is_row is_fcat = ls_fcat CHANGING cs_bapi = cs_bapi ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD apply_current_date.
    "Valid-from dates of the material status (MSTDV client level, VMSTD sales
    "view) - Create only; only if the field belongs to the variant.
    "  1. value from the template  2. value from the reference material
    "  3. value from ZTMM_DEFLT_DATA (APPLY_DEFAULTS, runs before)
    "  4. nothing found -> current date
    "A value from the template / default table must be a valid date in the
    "format YYYYMMDD, otherwise an error is logged.
    CONSTANTS lc_date_fields TYPE string VALUE ` VMSTD MSTDV `.
    CHECK lcl_screen=>get_operation( ) = gc_op-create.

    SPLIT condense( lc_date_fields ) AT space INTO TABLE DATA(lt_fields).
    LOOP AT lt_fields INTO DATA(lv_name).
      DATA(lv_field) = CONV fieldname( lv_name ).
      CHECK line_exists( mo_config->mt_fcat[ KEY k_field COMPONENTS temp_field_name = lv_field ] ).
      CHECK NOT line_exists( mt_copied[ row = is_row-row field = lv_field ] ).

      ASSIGN mt_cell[ row = is_row-row field = lv_field ] TO FIELD-SYMBOL(<ls_cell>).
      IF sy-subrc = 0.
        "template / default table value: format check only
        DATA(lv_given) = lcl_mapper=>trim( <ls_cell>-value ).
        CHECK lv_given IS NOT INITIAL.
        IF NOT is_yyyymmdd( lv_given ).
          mo_log->add( iv_type = 'E' is_row = is_row iv_field = lv_field
                       iv_text = |{ lv_field }: '{ lv_given }' is not a valid date - format must be YYYYMMDD| ).
        ENDIF.
        CONTINUE.
      ENDIF.

      DATA(lv_date) = CONV string( sy-datum ).                "YYYYMMDD
      INSERT VALUE #( row = is_row-row field = lv_field value = lv_date ) INTO TABLE mt_cell.
      mo_log->add( iv_type = 'S' is_row = is_row iv_field = lv_field
                   iv_text = |Current date { lv_date } set for blank field { lv_field }| ).

      LOOP AT mo_config->mt_fcat INTO DATA(ls_fcat) USING KEY k_field WHERE temp_field_name = lv_field.
        validate_row( EXPORTING is_row = is_row is_fcat = ls_fcat CHANGING cs_bapi = cs_bapi ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_yyyymmdd.
    "8 digits and a real calendar date (e.g. 20250230 is rejected)
    DATA lv_date TYPE d.
    rv_ok = abap_false.
    CHECK strlen( iv_value ) = 8 AND iv_value CO '0123456789'.
    lv_date = iv_value.
    CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
      EXPORTING
        date                      = lv_date
      EXCEPTIONS
        plausibility_check_failed = 1
        OTHERS                    = 2.
    rv_ok = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD derive_values.
    "PRDHA derived from PRODH_LVL1..n if not given directly.
    " - each level is padded to its own length (taken from the nodes of T179:
    "   the key length of a node of level n = sum of the lengths of levels 1..n)
    " - levels must be filled without gaps
    " - the resulting / given PRDHA must exist in T179
    " - PRDHA given together with levels: PRDHA wins, difference is reported
    TYPES: BEGIN OF lty_len,
             stufe TYPE t179-stufe,
             len   TYPE i,
           END OF lty_len.
    DATA: lt_len  TYPE SORTED TABLE OF lty_len WITH UNIQUE KEY stufe,
          lt_node TYPE SORTED TABLE OF t179-prodh WITH UNIQUE KEY table_line,
          lv_lvl  TYPE string,
          lv_seg  TYPE string,
          lv_prdha TYPE string.

    SELECT prodh, stufe FROM t179 INTO TABLE @DATA(lt_t179).
    LOOP AT lt_t179 INTO DATA(ls_t179).
      INSERT ls_t179-prodh INTO TABLE lt_node.
      INSERT VALUE #( stufe = ls_t179-stufe len = strlen( ls_t179-prodh ) ) INTO TABLE lt_len.
    ENDLOOP.

    LOOP AT mt_row INTO DATA(ls_row).
      "--- levels -> key (padded, no gaps)
      CLEAR: lv_prdha.
      DATA(lv_last)   = 0.                                   "highest filled level
      DATA(lv_gap)    = 0.                                   "first empty level below it
      DATA(lv_failed) = abap_false.
      DATA(lv_prev)   = 0.                                   "cumulative length of the level before
      DO gc_prodh_levels TIMES.
        DATA(lv_i) = sy-index.
        lv_lvl = to_upper( lcl_mapper=>trim( get_value( iv_row   = ls_row-row
                                                        iv_field = CONV #( |PRODH_LVL{ lv_i }| ) ) ) ).
        IF lv_lvl IS INITIAL.
          IF lv_gap = 0.
            lv_gap = lv_i.
          ENDIF.
          CONTINUE.
        ENDIF.
        IF lv_gap <> 0.
          mo_log->add( iv_type = 'E' is_row = ls_row iv_field = CONV #( |PRODH_LVL{ lv_i }| )
                       iv_text = |PRODH_LVL{ lv_i } is filled but PRODH_LVL{ lv_gap } is empty - | &&
                                 |product hierarchy levels must be filled without gaps| ).
          lv_failed = abap_true.
          EXIT.
        ENDIF.
        lv_last = lv_i.
        "length of this level from T179 (if the level exists there)
        DATA(lv_cum) = VALUE i( lt_len[ stufe = lv_i ]-len OPTIONAL ).
        IF lv_cum > 0.
          DATA(lv_width) = lv_cum - lv_prev.
          IF strlen( lv_lvl ) > lv_width.
            mo_log->add( iv_type = 'E' is_row = ls_row iv_field = CONV #( |PRODH_LVL{ lv_i }| )
                         iv_text = |PRODH_LVL{ lv_i } '{ lv_lvl }' is longer than { lv_width } characters| ).
            lv_failed = abap_true.
            EXIT.
          ENDIF.
          lv_seg = |{ lv_lvl WIDTH = lv_width }|.             "pad right to the level length
          lv_prev = lv_cum.
        ELSE.
          lv_seg = lv_lvl.
        ENDIF.
        lv_prdha = lv_prdha && lv_seg.
      ENDDO.
      CHECK lv_failed = abap_false.

      "--- PRDHA given directly
      DATA(lv_given) = to_upper( get_value( iv_row = ls_row-row iv_field = gc_col-prdha ) ).
      IF lv_given IS NOT INITIAL.
        IF lv_prdha IS NOT INITIAL AND condense( lv_given ) <> condense( lv_prdha ).
          mo_log->add( iv_type = 'W' is_row = ls_row iv_field = gc_col-prdha
                       iv_text = |PRDHA { lv_given } is used - it differs from PRODH_LVL1-{ gc_prodh_levels } ({ lv_prdha })| ).
        ENDIF.
        lv_prdha = lv_given.
      ELSEIF lv_prdha IS NOT INITIAL.
        INSERT VALUE #( row = ls_row-row field = gc_col-prdha value = lv_prdha ) INTO TABLE mt_cell.
        mo_log->add( iv_type = 'S' is_row = ls_row iv_field = gc_col-prdha
                     iv_text = |Product hierarchy '{ lv_prdha }' derived from PRODH_LVL1-{ lv_last }| ).
      ENDIF.

      "--- existence (only if the hierarchy is maintained in this system)
      IF lv_prdha IS NOT INITIAL AND lt_node IS NOT INITIAL AND
         NOT line_exists( lt_node[ table_line = CONV t179-prodh( lv_prdha ) ] ).
        mo_log->add( iv_type = 'E' is_row = ls_row iv_field = gc_col-prdha
                     iv_text = |Product hierarchy '{ lv_prdha }' does not exist (T179)| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD inherit_org_keys.
    "Reference material: plant / sales area not given in the template are
    "taken from REF_WERKS / REF_VKORG / REF_VTWEG - the new material is then
    "created in the org. levels of the reference. Only for views that are
    "copied (no COPY_* flag = all views). The value is handled exactly like
    "a template value (mapping, existence checks, log).
    LOOP AT mt_row ASSIGNING FIELD-SYMBOL(<ls_row>).
      CHECK get_value( iv_row = <ls_row>-row iv_field = gc_col-ref_matnr ) IS NOT INITIAL.

      DATA(lv_purch) = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_purch ).
      DATA(lv_mrp)   = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_mrp ).
      DATA(lv_frcst) = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_frcst ).
      DATA(lv_acct)  = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_acct ).
      DATA(lv_sales) = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_sales ).
      DATA(lv_basic) = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_basic ).
      DATA(lv_class) = is_flag_set( iv_row = <ls_row>-row iv_field = gc_col-copy_class ).
      DATA(lv_no_flag) = xsdbool( lv_purch = abap_false AND lv_mrp   = abap_false AND
                                  lv_frcst = abap_false AND
                                  lv_acct  = abap_false AND lv_sales = abap_false AND
                                  lv_basic = abap_false AND lv_class = abap_false ).

      "Plant (plant-level views: purchasing, MRP, plant/storage, accounting)
      IF <ls_row>-werks IS INITIAL AND
         ( lv_no_flag = abap_true OR lv_purch = abap_true OR lv_mrp = abap_true OR
           lv_frcst = abap_true OR lv_acct = abap_true ).
        DATA(lv_werks) = to_upper( get_value( iv_row = <ls_row>-row iv_field = gc_col-ref_werks ) ).
        IF lv_werks IS NOT INITIAL.
          INSERT VALUE #( row = <ls_row>-row field = gc_col-werks value = lv_werks ) INTO TABLE mt_cell.
          <ls_row>-werks = lv_werks.
          mo_log->add( iv_type = 'S' is_row = <ls_row> iv_field = gc_col-werks
                       iv_text = |Plant { lv_werks } taken from REF_WERKS| ).
        ENDIF.
      ENDIF.

      "Storage location (plant / storage view)
      IF lv_no_flag = abap_true OR lv_mrp = abap_true OR lv_purch = abap_true.
        IF get_value( iv_row = <ls_row>-row iv_field = gc_col-lgort ) IS INITIAL.
          DATA(lv_lgort) = to_upper( get_value( iv_row = <ls_row>-row iv_field = gc_col-ref_lgort ) ).
          IF lv_lgort IS NOT INITIAL.
            INSERT VALUE #( row = <ls_row>-row field = gc_col-lgort value = lv_lgort ) INTO TABLE mt_cell.
            mo_log->add( iv_type = 'S' is_row = <ls_row> iv_field = gc_col-lgort
                         iv_text = |Storage location { lv_lgort } taken from REF_LGORT| ).
          ENDIF.
        ENDIF.
      ENDIF.

      "Sales area (sales view)
      IF lv_no_flag = abap_true OR lv_sales = abap_true.
        IF <ls_row>-vkorg IS INITIAL.
          DATA(lv_vkorg) = to_upper( get_value( iv_row = <ls_row>-row iv_field = gc_col-ref_vkorg ) ).
          IF lv_vkorg IS NOT INITIAL.
            INSERT VALUE #( row = <ls_row>-row field = gc_col-vkorg value = lv_vkorg ) INTO TABLE mt_cell.
            <ls_row>-vkorg = lv_vkorg.
            mo_log->add( iv_type = 'S' is_row = <ls_row> iv_field = gc_col-vkorg
                         iv_text = |Sales organization { lv_vkorg } taken from REF_VKORG| ).
          ENDIF.
        ENDIF.
        IF <ls_row>-vtweg IS INITIAL.
          DATA(lv_vtweg) = to_upper( get_value( iv_row = <ls_row>-row iv_field = gc_col-ref_vtweg ) ).
          IF lv_vtweg IS NOT INITIAL.
            INSERT VALUE #( row = <ls_row>-row field = gc_col-vtweg value = lv_vtweg ) INTO TABLE mt_cell.
            <ls_row>-vtweg = lv_vtweg.
            mo_log->add( iv_type = 'S' is_row = <ls_row> iv_field = gc_col-vtweg
                         iv_text = |Distribution channel { lv_vtweg } taken from REF_VTWEG| ).
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_columns.
    "Mandatory fields of the view tables that are no template column (unless a
    "default value exists) are reported as errors.
    DATA(lt_ctrl) = lcl_config=>control_columns( ).

    "Columns not maintained in any selected view table

    "Mandatory fields that are no column of the template
    LOOP AT mo_config->mt_fcat INTO DATA(ls_fcat) WHERE mandatory = abap_true.
      CHECK NOT line_exists( mt_header[ table_line = ls_fcat-temp_field_name ] ).
      "a default value (ZTMM_DEFLT_DATA) fills the field in every row
      CHECK NOT line_exists( mo_config->mt_deflt[ KEY k_field COMPONENTS temp_field_name = ls_fcat-temp_field_name ] ).
      mo_log->add( iv_type = 'E' iv_view = ls_fcat-view iv_field = ls_fcat-temp_field_name
                   iv_fdesc = ls_fcat-description
                   iv_text = 'Mandatory field is not a column of the template' ).
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
* 5.5 - validation and mapping, row by row
*----------------------------------------------------------------------*
  METHOD validate_and_map.
    "Step 5.5: per template row copy the reference material, validate the fields
    "and map them to the BAPI structures (MT_BAPI).
    DATA(lv_fixed_comp) = 'ROW_NO  ACTION  STATUS  MESSAGE PROCESS_PROFILE REFERENCE_MATNR REF_WERKS REF_LGORT ' &&
          ' REF_VKORG  REF_VTWEG REF_EKORG DEFAULT_MODE  COPY_BASIC  COPY_PURCH  COPY_MRP  COPY_FRCST  COPY_SALES  COPY_ACCOUNTING COPY_CLASS DEFAULT_SUMMARY MATNR SALES_TEXT '.
    DATA: lt_split TYPE string_table,
          lt_comp  TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    SPLIT lv_fixed_comp AT space INTO TABLE lt_split.
    LOOP AT lt_split INTO DATA(lv_split) WHERE table_line IS NOT INITIAL.
      INSERT lv_split INTO TABLE lt_comp.
    ENDLOOP.
    CONSTANTS lc_org_params TYPE string VALUE
      ` PLANTDATA FORECASTPARAMETERS PLANNINGDATA STORAGELOCATIONDATA VALUATIONDATA WAREHOUSENUMBERDATA SALESDATA STORAGETYPEDATA TAXCLASSIFICATIONS `.

    "Mandatory fields of the field catalogue, with org.-level flag (once, not per row)
    TYPES: BEGIN OF lty_mand,
             fcat      TYPE ty_fcat,
             org_level TYPE abap_bool,
           END OF lty_mand.
    DATA lt_mand TYPE STANDARD TABLE OF lty_mand WITH EMPTY KEY.
    LOOP AT mo_config->mt_fcat INTO DATA(ls_mfcat) WHERE mandatory = abap_true.
      APPEND VALUE #( fcat = ls_mfcat ) TO lt_mand ASSIGNING FIELD-SYMBOL(<ls_mand>).
      LOOP AT ls_mfcat-targets INTO DATA(ls_mtgt).
        IF lc_org_params CS | { ls_mtgt-param } |.
          <ls_mand>-org_level = abap_true.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    "Existence of materials / org. levels: one SELECT per table
    prefetch_existence( ).

    LOOP AT mt_row INTO DATA(ls_row).
      DATA(ls_bapi) = VALUE ty_bapi( row = ls_row-row matkey = ls_row-matkey ).
      check_row_control( ls_row ).  "check Screen Fields with Template Fields

      "Reference material first (once per row) - template values mapped
      "below overwrite copied values
      copy_reference( EXPORTING is_row   = ls_row
                      IMPORTING es_ref   = DATA(ls_ref)
                                et_views = DATA(lt_ref_views)
                      CHANGING  cs_bapi  = ls_bapi ).
      LOOP AT mt_cell INTO DATA(ls_cell) WHERE row = ls_row-row.
        CHECK NOT line_exists( lt_comp[ table_line = ls_cell-field ] ).

        DATA(lt_fcat) = FILTER #( mo_config->mt_fcat USING KEY k_field WHERE temp_field_name = ls_cell-field ).

        LOOP AT lt_fcat INTO DATA(ls_fcat).
          IF ls_fcat IS NOT INITIAL.
            validate_row( EXPORTING is_row = ls_row is_fcat = ls_fcat CHANGING cs_bapi = ls_bapi ).
          ELSE.
            mo_log->add( iv_type = 'E'
                         is_row = ls_row
                         iv_field = ls_cell-field
                         iv_text = |The { ls_cell-field } is available in template but not maintained into config tables.| ).
          ENDIF.
        ENDLOOP.

      ENDLOOP.

      "Characteristics from the template columns CHAR_NAME_n / CHAR_VALUE_n
      "(independent of ZTMM_CLASS_DATA)
      collect_characteristics( EXPORTING is_row = ls_row CHANGING cs_bapi = ls_bapi ).

      "Table data of the reference for keys not given in the template
      copy_reference_tables( EXPORTING is_row   = ls_row
                                       is_ref   = ls_ref
                                       it_views = lt_ref_views
                             CHANGING  cs_bapi  = ls_bapi ).

      "Defaults for fields neither in the template nor copied from the reference
      apply_defaults( EXPORTING is_row = ls_row CHANGING cs_bapi = ls_bapi ).
      apply_unit_defaults( EXPORTING is_row = ls_row CHANGING cs_bapi = ls_bapi ).
      apply_current_date( EXPORTING is_row = ls_row CHANGING cs_bapi = ls_bapi ).

      "Sales text (text object MVKE): not part of the BAPI, saved after the material
      check_sales_text( ls_row ).

      "Classification: values, class master, single values
      check_classification( EXPORTING is_row = ls_row CHANGING cs_bapi = ls_bapi ).

      "Mandatory fields without value in this row - the cell loop above only
      "sees filled cells. Columns missing in the template: see CHECK_COLUMNS
      LOOP AT lt_mand INTO DATA(ls_mrec).
        DATA(ls_mand) = ls_mrec-fcat.
        CHECK line_exists( mt_header[ table_line = ls_mand-temp_field_name ] ).
        CHECK is_available( iv_row = ls_row-row iv_field = ls_mand-temp_field_name ) = abap_false.

        "Client-level field (no org. level target): one row of the material
        "is enough (BUILD_CALL merges client data); not sent at all by Extend
        IF ls_mrec-org_level = abap_false.
          CHECK lcl_screen=>get_operation( ) <> gc_op-extend.
          DATA(lv_in_other_row) = abap_false.
          LOOP AT mt_row INTO DATA(ls_other) USING KEY k_mat WHERE matkey = ls_row-matkey.
            IF is_available( iv_row = ls_other-row iv_field = ls_mand-temp_field_name ) = abap_true.
              lv_in_other_row = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
          CHECK lv_in_other_row = abap_false.
        ENDIF.

        mo_log->add( iv_type = 'E' is_row = ls_row iv_view = ls_mand-view
                     iv_field = ls_mand-temp_field_name iv_fdesc = ls_mand-description
                     iv_text = |{ ls_mand-temp_field_name } ({ ls_mand-description }) is mandatory| ).
      ENDLOOP.

      check_existence( is_row = ls_row is_bapi = ls_bapi ).

      APPEND ls_bapi TO mt_bapi.
    ENDLOOP.

    "Rows of the same material: conflicting characteristic values
    check_class_conflicts( ).
  ENDMETHOD.

  METHOD prefetch_existence.
    "Read the existence data of all template materials (and reference materials)
    "once per table instead of one SELECT SINGLE per template row.
    DATA: lt_matnr TYPE tt_matnr_set,
          lv_matnr TYPE matnr.

    CLEAR: mt_ex_mara, mt_ex_marc, mt_ex_mvke, mt_ex_mard, mt_ex_mbew, mt_ex_mlgn.

    LOOP AT mt_row INTO DATA(ls_row).
      DATA(lt_keys) = VALUE string_table( ( COND #( WHEN lcl_mapper=>is_dummy_key( ls_row-matkey ) = abap_false
                                                    THEN ls_row-matkey ) )
                                          ( to_upper( get_value( iv_row = ls_row-row iv_field = gc_col-ref_matnr ) ) ) ).
      LOOP AT lt_keys INTO DATA(lv_key) WHERE table_line IS NOT INITIAL.
        CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
          EXPORTING
            input  = lv_key
          IMPORTING
            output = lv_matnr
          EXCEPTIONS
            OTHERS = 1.
        IF sy-subrc = 0.                                   "invalid numbers are reported per row
          INSERT lv_matnr INTO TABLE lt_matnr.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    CHECK lt_matnr IS NOT INITIAL.

    DATA(lt_for) = VALUE tt_matnr_list( FOR lv_m IN lt_matnr ( matnr = lv_m ) ).

    SELECT matnr, mtart, mbrsh FROM mara
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_mara.
    SELECT matnr, werks FROM marc
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_marc.
    SELECT matnr, vkorg, vtweg FROM mvke
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_mvke.
    SELECT matnr, werks, lgort FROM mard
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_mard.
    SELECT matnr, bwkey, bwtar FROM mbew
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_mbew.
    SELECT matnr, lgnum FROM mlgn
      FOR ALL ENTRIES IN @lt_for WHERE matnr = @lt_for-matnr
      INTO CORRESPONDING FIELDS OF TABLE @mt_ex_mlgn.
  ENDMETHOD.

  METHOD check_sales_text.
    "SALES_TEXT: long text of the sales area (text object MVKE, ID 0001). It is saved
    "per sales area after the material, so the row needs sales organization and
    "distribution channel and the sales view must be selected.
    CHECK get_value( iv_row = is_row-row iv_field = gc_col-sales_text ) IS NOT INITIAL.

    IF p_sales = abap_false.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-sales_text
                   iv_text = 'SALES_TEXT can not be saved - sales view is not selected' ).
    ENDIF.
    IF is_row-vkorg IS INITIAL OR is_row-vtweg IS INITIAL.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-sales_text
                   iv_text = 'SALES_TEXT needs sales organization (VKORG) and distribution channel (VTWEG)' ).
    ENDIF.
  ENDMETHOD.

  METHOD check_row_control.
    "Check the control columns of a row: ACTION against the operation on the screen,
    "COPY_* flags and reference columns.
    DATA(lv_opid) = lcl_screen=>get_operation( ).

    "ACTION column must match the action selected on the screen
    DATA(lv_action) = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-action ) ).
    IF lv_action IS NOT INITIAL.
      DATA(lv_row_op) = COND z_de_op_id(
        WHEN lv_action = 'C' OR lv_action = 'CREATE'                        THEN gc_op-create
        WHEN lv_action = 'U' OR lv_action = 'UPDATE' OR lv_action = 'CHANGE' THEN gc_op-update
        WHEN lv_action = 'E' OR lv_action = 'EXTEND'                        THEN gc_op-extend
        ELSE '?' ).
      IF lv_row_op <> lv_opid.
        mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-action
                     iv_text = |Row action '{ lv_action }' does not match the action selected on the screen| ).
      ENDIF.
    ENDIF.

    "MTART / MBRSH in the template must match the selection screen
    DATA(lv_mtart) = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-mtart ) ).
    IF lv_mtart IS NOT INITIAL AND lv_mtart <> p_mtart.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-mtart
                   iv_text = |Material type { lv_mtart } differs from selection { p_mtart }| ).
    ENDIF.
    DATA(lv_mbrsh) = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-mbrsh ) ).
    IF lv_mbrsh IS NOT INITIAL AND lv_mbrsh <> p_indsec.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-mbrsh
                   iv_text = |Industry sector { lv_mbrsh } differs from selection { p_indsec }| ).
    ENDIF.

    "Update / Extend need a material number
    IF lv_opid <> gc_op-create AND lcl_mapper=>is_dummy_key( is_row-matkey ) = abap_true.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-matnr
                   iv_text = 'MATNR is required for Update / Extend' ).
    ENDIF.

    "Reference / copy columns
    IF get_value( iv_row = is_row-row iv_field = gc_col-ref_matnr ) = `` AND
       ( is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_basic ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_purch ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_mrp   ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_frcst ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_sales ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_acct  ) = abap_true OR
         is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_class ) = abap_true ).
      mo_log->add( iv_type = 'W' is_row = is_row iv_field = gc_col-ref_matnr
                   iv_text = 'COPY_* flags ignored - no REFERENCE_MATNR given' ).
    ENDIF.
    IF get_value( iv_row = is_row-row iv_field = gc_col-ref_ekorg ) <> ``.
      mo_log->add( iv_type = 'W' is_row = is_row iv_field = gc_col-ref_ekorg
                   iv_text = 'REF_EKORG ignored - purchasing org. data is not part of BAPI_MATERIAL_SAVEREPLICA' ).
    ENDIF.
  ENDMETHOD.

  METHOD copy_reference.
    "Reference material (REFERENCE_MATNR): every field of the views to be
    "copied is taken from the template if given there, otherwise from the
    "reference material. Runs before the template values are mapped, so
    "template values always overwrite copied ones.
    "Views: COPY_* flags; no flag set -> all views selected on the screen
    "(classification: see COPY_REFERENCE_CLASS).
    "Org. levels of the reference: REF_WERKS / REF_VKORG / REF_VTWEG,
    "default = plant / sales area of the template row.
    FIELD-SYMBOLS: <ls_src> TYPE any,
                   <lv_src> TYPE any,
                   <ls_tgt> TYPE any,
                   <lv_tgt> TYPE any.
    CONSTANTS:
      lc_org_keys    TYPE string VALUE
        ` MATERIAL MATERIAL_LONG PLANT SALES_ORG DISTR_CHAN VAL_AREA VAL_TYPE STGE_LOC WHSE_NO STGE_TYPE `,
      lc_plant_views TYPE string VALUE ` PURCH MRP FRCST PLNTST `.
    DATA: lv_refmat   TYPE matnr,
          lv_explicit TYPE abap_bool,
          lv_bwkey    TYPE bwkey,
          lv_ref_lgort TYPE lgort_d.

    CLEAR: es_ref, et_views.

    DATA(lv_ref) = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_matnr ) ).
    CHECK lv_ref IS NOT INITIAL.

    "--- 1. views to be copied
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_basic ) = abap_true.
      INSERT gc_view-basic INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_purch ) = abap_true.
      INSERT gc_view-purch INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_mrp ) = abap_true.
      INSERT gc_view-mrp INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_frcst ) = abap_true.
      INSERT gc_view-frcst INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_sales ) = abap_true.
      INSERT gc_view-sales INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_acct ) = abap_true.
      INSERT gc_view-val INTO TABLE et_views.
    ENDIF.
    IF is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_class ) = abap_true.
      INSERT gc_view-class INTO TABLE et_views.
    ENDIF.

    IF et_views IS NOT INITIAL.
      lv_explicit = abap_true.
    ELSE.
      LOOP AT lcl_config=>view_tables( ) INTO DATA(ls_vt) WHERE active = abap_true.
        INSERT ls_vt-view INTO TABLE et_views.
      ENDLOOP.
    ENDIF.
    IF p_class = abap_false.
      DELETE et_views WHERE table_line = gc_view-class.       "classification not selected
    ENDIF.

    "Missing reference data: error if the view was requested explicitly
    DATA(lv_msgty) = COND symsgty( WHEN lv_explicit = abap_true THEN 'E' ELSE 'W' ).

    "Extend does not change client-level data (see BUILD_CALL)
    IF lcl_screen=>get_operation( ) = gc_op-extend AND
       line_exists( et_views[ table_line = gc_view-basic ] ).
      DELETE et_views WHERE table_line = gc_view-basic.
      IF lv_explicit = abap_true.
        mo_log->add( iv_type = 'W' is_row = is_row iv_field = gc_col-copy_basic
                     iv_text = 'COPY_BASIC ignored - Extend does not change basic data' ).
      ENDIF.
    ENDIF.
    CHECK et_views IS NOT INITIAL.

    "--- 2. reference material
    CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
      EXPORTING
        input  = lv_ref
      IMPORTING
        output = lv_refmat
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc <> 0.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-ref_matnr
                   iv_text = |Invalid reference material { lv_ref }| ).
      CLEAR et_views.
      RETURN.
    ENDIF.

    READ TABLE mt_ex_mara INTO DATA(ls_ref_mara) WITH TABLE KEY matnr = lv_refmat.
    IF sy-subrc <> 0.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-ref_matnr
                   iv_text = |Reference material { lv_ref } does not exist| ).
      CLEAR et_views.
      RETURN.
    ENDIF.
    IF ls_ref_mara-mtart <> p_mtart.
      mo_log->add( iv_type = 'W' is_row = is_row iv_field = gc_col-ref_matnr
                   iv_text = |Reference material has type { ls_ref_mara-mtart } - selection is { p_mtart }| ).
    ENDIF.

    "--- 3. org. levels of the reference (default: those of the template row)
    DATA(lv_ref_werks) = CONV werks_d( to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_werks ) ) ).
    DATA(lv_ref_vkorg) = CONV vkorg(   to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_vkorg ) ) ).
    DATA(lv_ref_vtweg) = CONV vtweg(   to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_vtweg ) ) ).
    IF lv_ref_werks IS INITIAL.
      lv_ref_werks = is_row-werks.
    ENDIF.
    IF lv_ref_vkorg IS INITIAL.
      lv_ref_vkorg = is_row-vkorg.
    ENDIF.
    IF lv_ref_vtweg IS INITIAL.
      lv_ref_vtweg = is_row-vtweg.
    ENDIF.
    lv_bwkey = lv_ref_werks.                                 "valuation area = plant
    lv_ref_lgort = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_lgort ) ).
    IF lv_ref_lgort IS INITIAL.
      lv_ref_lgort = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-lgort ) ).
    ENDIF.

    "Plant level (purchasing, MRP, plant/storage; sales fields of MARC)
    IF lv_ref_werks IS NOT INITIAL.
      IF NOT line_exists( mt_ex_marc[ matnr = lv_refmat werks = lv_ref_werks ] ).
        LOOP AT et_views INTO DATA(lv_view).
          CHECK lc_plant_views CS | { lv_view } |.
          mo_log->add( iv_type = lv_msgty is_row = is_row iv_field = gc_col-ref_werks iv_view = lv_view
                       iv_text = |Reference { lv_ref } not maintained in plant { lv_ref_werks } - view not copied| ).
          DELETE et_views.
        ENDLOOP.
        CLEAR lv_ref_werks.                                  "no plant data from the reference
      ENDIF.
    ELSE.
      LOOP AT et_views INTO lv_view.
        CHECK lc_plant_views CS | { lv_view } |.
        mo_log->add( iv_type = lv_msgty is_row = is_row iv_field = gc_col-ref_werks iv_view = lv_view
                     iv_text = 'No reference plant (REF_WERKS / WERKS) - view not copied' ).
        DELETE et_views.
      ENDLOOP.
    ENDIF.

    "Storage location of the reference (REF_LGORT, default LGORT of the row)
    IF lv_ref_lgort IS NOT INITIAL.
      SELECT SINGLE * FROM mard INTO @DATA(ls_ref_mard)
        WHERE matnr = @lv_refmat AND werks = @lv_ref_werks AND lgort = @lv_ref_lgort.
      IF sy-subrc <> 0 OR lv_ref_werks IS INITIAL.
        IF get_value( iv_row = is_row-row iv_field = gc_col-ref_lgort ) <> ``.
          mo_log->add( iv_type = lv_msgty is_row = is_row iv_field = gc_col-ref_lgort iv_view = gc_view-plntst
                       iv_text = |Reference { lv_ref } not maintained in storage location | &&
                                 |{ lv_ref_werks }/{ lv_ref_lgort } - storage data not copied| ).
        ENDIF.
        CLEAR: lv_ref_lgort, ls_ref_mard.
      ENDIF.
    ENDIF.

    "Valuation
    IF line_exists( et_views[ table_line = gc_view-val ] ).
      IF lv_bwkey IS INITIAL OR
         NOT line_exists( mt_ex_mbew[ matnr = lv_refmat bwkey = lv_bwkey bwtar = space ] ).
        mo_log->add( iv_type = lv_msgty is_row = is_row iv_field = gc_col-ref_werks iv_view = gc_view-val
                     iv_text = |Reference { lv_ref } has no valuation data for valuation area '{ lv_bwkey }' - view not copied| ).
        DELETE et_views WHERE table_line = gc_view-val.
        CLEAR lv_bwkey.
      ENDIF.
    ENDIF.

    "Sales area
    IF line_exists( et_views[ table_line = gc_view-sales ] ).
      IF lv_ref_vkorg IS INITIAL OR lv_ref_vtweg IS INITIAL OR
         NOT line_exists( mt_ex_mvke[ matnr = lv_refmat vkorg = lv_ref_vkorg vtweg = lv_ref_vtweg ] ).
        "no sales data at the reference: warning only (other rows may have it)
        mo_log->add( iv_type = 'W' is_row = is_row iv_field = gc_col-ref_vkorg iv_view = gc_view-sales
                     iv_text = |Reference { lv_ref } has no sales data for sales area | &&
                               |'{ lv_ref_vkorg }/{ lv_ref_vtweg }' - view not copied| ).
        DELETE et_views WHERE table_line = gc_view-sales.
      ENDIF.
    ENDIF.
    IF NOT line_exists( et_views[ table_line = gc_view-sales ] ).
      CLEAR: lv_ref_vkorg, lv_ref_vtweg.
    ENDIF.
    IF NOT line_exists( et_views[ table_line = gc_view-val ] ).
      CLEAR lv_bwkey.
    ENDIF.
    CHECK et_views IS NOT INITIAL.

    "--- 4. read the reference
    TRY.
        es_ref = mo_bapi->get_reference( iv_matnr = lv_refmat
                                         iv_werks = lv_ref_werks
                                         iv_vkorg = lv_ref_vkorg
                                         iv_vtweg = lv_ref_vtweg
                                         iv_bwkey = lv_bwkey ).
      CATCH lcx_error INTO DATA(lx_error).
        mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-ref_matnr
                     iv_text = lx_error->get_text( ) ).
        CLEAR et_views.
        RETURN.
    ENDTRY.

    "storage location data of the reference (not part of BAPI_MATERIAL_GET_ALL)
    IF ls_ref_mard IS NOT INITIAL AND line_exists( et_views[ table_line = gc_view-plntst ] ).
      MOVE-CORRESPONDING ls_ref_mard TO es_ref-storagelocationdata.
      es_ref-storagelocationdata-material = lv_refmat.
      es_ref-storagelocationdata-plant    = ls_ref_mard-werks.
      es_ref-storagelocationdata-stge_loc = ls_ref_mard-lgort.
    ENDIF.

    "--- 5. single fields: configured fields of the views, no template value
    LOOP AT mo_config->mt_fcat INTO DATA(ls_fcat) WHERE system_derived = abap_false.
      CHECK line_exists( et_views[ table_line = ls_fcat-view ] ).
      CHECK NOT line_exists( mt_cell[ row = is_row-row field = ls_fcat-temp_field_name ] ).

      LOOP AT ls_fcat-targets INTO DATA(ls_target) WHERE table = abap_false.
        CHECK lc_org_keys NS | { ls_target-comp } |.        "never copy org. keys
        ASSIGN COMPONENT ls_target-param OF STRUCTURE es_ref TO <ls_src>.
        CHECK sy-subrc = 0.
        ASSIGN COMPONENT ls_target-comp OF STRUCTURE <ls_src> TO <lv_src>.
        CHECK sy-subrc = 0.
        CHECK <lv_src> IS NOT INITIAL.
        ASSIGN COMPONENT ls_target-param OF STRUCTURE cs_bapi TO <ls_tgt>.
        CHECK sy-subrc = 0.
        ASSIGN COMPONENT ls_target-comp OF STRUCTURE <ls_tgt> TO <lv_tgt>.
        CHECK sy-subrc = 0.
        <lv_tgt> = <lv_src>.
        INSERT VALUE #( row = is_row-row field = ls_fcat-temp_field_name ) INTO TABLE mt_copied.
        INSERT ls_fcat-view INTO TABLE cs_bapi-views.
      ENDLOOP.
    ENDLOOP.

    mo_log->add( iv_type = 'S' is_row = is_row iv_field = gc_col-ref_matnr
                 iv_text = |Reference { lv_ref } copied for view(s) { concat_lines_of( table = et_views sep = `, ` ) }| ).
  ENDMETHOD.

  METHOD copy_reference_tables.
    "Table data of the reference (after the template values are mapped):
    "only lines whose key is not given in the template are added
    "  descriptions (BASIC)      - per language
    "  units of measure (BASIC)  - per alternative unit, same base unit only
    "  long texts               - material-level texts per text ID
    "                              (BEST -> PURCH, others -> BASIC)
    "  tax classifications (SALES) - per country
    "  classification (CLASS)    - see COPY_REFERENCE_CLASS
    "EANs are never copied (must be unique per material)
    FIELD-SYMBOLS: <ls_line> TYPE any,
                   <lv_src>  TYPE any,
                   <lv_tgt>  TYPE any,
                   <lt_tab>  TYPE STANDARD TABLE.
    DATA: lv_copied   TYPE abap_bool,
          lt_text_new LIKE cs_bapi-materiallongtext,
          lt_params   TYPE SORTED TABLE OF fieldname WITH UNIQUE KEY table_line.

    CHECK it_views IS NOT INITIAL.

    DATA(lv_basic) = xsdbool( line_exists( it_views[ table_line = gc_view-basic ] ) ).
    DATA(lv_purch) = xsdbool( line_exists( it_views[ table_line = gc_view-purch ] ) ).
    DATA(lv_sales) = xsdbool( line_exists( it_views[ table_line = gc_view-sales ] ) ).

    "Descriptions
    IF lv_basic = abap_true.
      LOOP AT is_ref-materialdescription INTO DATA(ls_makt).
        CHECK NOT line_exists( cs_bapi-materialdescription[ langu = ls_makt-langu ] ).
        CHECK NOT ( ls_makt-langu = sy-langu AND
                    line_exists( cs_bapi-materialdescription[ langu = space ] ) ).  "template line, default language
        APPEND ls_makt TO cs_bapi-materialdescription.
        INSERT CONV fieldname( 'MATERIALDESCRIPTION' ) INTO TABLE lt_params.
      ENDLOOP.
    ENDIF.

    "Units of measure - ratios refer to the base unit of the reference.
    "Gross weight, volume and dimensions are unit data (MARM), not client
    "data: a unit given in the template (e.g. base unit line from MEINS)
    "keeps its values, its empty fields are filled from the reference
    IF lv_basic = abap_true AND
       ( cs_bapi-clientdata-base_uom IS INITIAL OR
         cs_bapi-clientdata-base_uom = is_ref-clientdata-base_uom ).
      LOOP AT is_ref-unitsofmeasure INTO DATA(ls_marm).
        "template line of this unit (no unit in the template line = base unit)
        READ TABLE cs_bapi-unitsofmeasure ASSIGNING <ls_line>
             WITH KEY alt_unit = ls_marm-alt_unit.
        IF sy-subrc <> 0 AND ls_marm-alt_unit = is_ref-clientdata-base_uom.
          READ TABLE cs_bapi-unitsofmeasure ASSIGNING <ls_line>
               WITH KEY alt_unit = space.
        ENDIF.
        IF sy-subrc <> 0.
          APPEND ls_marm TO cs_bapi-unitsofmeasure.
        ELSE.
          DO.
            ASSIGN COMPONENT sy-index OF STRUCTURE ls_marm TO <lv_src>.
            IF sy-subrc <> 0.
              EXIT.
            ENDIF.
            ASSIGN COMPONENT sy-index OF STRUCTURE <ls_line> TO <lv_tgt>.
            IF sy-subrc = 0 AND <lv_tgt> IS INITIAL AND <lv_src> IS NOT INITIAL.
              <lv_tgt> = <lv_src>.                         "template value wins
            ENDIF.
          ENDDO.
        ENDIF.
        INSERT CONV fieldname( 'UNITSOFMEASURE' ) INTO TABLE lt_params.
      ENDLOOP.
    ELSEIF lv_basic = abap_true AND is_ref-unitsofmeasure IS NOT INITIAL.
      mo_log->add( iv_type = 'W' is_row = is_row iv_view = gc_view-basic
                   iv_text = |Units of measure of the reference not copied - base unit | &&
                             |{ cs_bapi-clientdata-base_uom } differs from { is_ref-clientdata-base_uom }| ).
    ENDIF.

    "Long texts on material level (object MATERIAL - no sales texts)
    LOOP AT is_ref-materiallongtext INTO DATA(ls_text).
      CHECK ls_text-applobject IS INITIAL OR ls_text-applobject = 'MATERIAL'.
      DATA(lv_text_view) = COND #( WHEN ls_text-text_id = 'BEST' THEN gc_view-purch ELSE gc_view-basic ).
      CHECK ( lv_text_view = gc_view-basic AND lv_basic = abap_true ) OR
            ( lv_text_view = gc_view-purch AND lv_purch = abap_true ).
      "text ID given in the template (no ID = basic data text, see BUILD_CALL)
      CHECK NOT line_exists( cs_bapi-materiallongtext[ text_id = ls_text-text_id ] ).
      CHECK NOT ( ls_text-text_id = 'BEST' AND
                  line_exists( cs_bapi-materiallongtext[ text_id = space ] ) ).
      CLEAR ls_text-text_name.                          "set to the new material in BUILD_CALL
      APPEND ls_text TO lt_text_new.
    ENDLOOP.
    IF lt_text_new IS NOT INITIAL.
      APPEND LINES OF lt_text_new TO cs_bapi-materiallongtext.
      INSERT CONV fieldname( 'MATERIALLONGTEXT' ) INTO TABLE lt_params.
    ENDIF.

    "Tax classifications
    IF lv_sales = abap_true.
      LOOP AT is_ref-taxclassifications INTO DATA(ls_mlan).
        READ TABLE cs_bapi-taxclassifications ASSIGNING <ls_line>
             WITH KEY depcountry = ls_mlan-depcountry.
        "no country in the reference line: cannot be compared - take every line
        IF sy-subrc <> 0 OR ls_mlan-depcountry IS INITIAL.
          APPEND ls_mlan TO cs_bapi-taxclassifications.
          INSERT CONV fieldname( 'TAXCLASSIFICATIONS' ) INTO TABLE lt_params.
          CONTINUE.
        ENDIF.
        "country already in the template: add the tax type / class pairs
        "(TAX_TYPE_n / TAXCLASS_n) the template line does not have
        DO 9 TIMES.
          DATA(lv_tt) = |TAX_TYPE_{ sy-index }|.
          DATA(lv_tc) = |TAXCLASS_{ sy-index }|.
          ASSIGN COMPONENT lv_tt OF STRUCTURE ls_mlan TO <lv_src>.
          CHECK sy-subrc = 0 AND <lv_src> IS NOT INITIAL.
          DATA(lv_type) = CONV string( <lv_src> ).
          ASSIGN COMPONENT lv_tc OF STRUCTURE ls_mlan TO <lv_src>.
          CHECK sy-subrc = 0.
          DATA(lv_class) = CONV string( <lv_src> ).
          "tax type already in the template line?
          DATA(lv_have) = abap_false.
          DO 9 TIMES.
            DATA(lv_nt) = |TAX_TYPE_{ sy-index }|.
            ASSIGN COMPONENT lv_nt OF STRUCTURE <ls_line> TO <lv_tgt>.
            IF sy-subrc = 0 AND <lv_tgt> = lv_type.
              lv_have = abap_true.
            ENDIF.
          ENDDO.
          CHECK lv_have = abap_false.
          "free slot (type and class empty) in the template line
          DO 9 TIMES.
            DATA(lv_ft) = |TAX_TYPE_{ sy-index }|.
            DATA(lv_fc) = |TAXCLASS_{ sy-index }|.
            ASSIGN COMPONENT lv_ft OF STRUCTURE <ls_line> TO <lv_tgt>.
            CHECK sy-subrc = 0 AND <lv_tgt> IS INITIAL.
            ASSIGN COMPONENT lv_fc OF STRUCTURE <ls_line> TO <lv_src>.
            CHECK sy-subrc = 0 AND <lv_src> IS INITIAL.
            <lv_tgt> = lv_type.
            <lv_src> = lv_class.
            INSERT CONV fieldname( 'TAXCLASSIFICATIONS' ) INTO TABLE lt_params.
            EXIT.
          ENDDO.
        ENDDO.
      ENDLOOP.
    ENDIF.

    "Classification
    IF line_exists( it_views[ table_line = gc_view-class ] ).
      copy_reference_class( EXPORTING is_row    = is_row
                            IMPORTING et_params = DATA(lt_cl_params)
                            CHANGING  cs_bapi   = cs_bapi ).
      LOOP AT lt_cl_params INTO DATA(lv_cl_param).
        INSERT lv_cl_param INTO TABLE lt_params.
      ENDLOOP.
    ENDIF.

    CHECK lt_params IS NOT INITIAL.

    "Fields whose target now has a value from the reference count as given
    "(mandatory check) and their view is created
    LOOP AT mo_config->mt_fcat INTO DATA(ls_fcat).
      CHECK line_exists( it_views[ table_line = ls_fcat-view ] ).
      CHECK NOT line_exists( mt_cell[ row = is_row-row field = ls_fcat-temp_field_name ] ).
      CLEAR lv_copied.
      LOOP AT ls_fcat-targets INTO DATA(ls_target) WHERE table = abap_true OR param = 'CLASSKEY'.
        CHECK line_exists( lt_params[ table_line = ls_target-param ] ).
        IF ls_target-table = abap_false.                        "class key of the reference
          ASSIGN COMPONENT ls_target-param OF STRUCTURE cs_bapi TO <ls_line>.
          CHECK sy-subrc = 0.
          ASSIGN COMPONENT ls_target-comp OF STRUCTURE <ls_line> TO <lv_tgt>.
          IF sy-subrc = 0 AND <lv_tgt> IS NOT INITIAL.
            lv_copied = abap_true.
          ENDIF.
          CONTINUE.
        ENDIF.
        ASSIGN COMPONENT ls_target-param OF STRUCTURE cs_bapi TO <lt_tab>.
        CHECK sy-subrc = 0.
        LOOP AT <lt_tab> ASSIGNING <ls_line>.
          "line of this field only (fixed values, e.g. CHARACT=COLOR)
          DATA(lv_match) = abap_true.
          LOOP AT ls_target-fixed INTO DATA(ls_fix).
            ASSIGN COMPONENT ls_fix-comp OF STRUCTURE <ls_line> TO <lv_src>.
            IF sy-subrc <> 0 OR <lv_src> <> ls_fix-value.
              lv_match = abap_false.
              EXIT.
            ENDIF.
          ENDLOOP.
          CHECK lv_match = abap_true.
          ASSIGN COMPONENT ls_target-comp OF STRUCTURE <ls_line> TO <lv_tgt>.
          IF sy-subrc = 0 AND <lv_tgt> IS NOT INITIAL.
            lv_copied = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      CHECK lv_copied = abap_true.
      INSERT VALUE #( row = is_row-row field = ls_fcat-temp_field_name ) INTO TABLE mt_copied.
      INSERT ls_fcat-view INTO TABLE cs_bapi-views.
    ENDLOOP.
  ENDMETHOD.

  METHOD validate_row.
    "Step 5.5.1 - one pass over the field catalogue of all selected views

    DATA(ls_fcat)     = is_fcat.
    DATA(lv_value)    = get_value( iv_row = is_row-row iv_field = ls_fcat-temp_field_name ).
    DATA(lv_supplied) = COND abap_bool( WHEN lv_value IS NOT INITIAL THEN abap_true ELSE abap_false ).

    IF ls_fcat-mandatory = abap_true.
      IF lv_supplied = abap_true.
        map_field( EXPORTING is_row = is_row is_fcat = ls_fcat iv_value = lv_value
                   CHANGING  cs_bapi = cs_bapi ).
      ELSEIF is_available( iv_row = is_row-row iv_field = ls_fcat-temp_field_name ) = abap_false.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = ls_fcat-view
                     iv_field = ls_fcat-temp_field_name iv_fdesc = ls_fcat-description
                     iv_text = |{ ls_fcat-temp_field_name } ({ ls_fcat-description }) is mandatory| ).
      ENDIF.

    ELSEIF ls_fcat-optional = abap_true.
      IF lv_supplied = abap_true.
        map_field( EXPORTING is_row = is_row is_fcat = ls_fcat iv_value = lv_value
                   CHANGING  cs_bapi = cs_bapi ).
      ENDIF.

    ELSEIF ls_fcat-system_derived = abap_true.
      "derived by the system - nothing to do
      IF lv_supplied = abap_true.
        map_field( EXPORTING is_row = is_row is_fcat = ls_fcat iv_value = lv_value
                   CHANGING  cs_bapi = cs_bapi ).
      ENDIF.

    ELSEIF ls_fcat-cond_mandatory = abap_true.
      IF lv_supplied = abap_true.
        map_field( EXPORTING is_row = is_row is_fcat = ls_fcat iv_value = lv_value
                   CHANGING  cs_bapi = cs_bapi ).
      ENDIF.
      check_cond_mandatory( is_row      = is_row
                            is_fcat     = ls_fcat
                            iv_supplied = is_available( iv_row   = is_row-row
                                                        iv_field = ls_fcat-temp_field_name ) ).

    ELSE.
      "no flag maintained -> handled like optional
      IF lv_supplied = abap_true.
        map_field( EXPORTING is_row = is_row is_fcat = ls_fcat iv_value = lv_value
                   CHANGING  cs_bapi = cs_bapi ).
      ENDIF.
    ENDIF.

    "Classification consistency: CHECK_CLASSIFICATION (once all values of
    "the row are mapped - the class may come from a later column, the
    "reference material or the default table)
  ENDMETHOD.

  METHOD collect_characteristics.
    "Template columns CHAR_NAME_n / CHAR_VALUE_n (n = 1, 2, ... any number):
    "pair n = characteristic name + its value. The columns need no entry in
    "ZTMM_CLASS_DATA (only CLASS_TYPE / CLASS_NAME do). The lines are added
    "as text lines; CHECK_CLASSIFICATION reads the format of the
    "characteristic in SAP (CABN) and moves numeric / date / time /
    "currency values to the matching BAPI table.
    "Columns that ARE maintained in ZTMM_CLASS_DATA are mapped there.
    TYPES: BEGIN OF lty_pair,
             n     TYPE i,
             name  TYPE string,
             value TYPE string,
           END OF lty_pair.
    DATA: lt_pair  TYPE SORTED TABLE OF lty_pair WITH UNIQUE KEY n,
          ls_probe TYPE bapi1003_alloc_values_char.

    CHECK p_class = abap_true.
    DESCRIBE FIELD ls_probe-value_char LENGTH DATA(lv_max) IN CHARACTER MODE.

    LOOP AT mt_cell INTO DATA(ls_cell) WHERE row = is_row-row.
      DATA(lv_kind) = COND string( WHEN ls_cell-field CP 'CHAR_NAME_*'  THEN `N`
                                   WHEN ls_cell-field CP 'CHAR_VALUE_*' THEN `V` ).
      CHECK lv_kind IS NOT INITIAL.
      CHECK NOT line_exists( mo_config->mt_fcat[ KEY k_field COMPONENTS temp_field_name = ls_cell-field ] ).
      DATA(lv_num) = substring_after( val = CONV string( ls_cell-field ) sub = `_` occ = 2 ).
      CHECK lv_num IS NOT INITIAL AND lv_num CO '0123456789'.
      DATA(lv_n) = CONV i( lv_num ).

      ASSIGN lt_pair[ n = lv_n ] TO FIELD-SYMBOL(<ls_pair>).
      IF sy-subrc <> 0.
        INSERT VALUE #( n = lv_n ) INTO TABLE lt_pair ASSIGNING <ls_pair>.
      ENDIF.
      IF lv_kind = `N`.
        <ls_pair>-name = to_upper( lcl_mapper=>trim( ls_cell-value ) ).
      ELSE.
        <ls_pair>-value = lcl_mapper=>trim( ls_cell-value ).
      ENDIF.
    ENDLOOP.

    LOOP AT lt_pair ASSIGNING <ls_pair>.
      IF <ls_pair>-name IS INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_field = |CHAR_VALUE_{ <ls_pair>-n }|
                     iv_text = |Characteristic value '{ <ls_pair>-value }' without characteristic name | &&
                               |(CHAR_NAME_{ <ls_pair>-n })| ).
        CONTINUE.
      ENDIF.
      IF <ls_pair>-value IS INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_field = |CHAR_NAME_{ <ls_pair>-n }|
                     iv_text = |Characteristic { <ls_pair>-name } without value (CHAR_VALUE_{ <ls_pair>-n })| ).
        CONTINUE.
      ENDIF.
      IF strlen( <ls_pair>-value ) > lv_max.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_field = |CHAR_VALUE_{ <ls_pair>-n }|
                     iv_text = |Value of { <ls_pair>-name } is longer than { lv_max } characters| ).
        CONTINUE.
      ENDIF.
      APPEND VALUE #( charact = <ls_pair>-name value_char = <ls_pair>-value )
        TO cs_bapi-allocvalueschar.
      INSERT gc_view-class INTO TABLE cs_bapi-views.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_classification.
    "Classification of one row - runs after template, reference and default
    "values are mapped:
    "  1. values without characteristic name / without class
    "  2. class, characteristics and values against the class master,
    "     single-value characteristics with one value only
    DATA lt_used TYPE STANDARD TABLE OF atnam WITH EMPTY KEY.

    CHECK p_class = abap_true.

    "--- 0. names in upper case (as in the class master)
    cs_bapi-classkey-classnum = to_upper( cs_bapi-classkey-classnum ).
    LOOP AT cs_bapi-allocvalueschar ASSIGNING FIELD-SYMBOL(<ls_uc>).
      <ls_uc>-charact = to_upper( <ls_uc>-charact ).
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluesnum ASSIGNING FIELD-SYMBOL(<ls_un>).
      <ls_un>-charact = to_upper( <ls_un>-charact ).
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluescurr ASSIGNING FIELD-SYMBOL(<ls_uu>).
      <ls_uu>-charact = to_upper( <ls_uu>-charact ).
    ENDLOOP.

    "--- 1. values without characteristic name / without class
    LOOP AT cs_bapi-allocvalueschar INTO DATA(ls_char) WHERE charact IS INITIAL.
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Characteristic value '{ ls_char-value_char }' without characteristic name| ).
    ENDLOOP.
    LOOP AT cs_bapi-allocvalueschar INTO ls_char WHERE charact IS NOT INITIAL AND value_char IS INITIAL.
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Characteristic { ls_char-charact } without value| ).
    ENDLOOP.
    IF line_exists( cs_bapi-allocvaluesnum[ charact = space ] ) OR
       line_exists( cs_bapi-allocvaluescurr[ charact = space ] ).
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = 'Numeric / currency characteristic value without characteristic name' ).
    ENDIF.
    IF cs_bapi-classkey-classnum IS INITIAL.
      IF cs_bapi-allocvalueschar IS NOT INITIAL OR cs_bapi-allocvaluesnum IS NOT INITIAL OR
         cs_bapi-allocvaluescurr IS NOT INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_text = 'Characteristic values given, but no class' ).
      ENDIF.
      RETURN.
    ENDIF.
    IF cs_bapi-classkey-classtype IS INITIAL.
      cs_bapi-classkey-classtype = gc_def_classtype.
    ENDIF.

    "--- 2. class master
    DATA(ls_info) = lcl_class_info=>get( iv_class = cs_bapi-classkey-classnum
                                         iv_klart = cs_bapi-classkey-classtype ).
    IF ls_info-exists = abap_false.
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Class { cs_bapi-classkey-classnum } (class type | &&
                             |{ cs_bapi-classkey-classtype }) does not exist| ).
      RETURN.
    ENDIF.

    "--- 3. template columns CHAR_NAME_n / CHAR_VALUE_n are mapped to the
    "    character table whatever the characteristic is: move the lines of
    "    numeric / date / time characteristics to ALLOCVALUESNUM and of
    "    currency characteristics to ALLOCVALUESCURR (format from CABN)
    FIELD-SYMBOLS <lv_rel> TYPE any.
    DATA: lt_char_keep LIKE cs_bapi-allocvalueschar,
          ls_new_num   TYPE bapi1003_alloc_values_num,
          ls_new_curr  TYPE bapi1003_alloc_values_curr,
          lv_conv_err  TYPE string,
          lv_date      TYPE d,
          lv_text      TYPE string.

    LOOP AT cs_bapi-allocvalueschar INTO ls_char.
      READ TABLE ls_info-chars INTO DATA(ls_def) WITH TABLE KEY atnam = CONV atnam( ls_char-charact ).
      DATA(lv_known) = xsdbool( sy-subrc = 0 ).
      IF lv_known = abap_false OR ls_char-charact IS INITIAL OR ls_char-value_char IS INITIAL
         OR ls_def-atfor = 'CHAR'.
        IF lv_known = abap_true AND ls_def-atfor = 'CHAR' AND ls_def-atkle = abap_false.
          ls_char-value_char = to_upper( ls_char-value_char ).    "not case sensitive
        ENDIF.
        APPEND ls_char TO lt_char_keep.
        CONTINUE.
      ENDIF.

      lv_text = condense( CONV string( ls_char-value_char ) ).
      CLEAR: lv_conv_err, ls_new_num, ls_new_curr.
      CASE ls_def-atfor.
        WHEN 'NUM'.
          ls_new_num-charact = ls_char-charact.
          lcl_mapper=>move_value( EXPORTING iv_value  = lv_text
                                  IMPORTING ev_error  = lv_conv_err
                                  CHANGING  cv_target = ls_new_num-value_from ).
        WHEN 'CURR'.
          ls_new_curr-charact = ls_char-charact.
          lcl_mapper=>move_value( EXPORTING iv_value  = lv_text
                                  IMPORTING ev_error  = lv_conv_err
                                  CHANGING  cv_target = ls_new_curr-value_from ).
        WHEN 'DATE'.
          ls_new_num-charact = ls_char-charact.
          lcl_mapper=>move_value( EXPORTING iv_value  = lv_text
                                  IMPORTING ev_error  = lv_conv_err
                                  CHANGING  cv_target = lv_date ).
          IF lv_conv_err IS INITIAL.
            ls_new_num-value_from = CONV f( |{ lv_date }| ).      "YYYYMMDD
          ENDIF.
        WHEN 'TIME'.
          ls_new_num-charact = ls_char-charact.
          REPLACE ALL OCCURRENCES OF ':' IN lv_text WITH ''.
          IF lv_text CO '0123456789' AND strlen( lv_text ) <= 6.
            ls_new_num-value_from = CONV f( lv_text ).             "HHMMSS
          ELSE.
            lv_conv_err = |Value '{ ls_char-value_char }' is not a valid time|.
          ENDIF.
      ENDCASE.

      IF lv_conv_err IS NOT INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class iv_field = ls_char-charact
                     iv_text = |Characteristic { ls_char-charact } ({ ls_def-atfor }): { lv_conv_err }| ).
        APPEND ls_char TO lt_char_keep.
        CONTINUE.
      ENDIF.

      IF ls_def-atfor = 'CURR'.
        ASSIGN COMPONENT 'VALUE_RELATION' OF STRUCTURE ls_new_curr TO <lv_rel>.
        IF sy-subrc = 0.
          <lv_rel> = '1'.                                        "equal
        ENDIF.
        APPEND ls_new_curr TO cs_bapi-allocvaluescurr.
      ELSE.
        ASSIGN COMPONENT 'VALUE_RELATION' OF STRUCTURE ls_new_num TO <lv_rel>.
        IF sy-subrc = 0.
          <lv_rel> = '1'.                                        "equal
        ENDIF.
        APPEND ls_new_num TO cs_bapi-allocvaluesnum.
      ENDIF.
    ENDLOOP.
    cs_bapi-allocvalueschar = lt_char_keep.

    LOOP AT cs_bapi-allocvalueschar INTO ls_char WHERE charact IS NOT INITIAL.
      check_characteristic( is_row = is_row is_info = ls_info iv_param = 'ALLOCVALUESCHAR'
                            iv_atnam = ls_char-charact iv_value = ls_char-value_char ).
      APPEND ls_char-charact TO lt_used.
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluesnum INTO DATA(ls_num) WHERE charact IS NOT INITIAL.
      check_characteristic( is_row = is_row is_info = ls_info iv_param = 'ALLOCVALUESNUM'
                            iv_atnam = ls_num-charact ).
      APPEND ls_num-charact TO lt_used.
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluescurr INTO DATA(ls_curr) WHERE charact IS NOT INITIAL.
      check_characteristic( is_row = is_row is_info = ls_info iv_param = 'ALLOCVALUESCURR'
                            iv_atnam = ls_curr-charact ).
      APPEND ls_curr-charact TO lt_used.
    ENDLOOP.

    "single-value characteristics: one value per row
    LOOP AT lt_used INTO DATA(lv_used) GROUP BY lv_used INTO DATA(lv_grp).
      DATA(lv_cnt) = REDUCE i( INIT n = 0 FOR ls_g IN GROUP lv_grp NEXT n = n + 1 ).
      CHECK lv_cnt > 1.
      CHECK line_exists( ls_info-chars[ atnam = lv_grp atein = abap_true ] ).
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Characteristic { lv_grp } allows one value only - { lv_cnt } given| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD check_characteristic.
    "One characteristic (value) of a row against the class master
    DATA(lv_atnam) = CONV atnam( to_upper( iv_atnam ) ).

    READ TABLE is_info-chars INTO DATA(ls_ch) WITH TABLE KEY atnam = lv_atnam.
    IF sy-subrc <> 0.
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Characteristic { lv_atnam } is not assigned to class { is_info-class }| ).
      RETURN.
    ENDIF.

    "value table of the BAPI must fit the format of the characteristic
    IF iv_param IS NOT INITIAL.
      DATA(lv_fits) = SWITCH abap_bool( iv_param
        WHEN 'ALLOCVALUESCHAR' THEN xsdbool( ls_ch-atfor = 'CHAR' )
        WHEN 'ALLOCVALUESCURR' THEN xsdbool( ls_ch-atfor = 'CURR' )
        ELSE xsdbool( ls_ch-atfor = 'NUM' OR ls_ch-atfor = 'DATE' OR ls_ch-atfor = 'TIME' ) ).
      IF lv_fits = abap_false.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_text = |Characteristic { lv_atnam } has format { ls_ch-atfor } - | &&
                               |target { iv_param } in ZTMM_CLASS_DATA does not fit| ).
        RETURN.
      ENDIF.
    ENDIF.

    CHECK iv_param = 'ALLOCVALUESCHAR'.
    IF ls_ch-anzst > 0 AND strlen( iv_value ) > ls_ch-anzst.
      mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                   iv_text = |Value '{ iv_value }' is longer than { ls_ch-anzst } characters | &&
                             |(characteristic { lv_atnam })| ).
    ENDIF.
    "value list (CAWN) - unless additional values are allowed
    IF ls_ch-values IS NOT INITIAL AND ls_ch-atson = abap_false.
      DATA(lv_cmp) = COND string( WHEN ls_ch-atkle = abap_true THEN iv_value ELSE to_upper( iv_value ) ).
      IF NOT line_exists( ls_ch-values[ table_line = lv_cmp ] ).
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = gc_view-class
                     iv_text = |Value '{ iv_value }' is not allowed for characteristic { lv_atnam }| ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD check_class_conflicts.
    "The rows of one material are merged into one classification: a
    "single-value characteristic must not get different values in different
    "rows
    TYPES: BEGIN OF lty_val,
             matkey   TYPE string,
             classnum TYPE bapi1003_key-classnum,
             klart    TYPE bapi1003_key-classtype,
             atnam    TYPE atnam,
             value    TYPE string,
             row      TYPE i,
           END OF lty_val.
    DATA: lt_val    TYPE STANDARD TABLE OF lty_val WITH EMPTY KEY,
          lt_values TYPE string_table,
          lt_rows   TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    CHECK p_class = abap_true.

    LOOP AT mt_bapi ASSIGNING FIELD-SYMBOL(<ls_b>) WHERE classkey-classnum IS NOT INITIAL.
      DATA(ls_val) = VALUE lty_val( matkey   = <ls_b>-matkey
                                    classnum = <ls_b>-classkey-classnum
                                    klart    = <ls_b>-classkey-classtype
                                    row      = <ls_b>-row ).
      LOOP AT <ls_b>-allocvalueschar INTO DATA(ls_c).
        ls_val-atnam = ls_c-charact.
        ls_val-value = ls_c-value_char.
        APPEND ls_val TO lt_val.
      ENDLOOP.
      LOOP AT <ls_b>-allocvaluesnum INTO DATA(ls_n).
        ls_val-atnam = ls_n-charact.
        ls_val-value = |{ ls_n-value_from }/{ ls_n-value_to }|.
        APPEND ls_val TO lt_val.
      ENDLOOP.
      LOOP AT <ls_b>-allocvaluescurr INTO DATA(ls_u).
        ls_val-atnam = ls_u-charact.
        ls_val-value = |{ ls_u-value_from }/{ ls_u-value_to }|.
        APPEND ls_val TO lt_val.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_val INTO DATA(ls_v)
         GROUP BY ( matkey   = ls_v-matkey   classnum = ls_v-classnum
                    klart    = ls_v-klart    atnam    = ls_v-atnam )
         INTO DATA(lg_val).
      CLEAR: lt_values, lt_rows.
      LOOP AT GROUP lg_val INTO DATA(ls_m).
        IF NOT line_exists( lt_values[ table_line = ls_m-value ] ).
          APPEND ls_m-value TO lt_values.
        ENDIF.
        IF NOT line_exists( lt_rows[ table_line = ls_m-row ] ).
          APPEND ls_m-row TO lt_rows.
        ENDIF.
      ENDLOOP.
      CHECK lines( lt_values ) > 1 AND lines( lt_rows ) > 1.    "same row: CHECK_CLASSIFICATION

      DATA(ls_info) = lcl_class_info=>get( iv_class = lg_val-classnum iv_klart = lg_val-klart ).
      CHECK line_exists( ls_info-chars[ atnam = lg_val-atnam atein = abap_true ] ).

      LOOP AT lt_rows INTO DATA(lv_row).
        READ TABLE mt_row INTO DATA(ls_row) WITH KEY k_row COMPONENTS row = lv_row.
        mo_log->add( iv_type = 'E' is_row = ls_row iv_view = gc_view-class
                     iv_text = |Characteristic { lg_val-atnam } allows one value only - rows of the material give | &&
                               |{ concat_lines_of( table = lt_values sep = `, ` ) }| ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD copy_reference_class.
    "Classification of the reference material (view CLASS is copied):
    "  - class: taken from the reference if the template has none (a
    "    reference with several classes of the type needs the class given)
    "  - values: only characteristics not given in the template (template
    "    values win); inherited values are not copied
    "Runs before the default values (ZTMM_DEFLT_DATA) are applied.
    FIELD-SYMBOLS <lv_inh> TYPE any.
    DATA: lv_refmat TYPE matnr,
          lt_given  TYPE tt_atnam,
          lv_count  TYPE i.

    CLEAR et_params.
    DATA(lv_ref) = to_upper( get_value( iv_row = is_row-row iv_field = gc_col-ref_matnr ) ).
    CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
      EXPORTING
        input  = lv_ref
      IMPORTING
        output = lv_refmat
      EXCEPTIONS
        OTHERS = 1.
    CHECK sy-subrc = 0.

    "missing reference data: error if COPY_CLASS was requested explicitly
    DATA(lv_msgty) = COND symsgty( WHEN is_flag_set( iv_row = is_row-row iv_field = gc_col-copy_class ) = abap_true
                                   THEN 'E' ELSE 'W' ).
    TRY.
        DATA(ls_rcl) = mo_bapi->get_ref_classification( iv_matnr = lv_refmat
                                                        iv_class = cs_bapi-classkey-classnum
                                                        iv_ctype = cs_bapi-classkey-classtype ).
      CATCH lcx_error INTO DATA(lx_error).
        mo_log->add( iv_type = lv_msgty is_row = is_row iv_view = gc_view-class
                     iv_field = gc_col-ref_matnr iv_text = lx_error->get_text( ) ).
        RETURN.
    ENDTRY.
    IF ls_rcl-classkey-classnum IS INITIAL.
      "no classification at the reference: warning only (other rows may have it)
      mo_log->add( iv_type = 'W' is_row = is_row iv_view = gc_view-class iv_field = gc_col-ref_matnr
                   iv_text = |Reference { lv_ref } has no classification | &&
                             |{ cs_bapi-classkey-classnum } - not copied| ).
      RETURN.
    ENDIF.

    DATA(lv_all_classes) = abap_false.
    IF cs_bapi-classkey-classnum IS INITIAL.
      cs_bapi-classkey = ls_rcl-classkey.
      APPEND 'CLASSKEY' TO et_params.
      lv_all_classes = abap_true.                     "no class in the template -> copy all
    ENDIF.

    "characteristics given in the template
    LOOP AT cs_bapi-allocvalueschar INTO DATA(ls_char).
      INSERT CONV atnam( to_upper( ls_char-charact ) ) INTO TABLE lt_given.
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluesnum INTO DATA(ls_num).
      INSERT CONV atnam( to_upper( ls_num-charact ) ) INTO TABLE lt_given.
    ENDLOOP.
    LOOP AT cs_bapi-allocvaluescurr INTO DATA(ls_curr).
      INSERT CONV atnam( to_upper( ls_curr-charact ) ) INTO TABLE lt_given.
    ENDLOOP.

    LOOP AT ls_rcl-allocvalueschar INTO DATA(ls_rchar).
      CHECK NOT line_exists( lt_given[ table_line = ls_rchar-charact ] ).
      ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_rchar TO <lv_inh>.
      CHECK NOT ( sy-subrc = 0 AND <lv_inh> IS NOT INITIAL ).
      APPEND ls_rchar TO cs_bapi-allocvalueschar.
      lv_count = lv_count + 1.
    ENDLOOP.
    LOOP AT ls_rcl-allocvaluesnum INTO DATA(ls_rnum).
      CHECK NOT line_exists( lt_given[ table_line = ls_rnum-charact ] ).
      ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_rnum TO <lv_inh>.
      CHECK NOT ( sy-subrc = 0 AND <lv_inh> IS NOT INITIAL ).
      APPEND ls_rnum TO cs_bapi-allocvaluesnum.
      lv_count = lv_count + 1.
    ENDLOOP.
    LOOP AT ls_rcl-allocvaluescurr INTO DATA(ls_rcurr).
      CHECK NOT line_exists( lt_given[ table_line = ls_rcurr-charact ] ).
      ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_rcurr TO <lv_inh>.
      CHECK NOT ( sy-subrc = 0 AND <lv_inh> IS NOT INITIAL ).
      APPEND ls_rcurr TO cs_bapi-allocvaluescurr.
      lv_count = lv_count + 1.
    ENDLOOP.
    "reference with several classes of the type: copy all of them (warning)
    IF lv_all_classes = abap_true AND ls_rcl-extra_class IS NOT INITIAL.
      LOOP AT ls_rcl-extra_class INTO DATA(ls_extra).
        DATA(ls_copy) = ls_extra.
        LOOP AT ls_copy-allocvalueschar INTO DATA(ls_xc).
          ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_xc TO <lv_inh>.
          IF sy-subrc = 0 AND <lv_inh> IS NOT INITIAL.
            DELETE ls_copy-allocvalueschar.                  "inherited values are not copied
          ENDIF.
        ENDLOOP.
        LOOP AT ls_copy-allocvaluesnum INTO DATA(ls_xn).
          ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_xn TO <lv_inh>.
          IF sy-subrc = 0 AND <lv_inh> IS NOT INITIAL.
            DELETE ls_copy-allocvaluesnum.
          ENDIF.
        ENDLOOP.
        LOOP AT ls_copy-allocvaluescurr INTO DATA(ls_xr).
          ASSIGN COMPONENT 'INHERITED' OF STRUCTURE ls_xr TO <lv_inh>.
          IF sy-subrc = 0 AND <lv_inh> IS NOT INITIAL.
            DELETE ls_copy-allocvaluescurr.
          ENDIF.
        ENDLOOP.
        APPEND ls_copy TO cs_bapi-extra_class.
      ENDLOOP.
      mo_log->add( iv_type = 'W' is_row = is_row iv_view = gc_view-class iv_field = gc_col-ref_matnr
                   iv_text = |Reference { lv_ref } has { lines( ls_rcl-extra_class ) + 1 } classes of type | &&
                             |{ ls_rcl-classkey-classtype } - all classes are copied| ).
    ENDIF.
    IF lv_count > 0.
      APPEND 'ALLOCVALUESCHAR' TO et_params.
      APPEND 'ALLOCVALUESNUM'  TO et_params.
      APPEND 'ALLOCVALUESCURR' TO et_params.
    ENDIF.
    INSERT gc_view-class INTO TABLE cs_bapi-views.

    mo_log->add( iv_type = 'S' is_row = is_row iv_view = gc_view-class iv_field = gc_col-ref_matnr
                 iv_text = |Classification { cs_bapi-classkey-classnum } of reference { lv_ref }: | &&
                           |{ lv_count } value(s) copied| ).
  ENDMETHOD.

  METHOD check_cond_mandatory.
    "ZTMM_COND_MAND: SOURCE_FIELD = this field -> CONDMAT_FIELD required
    LOOP AT mo_config->mt_cond INTO DATA(ls_cond) WHERE source_field = is_fcat-temp_field_name.
      IF gc_cond_if_source = abap_true AND iv_supplied = abap_false.
        CONTINUE.                               "source not maintained -> no check
      ENDIF.
      CHECK is_available( iv_row = is_row-row iv_field = ls_cond-condmat_field ) = abap_false.

      mo_log->add( iv_type  = 'E'
                   is_row   = is_row
                   iv_view  = is_fcat-view
                   iv_field = ls_cond-condmat_field
                   iv_fdesc = ls_cond-condmat_dec
                   iv_text  = |{ ls_cond-condmat_field } ({ ls_cond-condmat_dec }) is mandatory | &&
                              |when { ls_cond-source_field } ({ ls_cond-source_dec }) is maintained| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD map_field.
    "Pass the template value to every BAPI target maintained for the field
    LOOP AT is_fcat-targets INTO DATA(ls_target).
      lcl_mapper=>map_value( EXPORTING is_target = ls_target
                                       iv_field  = is_fcat-temp_field_name
                                       iv_value  = iv_value
                             IMPORTING ev_error  = DATA(lv_error)
                             CHANGING  cs_bapi   = cs_bapi ).
      IF lv_error IS NOT INITIAL.
        mo_log->add( iv_type = 'E' is_row = is_row iv_view = is_fcat-view
                     iv_field = is_fcat-temp_field_name iv_fdesc = is_fcat-description
                     iv_text = lv_error ).
      ENDIF.
    ENDLOOP.
    IF is_fcat-targets IS NOT INITIAL.
      INSERT is_fcat-view INTO TABLE cs_bapi-views.
    ENDIF.
  ENDMETHOD.

  METHOD check_existence.
    "Check the existence of the material and its org. levels (plant, storage
    "location, sales area, valuation area ...) according to the operation.
    TYPES: BEGIN OF lty_org,
             text   TYPE string,
             exists TYPE abap_bool,
           END OF lty_org.
    DATA: lt_org   TYPE STANDARD TABLE OF lty_org WITH EMPTY KEY,
          lv_matnr TYPE matnr.

    CHECK lcl_mapper=>is_dummy_key( is_row-matkey ) = abap_false.

    CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
      EXPORTING
        input  = is_row-matkey
      IMPORTING
        output = lv_matnr
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc <> 0.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-matnr iv_text = 'Invalid material number' ).
      RETURN.
    ENDIF.

    READ TABLE mt_ex_mara INTO DATA(ls_mara) WITH TABLE KEY matnr = lv_matnr.
    DATA(lv_exists) = xsdbool( sy-subrc = 0 ).
    DATA(lv_opid)   = lcl_screen=>get_operation( ).

    IF lv_opid = gc_op-create.
      IF lv_exists = abap_true.
        mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-matnr
                     iv_text = 'Material already exists - use Update or Extend' ).
      ENDIF.
      RETURN.
    ENDIF.
    IF lv_exists = abap_false.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-matnr
                   iv_text = 'Material does not exist - use Create' ).
      RETURN.
    ENDIF.

    "HEADDATA is sent with type / sector of the selection screen
    IF ls_mara-mtart <> p_mtart.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-mtart
                   iv_text = |Material has type { ls_mara-mtart } - selection is { p_mtart }| ).
    ENDIF.
    IF ls_mara-mbrsh <> p_indsec.
      mo_log->add( iv_type = 'E' is_row = is_row iv_field = gc_col-mbrsh
                   iv_text = |Material has industry sector { ls_mara-mbrsh } - selection is { p_indsec }| ).
    ENDIF.

    "Extend maintains org. levels only - client-level data is not sent
    IF lv_opid = gc_op-extend AND
       ( is_bapi-clientdata          IS NOT INITIAL OR is_bapi-materialdescription IS NOT INITIAL OR
         is_bapi-unitsofmeasure      IS NOT INITIAL OR is_bapi-internationalartnos IS NOT INITIAL OR
         is_bapi-materiallongtext    IS NOT INITIAL ).
      mo_log->add( iv_type = 'W' is_row = is_row
                   iv_text = 'Basic data / descriptions / units / texts are not changed by Extend - use Update' ).
    ENDIF.

    "Org. levels of this row - already maintained for the material?
    IF is_bapi-plantdata IS NOT INITIAL.
      APPEND VALUE #( text   = |Plant { is_bapi-plantdata-plant }|
                      exists = xsdbool( line_exists( mt_ex_marc[ matnr = lv_matnr
                                                                 werks = is_bapi-plantdata-plant ] ) ) ) TO lt_org.
    ENDIF.
    IF is_bapi-salesdata-sales_org IS NOT INITIAL.
      APPEND VALUE #( text   = |Sales area { is_bapi-salesdata-sales_org }/{ is_bapi-salesdata-distr_chan }|
                      exists = xsdbool( line_exists( mt_ex_mvke[ matnr = lv_matnr
                                                                 vkorg = is_bapi-salesdata-sales_org
                                                                 vtweg = is_bapi-salesdata-distr_chan ] ) ) ) TO lt_org.
    ENDIF.
    IF is_bapi-storagelocationdata-stge_loc IS NOT INITIAL.
      DATA(lv_sloc_plant) = COND werks_d( WHEN is_bapi-storagelocationdata-plant IS NOT INITIAL
                                          THEN is_bapi-storagelocationdata-plant
                                          ELSE is_bapi-plantdata-plant ).
      APPEND VALUE #( text   = |Storage location { lv_sloc_plant }/{ is_bapi-storagelocationdata-stge_loc }|
                      exists = xsdbool( line_exists( mt_ex_mard[ matnr = lv_matnr
                                                                 werks = lv_sloc_plant
                                                                 lgort = is_bapi-storagelocationdata-stge_loc ] ) ) ) TO lt_org.
    ENDIF.
    IF is_bapi-valuationdata-val_area IS NOT INITIAL.
      APPEND VALUE #( text   = |Valuation area { is_bapi-valuationdata-val_area }|
                      exists = xsdbool( line_exists( mt_ex_mbew[ matnr = lv_matnr
                                                                 bwkey = is_bapi-valuationdata-val_area
                                                                 bwtar = is_bapi-valuationdata-val_type ] ) ) ) TO lt_org.
    ENDIF.
    IF is_bapi-warehousenumberdata-whse_no IS NOT INITIAL.
      APPEND VALUE #( text   = |Warehouse { is_bapi-warehousenumberdata-whse_no }|
                      exists = xsdbool( line_exists( mt_ex_mlgn[ matnr = lv_matnr
                                                                 lgnum = is_bapi-warehousenumberdata-whse_no ] ) ) ) TO lt_org.
    ENDIF.

    CASE lv_opid.
      WHEN gc_op-update.
        LOOP AT lt_org INTO DATA(ls_org) WHERE exists = abap_false.
          mo_log->add( iv_type = 'E' is_row = is_row
                       iv_text = |{ ls_org-text } does not exist for the material - use Extend| ).
        ENDLOOP.
      WHEN gc_op-extend.
        LOOP AT lt_org INTO ls_org WHERE exists = abap_true.
          mo_log->add( iv_type = 'W' is_row = is_row
                       iv_text = |{ ls_org-text } already exists - its values will be changed| ).
        ENDLOOP.
        IF lt_org IS NOT INITIAL AND NOT line_exists( lt_org[ exists = abap_false ] ).
          mo_log->add( iv_type = 'E' is_row = is_row
                       iv_text = 'Nothing to extend - all org. levels of the row already exist (use Update)' ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Simulation / posting
*----------------------------------------------------------------------*
  METHOD process_materials.
    "Post the materials: per template row one BAPI_MATERIAL_SAVEREPLICA call, then
    "the classification. Test run: checks only, the update is rolled back. The
    "result is written to the log.
    FIELD-SYMBOLS <ls_class> TYPE ty_bapi.
    DATA: lt_err_mat  TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lt_seen     TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line,
          lt_mat      TYPE string_table,
          lt_class    TYPE tt_bapi,
          lv_ok_cnt   TYPE i,
          lv_fail_cnt TYPE i,
          lv_skip_cnt TYPE i.

    DATA(lv_mode) = COND string( WHEN p_test = abap_true THEN `Simulation` ELSE `Posting` ).

    "Materials in template order, materials with validation errors
    LOOP AT mt_row INTO DATA(ls_row).
      INSERT ls_row-matkey INTO TABLE lt_seen.
      IF sy-subrc = 0.
        APPEND ls_row-matkey TO lt_mat.
      ENDIF.
      IF mo_log->has_error( ls_row-row ) = abap_true.
        INSERT ls_row-matkey INTO TABLE lt_err_mat.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_mat INTO DATA(lv_matkey).
      DATA(ls_first) = mt_row[ KEY k_mat COMPONENTS matkey = lv_matkey ].

      IF line_exists( lt_err_mat[ table_line = lv_matkey ] ).
        mo_log->add( iv_type = 'W' is_row = ls_first
                     iv_text = |{ lv_mode } skipped - material has validation errors| ).
        lv_skip_cnt = lv_skip_cnt + 1.
        CONTINUE.
      ENDIF.

      DATA(lv_matnr) = mo_bapi->get_material_number( ls_first ).
      IF lv_matnr IS INITIAL.
        lv_skip_cnt = lv_skip_cnt + 1.
        CONTINUE.
      ENDIF.

      "--- One BAPI_MATERIAL_SAVEREPLICA call per template row:
      "    basic data of the material + org. levels of this row only
      DATA(lv_mat_ok) = abap_true.
      LOOP AT mt_row INTO DATA(ls_mrow) USING KEY k_mat WHERE matkey = lv_matkey.
        DATA(lv_row_ok) = mo_bapi->save_material( is_call  = build_call( iv_matkey = lv_matkey
                                                                         iv_matnr  = lv_matnr
                                                                         iv_row    = ls_mrow-row )
                                                  it_rows  = VALUE #( ( ls_mrow ) )
                                                  iv_matnr = lv_matnr ).
        IF lv_row_ok = abap_false.
          lv_mat_ok = abap_false.
          IF p_test = abap_false.
            mo_log->add( iv_type = 'W' is_row = ls_mrow
                         iv_text = 'Remaining rows of this material not posted after the error' ).
            EXIT.                                   "posting: stop this material
          ENDIF.
        ELSE.
          "Sales text (text object MVKE) of the sales area of this row
          DATA(lv_stext) = get_value( iv_row = ls_mrow-row iv_field = gc_col-sales_text ).
          IF lv_stext IS NOT INITIAL AND
             mo_bapi->save_sales_text( is_row = ls_mrow iv_matnr = lv_matnr iv_text = lv_stext ) = abap_false.
            lv_mat_ok = abap_false.
          ENDIF.
        ENDIF.
      ENDLOOP.

      "material data really saved in this run (for the message below)
      DATA(lv_saved) = xsdbool( p_test = abap_false AND lv_mat_ok = abap_true ).

      "--- Classification: merged per class over all rows of the material
      "    (conflicting values were rejected in CHECK_CLASS_CONFLICTS)
      CLEAR lt_class.
      LOOP AT mt_bapi ASSIGNING FIELD-SYMBOL(<ls_rb>) USING KEY k_mat WHERE matkey = lv_matkey.
        "main class of the row + further classes copied from the reference
        DATA(lt_src) = VALUE tt_bapi( ).
        IF <ls_rb>-classkey-classnum IS NOT INITIAL.
          APPEND VALUE #( classkey        = <ls_rb>-classkey
                          allocvalueschar = <ls_rb>-allocvalueschar
                          allocvaluesnum  = <ls_rb>-allocvaluesnum
                          allocvaluescurr = <ls_rb>-allocvaluescurr
                          row             = <ls_rb>-row ) TO lt_src.
        ENDIF.
        LOOP AT <ls_rb>-extra_class INTO DATA(ls_xcl).
          APPEND VALUE #( classkey        = ls_xcl-classkey
                          allocvalueschar = ls_xcl-allocvalueschar
                          allocvaluesnum  = ls_xcl-allocvaluesnum
                          allocvaluescurr = ls_xcl-allocvaluescurr
                          row             = <ls_rb>-row ) TO lt_src.
        ENDLOOP.

        LOOP AT lt_src ASSIGNING FIELD-SYMBOL(<ls_src>).
          READ TABLE lt_class ASSIGNING <ls_class>
               WITH KEY classkey-classnum  = <ls_src>-classkey-classnum
                        classkey-classtype = <ls_src>-classkey-classtype.
          IF sy-subrc <> 0.
            APPEND VALUE #( classkey = <ls_src>-classkey row = <ls_src>-row matkey = lv_matkey )
              TO lt_class ASSIGNING <ls_class>.
          ENDIF.
          LOOP AT <ls_src>-allocvalueschar INTO DATA(ls_vchar).
            lcl_mapper=>append_unique( EXPORTING is_line = ls_vchar CHANGING ct_tab = <ls_class>-allocvalueschar ).
          ENDLOOP.
          LOOP AT <ls_src>-allocvaluesnum INTO DATA(ls_vnum).
            lcl_mapper=>append_unique( EXPORTING is_line = ls_vnum CHANGING ct_tab = <ls_class>-allocvaluesnum ).
          ENDLOOP.
          LOOP AT <ls_src>-allocvaluescurr INTO DATA(ls_vcurr).
            lcl_mapper=>append_unique( EXPORTING is_line = ls_vcurr CHANGING ct_tab = <ls_class>-allocvaluescurr ).
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.

      "only once the material exists (after posting / for update + extend)
      IF lv_mat_ok = abap_true OR p_test = abap_true.
        LOOP AT lt_class ASSIGNING <ls_class>.
          DATA(ls_crow) = mt_row[ KEY k_row COMPONENTS row = <ls_class>-row ].
          IF p_test = abap_true AND lcl_screen=>get_operation( ) = gc_op-create.
            mo_log->add( iv_type = 'W' is_row = ls_crow iv_view = gc_view-class
                         iv_text = |Classification { <ls_class>-classkey-classnum } checked against the | &&
                                   |class master only - BAPI simulation needs an existing material| ).
            CONTINUE.
          ENDIF.
          IF mo_bapi->classify( is_class = <ls_class> is_row = ls_crow iv_matnr = lv_matnr ) = abap_false.
            lv_mat_ok = abap_false.
            IF lv_saved = abap_true.
              mo_log->add( iv_type = 'E' is_row = ls_crow iv_view = gc_view-class iv_matnr = lv_matnr
                           iv_text = |Material saved without classification { <ls_class>-classkey-classnum } - | &&
                                     |correct the class data and classify it with Update| ).
            ENDIF.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_mat_ok = abap_true.
        lv_ok_cnt = lv_ok_cnt + 1.
      ELSE.
        lv_fail_cnt = lv_fail_cnt + 1.
      ENDIF.
    ENDLOOP.

    mo_log->add( iv_type = COND #( WHEN lv_fail_cnt > 0 THEN 'W' ELSE 'S' )
                 iv_text = |{ lv_mode } finished: { lv_ok_cnt } material(s) successful, | &&
                           |{ lv_fail_cnt } failed, { lv_skip_cnt } skipped| ).
  ENDMETHOD.

  METHOD build_call.
    "One call of BAPI_MATERIAL_SAVEREPLICA for template row IV_ROW:
    " - basic data (header, client data, descriptions, units, texts, tax)
    "   from all rows of the material - every call is complete on its own
    " - org. level data (plant, storage location, sales area, valuation
    "   area, warehouse ...) only from row IV_ROW
    FIELD-SYMBOLS: <ls_src>  TYPE any,
                   <lt_src>  TYPE STANDARD TABLE,
                   <ls_line> TYPE any.
    CONSTANTS:
      lc_single  TYPE string VALUE `CLIENTDATA PLANTDATA FORECASTPARAMETERS PLANNINGDATA STORAGELOCATIONDATA VALUATIONDATA WAREHOUSENUMBERDATA SALESDATA STORAGETYPEDATA`,
      lc_single2 TYPE string VALUE `PRTDATA EXTENSIONIN FORECASTVALUES UNPLNDCONSUMPTIO TOTALCONSUMPTION RETURNMESSAGES CLIENTDATACWM UNITSOFMEASURECWM VALUATIONDATACWM MATPLSTADATA MARC_APS_EXTDATA DEMAND_PENALTYDATA `,
      lc_tables  TYPE string VALUE `MATERIALDESCRIPTION UNITSOFMEASURE INTERNATIONALARTNOS MATERIALLONGTEXT TAXCLASSIFICATIONS`.
    DATA: lt_single TYPE string_table,
          lt_tables TYPE string_table,
          lt_views  TYPE tt_views,
          ls_head   TYPE bapie1matheader.

    SPLIT lc_single AT space INTO TABLE lt_single.
    SPLIT lc_single2 AT space INTO TABLE DATA(lt_single2).
    APPEND LINES OF lt_single2 TO lt_single.
    SPLIT lc_tables AT space INTO TABLE lt_tables.

    "Extend: org. levels only - client-level data of the existing material
    "is left untouched (tax classifications are needed for new countries)
    DATA(lv_extend) = xsdbool( lcl_screen=>get_operation( ) = gc_op-extend ).
    IF lv_extend = abap_true.
      DELETE lt_single WHERE table_line = `CLIENTDATA`.
      DELETE lt_tables WHERE table_line <> `TAXCLASSIFICATIONS`.
    ENDIF.

    LOOP AT mt_bapi INTO DATA(ls_rb) USING KEY k_mat WHERE matkey = iv_matkey.

      "Org. key defaults from the plant of the row
      IF ls_rb-plantdata-plant IS NOT INITIAL.
        IF ls_rb-storagelocationdata IS NOT INITIAL AND ls_rb-storagelocationdata-plant IS INITIAL.
          ls_rb-storagelocationdata-plant = ls_rb-plantdata-plant.
        ENDIF.
        IF ls_rb-forecastparameters IS NOT INITIAL AND ls_rb-forecastparameters-plant IS INITIAL.
          ls_rb-forecastparameters-plant = ls_rb-plantdata-plant.
        ENDIF.
        IF ls_rb-planningdata IS NOT INITIAL AND ls_rb-planningdata-plant IS INITIAL.
          ls_rb-planningdata-plant = ls_rb-plantdata-plant.
        ENDIF.
        IF ls_rb-valuationdata IS NOT INITIAL AND ls_rb-valuationdata-val_area IS INITIAL.
          ls_rb-valuationdata-val_area = ls_rb-plantdata-plant.       "valuation at plant level
        ENDIF.
      ENDIF.

      DATA(lv_this_row) = COND abap_bool( WHEN iv_row IS INITIAL OR ls_rb-row = iv_row
                                          THEN abap_true ELSE abap_false ).

      "Header fields + views with data (org. level views only from this row)
      lcl_mapper=>merge_struct( EXPORTING is_src = ls_rb-headdata CHANGING cs_tgt = ls_head ).
      LOOP AT ls_rb-views INTO DATA(lv_view).
        IF lv_this_row = abap_true OR lv_view = gc_view-basic.
          INSERT lv_view INTO TABLE lt_views.
        ENDIF.
      ENDLOOP.

      "Structures -> table lines: CLIENTDATA from every row, org. levels
      "only from this row
      LOOP AT lt_single INTO DATA(lv_param).
        CHECK lv_this_row = abap_true OR lv_param = `CLIENTDATA`.
        ASSIGN COMPONENT lv_param OF STRUCTURE ls_rb TO <ls_src>.
        CHECK sy-subrc = 0.
        CHECK <ls_src> IS NOT INITIAL.
        lcl_mapper=>add_line( EXPORTING iv_param = CONV #( lv_param )
                                        is_line  = <ls_src>
                                        iv_row   = ls_rb-row
                              CHANGING  cs_call  = rs_call ).
      ENDLOOP.

      "Table parameters of the row
      LOOP AT lt_tables INTO lv_param.
        ASSIGN COMPONENT lv_param OF STRUCTURE ls_rb TO <lt_src>.
        CHECK sy-subrc = 0.
        LOOP AT <lt_src> ASSIGNING <ls_line>.
          lcl_mapper=>add_line( EXPORTING iv_param = CONV #( lv_param )
                                          is_line  = <ls_line>
                                          iv_row   = ls_rb-row
                                CHANGING  cs_call  = rs_call ).
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    "Defaults for descriptions and long texts
    LOOP AT rs_call-materialdescription ASSIGNING FIELD-SYMBOL(<ls_makt>)
         WHERE langu IS INITIAL AND langu_iso IS INITIAL.
      <ls_makt>-langu = sy-langu.
    ENDLOOP.
    LOOP AT rs_call-materiallongtext ASSIGNING FIELD-SYMBOL(<ls_text>).
      lcl_mapper=>set_default( EXPORTING iv_comp = 'APPLOBJECT' iv_value = 'MATERIAL' CHANGING cs_line = <ls_text> ).
      lcl_mapper=>set_default( EXPORTING iv_comp = 'TEXT_NAME'  iv_value = iv_matnr   CHANGING cs_line = <ls_text> ).
      lcl_mapper=>set_default( EXPORTING iv_comp = 'TEXT_ID'    iv_value = 'BEST'     CHANGING cs_line = <ls_text> ).
      lcl_mapper=>set_default( EXPORTING iv_comp = 'LANGU'      iv_value = sy-langu   CHANGING cs_line = <ls_text> ).
    ENDLOOP.

    "Header: type, industry sector, view indicators (screen AND data supplied)
    ls_head-matl_type  = p_mtart.
    ls_head-ind_sector = p_indsec.
    ls_head-basic_view    = xsdbool( lv_extend = abap_false ).
    ls_head-purchase_view = COND #( WHEN p_purch  = abap_true AND line_exists( lt_views[ table_line = gc_view-purch  ] ) THEN abap_true ).
    ls_head-mrp_view      = COND #( WHEN p_mrp   = abap_true AND line_exists( lt_views[ table_line = gc_view-mrp    ] ) THEN abap_true ).
    ls_head-forecast_view = COND #( WHEN p_frcst = abap_true AND line_exists( lt_views[ table_line = gc_view-frcst ] ) THEN abap_true ).
    ls_head-storage_view  = COND #( WHEN p_plntst = abap_true AND line_exists( lt_views[ table_line = gc_view-plntst ] ) THEN abap_true ).
    ls_head-sales_view    = COND #( WHEN p_sales = abap_true AND line_exists( lt_views[ table_line = gc_view-sales  ] ) THEN abap_true ).
    ls_head-account_view  = COND #( WHEN p_val  = abap_true AND line_exists( lt_views[ table_line = gc_view-val    ] ) THEN abap_true ).
    APPEND ls_head TO rs_call-headdata.

    "Material number in all lines, then the X tables
    lcl_mapper=>set_material_all( EXPORTING iv_matnr = iv_matnr CHANGING cs_call = rs_call ).
    lcl_mapper=>build_x_tables( CHANGING cs_call = rs_call ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Helpers
*----------------------------------------------------------------------*
  METHOD get_value.
    "Value of a template cell (initial if not maintained).
    rv_value = VALUE #( mt_cell[ row = iv_row field = iv_field ]-value OPTIONAL ).
  ENDMETHOD.

  METHOD is_available.
    "value in template or copied from the reference material
    rv_avail = COND #( WHEN line_exists( mt_cell[   row = iv_row field = iv_field ] ) OR
                            line_exists( mt_copied[ row = iv_row field = iv_field ] )
                       THEN abap_true ELSE abap_false ).
  ENDMETHOD.

  METHOD is_flag_set.
    "COPY_* columns: X, Y, YES, 1 or TRUE set the flag.
    DATA(lv_flag) = to_upper( get_value( iv_row = iv_row iv_field = iv_field ) ).
    rv_set = COND #( WHEN lv_flag = 'X' OR lv_flag = 'Y' OR lv_flag = 'YES' OR
                          lv_flag = '1' OR lv_flag = 'TRUE'
                     THEN abap_true ELSE abap_false ).
  ENDMETHOD.

ENDCLASS.
