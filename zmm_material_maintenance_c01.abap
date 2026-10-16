*&---------------------------------------------------------------------*
*& Include          ZMM_MATERIAL_MAINTENANCE_C01
*&---------------------------------------------------------------------*
*& Class definitions
*&   lcx_error          - local exception
*&   lcl_log            - message log (= output ALV)
*&   lcl_mapper         - dynamic mapping template value -> BAPI field
*&   lcl_file_reader    - .xlsx / .csv reader (PC or application server)
*&   lcl_config         - variant + field catalogue + cond. rules
*&   lcl_material_bapi  - BAPI_MATERIAL_SAVEREPLICA / BAPI_OBJCL_* calls
*&   lcl_output         - ALV, server file, e-mail
*&   lcl_screen         - selection-screen logic
*&   lcl_app            - controller
*&---------------------------------------------------------------------*

CLASS lcx_error DEFINITION INHERITING FROM cx_static_check.
  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_text TYPE csequence.
    METHODS get_text REDEFINITION.
  PRIVATE SECTION.
    DATA mv_text TYPE string.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_log DEFINITION FINAL.
  PUBLIC SECTION.
    DATA mt_msg TYPE tt_msg READ-ONLY.

    METHODS:
      add IMPORTING iv_type  TYPE symsgty
                    iv_text  TYPE csequence
                    is_row   TYPE ty_row    OPTIONAL
                    iv_matnr TYPE csequence OPTIONAL
                    iv_view  TYPE char10    OPTIONAL
                    iv_field TYPE csequence OPTIONAL
                    iv_fdesc TYPE csequence OPTIONAL,
      count            IMPORTING iv_type TYPE symsgty RETURNING VALUE(rv_count) TYPE i,
      has_error        IMPORTING iv_row TYPE i       RETURNING VALUE(rv_error) TYPE abap_bool,
      has_global_error RETURNING VALUE(rv_error) TYPE abap_bool.
  PRIVATE SECTION.
    DATA mt_cnt TYPE tt_msgcnt.                 "messages per type (for COUNT)
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_mapper DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      trim          IMPORTING iv_value TYPE any RETURNING VALUE(rv_value) TYPE string,
      is_dummy_key  IMPORTING iv_key TYPE string RETURNING VALUE(rv_dummy) TYPE abap_bool,
      resolve_param IMPORTING iv_struct TYPE csequence
                    EXPORTING ev_param  TYPE fieldname
                              ev_table  TYPE abap_bool,
      target_exists IMPORTING is_target TYPE ty_target RETURNING VALUE(rv_exists) TYPE abap_bool,
      map_value     IMPORTING is_target TYPE ty_target
                              iv_field  TYPE fieldname
                              iv_value  TYPE string
                    EXPORTING ev_error  TYPE string
                    CHANGING  cs_bapi   TYPE ty_bapi,
      move_value    IMPORTING iv_value  TYPE string
                    EXPORTING ev_error  TYPE string
                    CHANGING  cv_target TYPE any,
      set_x         IMPORTING iv_value TYPE any
                    CHANGING  cv_x     TYPE any,
      set_all_x     IMPORTING is_data TYPE any
                    CHANGING  cs_x    TYPE any,
      merge_struct  IMPORTING is_src TYPE any
                    CHANGING  cs_tgt TYPE any,
      append_unique IMPORTING is_line TYPE any
                    CHANGING  ct_tab  TYPE STANDARD TABLE,
      "--- BAPI_MATERIAL_SAVEREPLICA call assembly
      add_line         IMPORTING iv_param TYPE fieldname
                                 is_line  TYPE any
                                 iv_row   TYPE i
                       CHANGING  cs_call  TYPE ty_call,
      set_matnr        IMPORTING iv_matnr TYPE matnr
                       CHANGING  cs_line  TYPE any,

      set_func        IMPORTING iv_function TYPE bapifn
                      CHANGING  cs_line     TYPE any,
      set_material_all IMPORTING iv_matnr TYPE matnr
                       CHANGING  cs_call  TYPE ty_call,
      build_x_tables   CHANGING  cs_call  TYPE ty_call,
      set_default      IMPORTING iv_comp  TYPE csequence
                                 iv_value TYPE any
                       CHANGING  cs_line  TYPE any.
  PRIVATE SECTION.
    CLASS-METHODS get_line IMPORTING iv_param TYPE fieldname
                                     iv_key   TYPE string
                           EXPORTING er_line  TYPE REF TO data
                           CHANGING  cs_bapi  TYPE ty_bapi.
    CLASS-METHODS extend_func IMPORTING iv_param       TYPE fieldname
                                        iv_matnr       TYPE matnr
                                        is_line        TYPE any
                              RETURNING VALUE(rv_func) TYPE bapifn.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_file_reader DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      read          IMPORTING iv_file       TYPE string
                              iv_server     TYPE abap_bool
                    RETURNING VALUE(rt_raw) TYPE tt_raw
                    RAISING   lcx_error,
      get_extension IMPORTING iv_file       TYPE string
                    RETURNING VALUE(rv_ext) TYPE string.
  PRIVATE SECTION.
    CLASS-METHODS:
      read_binary     IMPORTING iv_file TYPE string iv_server TYPE abap_bool
                      RETURNING VALUE(rv_xdata) TYPE xstring RAISING lcx_error,
      read_text_lines IMPORTING iv_file TYPE string iv_server TYPE abap_bool
                      RETURNING VALUE(rt_lines) TYPE string_table RAISING lcx_error,
      parse_xlsx      IMPORTING iv_xdata TYPE xstring iv_file TYPE string
                      RETURNING VALUE(rt_raw) TYPE tt_raw RAISING lcx_error,
      parse_csv       IMPORTING it_lines TYPE string_table
                      RETURNING VALUE(rt_raw) TYPE tt_raw,
      split_csv_line  IMPORTING iv_line TYPE string iv_sep TYPE string
                      RETURNING VALUE(rt_fields) TYPE string_table.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_config DEFINITION FINAL.
  PUBLIC SECTION.
    DATA: mv_variant TYPE z_de_var_view READ-ONLY,
          mt_fcat    TYPE tt_fcat      READ-ONLY,
          mt_cond    TYPE tt_cond      READ-ONLY,
          mt_deflt   TYPE tt_deflt     READ-ONLY.

    CLASS-METHODS:
      view_tables     RETURNING VALUE(rt_tab)  TYPE tt_viewtab,
      control_columns RETURNING VALUE(rt_cols) TYPE tt_fieldname.

    METHODS:
      constructor IMPORTING io_log TYPE REF TO lcl_log,
      load        RAISING lcx_error.

  PRIVATE SECTION.
    DATA mo_log TYPE REF TO lcl_log.
    METHODS:
      get_variant    RAISING lcx_error,
      get_fields     RAISING lcx_error,
      get_cond_rules,
      get_defaults,
      parse_targets  IMPORTING is_fcat TYPE ty_fcat RETURNING VALUE(rt_target) TYPE tt_target.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_class_info DEFINITION FINAL.
  "Class master data for the classification checks - buffered per class
  PUBLIC SECTION.
    CLASS-METHODS get IMPORTING iv_class       TYPE csequence
                                iv_klart       TYPE csequence
                      RETURNING VALUE(rs_info) TYPE ty_classinfo.
  PRIVATE SECTION.
    CLASS-DATA mt_buffer TYPE tt_classinfo.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_material_bapi DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      constructor         IMPORTING io_log TYPE REF TO lcl_log,
      get_material_number IMPORTING is_row TYPE ty_row RETURNING VALUE(rv_matnr) TYPE matnr,
      get_reference       IMPORTING iv_matnr      TYPE matnr
                                    iv_werks      TYPE werks_d
                                    iv_vkorg      TYPE vkorg
                                    iv_vtweg      TYPE vtweg
                                    iv_bwkey      TYPE bwkey OPTIONAL
                          RETURNING VALUE(rs_ref) TYPE ty_bapi
                          RAISING   lcx_error,
      read_material_data  IMPORTING is_key        TYPE ty_postkey
                          RETURNING VALUE(rt_data) TYPE tt_kv
                          RAISING   lcx_error,
      save_sales_text     IMPORTING is_row       TYPE ty_row
                                    iv_matnr     TYPE matnr
                                    iv_text      TYPE string
                          RETURNING VALUE(rv_ok) TYPE abap_bool,
      save_material       IMPORTING is_call      TYPE ty_call
                                    it_rows      TYPE tt_row
                                    iv_matnr     TYPE matnr
                                    iv_simulate  TYPE abap_bool DEFAULT abap_false
                          RETURNING VALUE(rv_ok) TYPE abap_bool,
      classify            IMPORTING is_class     TYPE ty_bapi
                                    is_row       TYPE ty_row
                                    iv_matnr     TYPE matnr
                          RETURNING VALUE(rv_ok) TYPE abap_bool,
      get_ref_classification IMPORTING iv_matnr       TYPE matnr
                                       iv_class       TYPE csequence
                                       iv_ctype       TYPE csequence
                                       iv_fresh       TYPE abap_bool DEFAULT abap_false
                             RETURNING VALUE(rs_class) TYPE ty_bapi
                             RAISING   lcx_error.
  PRIVATE SECTION.
    METHODS:
      get_all_raw    IMPORTING iv_matnr      TYPE matnr
                               iv_werks      TYPE werks_d
                               iv_vkorg      TYPE vkorg
                               iv_vtweg      TYPE vtweg
                               iv_bwkey      TYPE bwkey OPTIONAL
                               iv_all        TYPE abap_bool DEFAULT abap_false
                     RETURNING VALUE(rt_raw) TYPE tt_rawpart
                     RAISING   lcx_error,
      flatten_struct IMPORTING iv_prefix TYPE string
                               iv_suffix TYPE string OPTIONAL
                               is_data   TYPE any
                     CHANGING  ct_kv     TYPE tt_kv,
      flatten_table  IMPORTING iv_prefix TYPE string
                               it_data   TYPE ANY TABLE
                     CHANGING  ct_kv     TYPE tt_kv,
      char_text      IMPORTING iv_atnam  TYPE csequence
                     RETURNING VALUE(rv_text) TYPE string,
      add_class_kv   IMPORTING iv_prefix TYPE string
                               is_class  TYPE ty_classdata
                     CHANGING  ct_kv     TYPE tt_kv,
      add_value      IMPORTING iv_name   TYPE string
                               iv_value  TYPE string
                               iv_label  TYPE string OPTIONAL
                     CHANGING  ct_kv     TYPE tt_kv,
      value_text     IMPORTING is_value  TYPE any
                     RETURNING VALUE(rv_text) TYPE string.
    METHODS sync_long_values CHANGING ct_char TYPE STANDARD TABLE.
    DATA: mo_log   TYPE REF TO lcl_log,
          mt_ddic  TYPE tt_ddicbuf,               "DDIC field texts (output file headers)
          mt_chartext TYPE tt_kv_hash,            "characteristic descriptions
          mt_cache TYPE tt_refcache,
          mt_clcache TYPE tt_refcache.            "classification of reference materials
    METHODS finish_luw IMPORTING iv_ok        TYPE abap_bool
                                 iv_what      TYPE string
                                 iv_msg       TYPE csequence
                                 is_row       TYPE ty_row
                                 iv_matnr     TYPE matnr
                                 iv_simulate  TYPE abap_bool DEFAULT abap_false
                       RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_output DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor IMPORTING io_log TYPE REF TO lcl_log.
    METHODS publish IMPORTING it_posted TYPE tt_posted OPTIONAL.
  PRIVATE SECTION.
    DATA: mo_log    TYPE REF TO lcl_log,
          mt_posted TYPE tt_posted,           "sheet 2 of the output file
          mt_out TYPE tt_msg_out,
          mo_alv TYPE REF TO cl_salv_table.
    METHODS:
      build_alv      RETURNING VALUE(rv_ok) TYPE abap_bool,
      to_xlsx        RETURNING VALUE(rv_xdata) TYPE xstring,
      save_to_server IMPORTING iv_xdata TYPE xstring,
      send_mail      IMPORTING iv_xdata TYPE xstring,
      file_name      RETURNING VALUE(rv_name) TYPE string.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_template DEFINITION FINAL.
  "Upload template as .xlsx (Office Open XML built with CL_ABAP_ZIP)
  PUBLIC SECTION.
    CLASS-METHODS:
      download,
      template_columns RETURNING VALUE(rt_cols) TYPE tt_fieldname,
      get_temp_matnr IMPORTING is_row TYPE ty_row RETURNING VALUE(rv_matnr) TYPE matnr,
      add_data_sheet IMPORTING iv_xlsx        TYPE xstring
                               it_posted      TYPE tt_posted
                               iv_test        TYPE abap_bool
                     RETURNING VALUE(rv_xlsx) TYPE xstring.
  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF c_style,                 "cellXfs index in styles.xml
        header    TYPE i VALUE 1,       "blue   - optional / other
        mandatory TYPE i VALUE 2,       "red    - mandatory
        cond      TYPE i VALUE 3,       "orange - conditional mandatory
        system    TYPE i VALUE 4,       "grey   - system derived
        control   TYPE i VALUE 5,       "green  - control column
        text      TYPE i VALUE 6,       "data cells formatted as text
        bold      TYPE i VALUE 7,
      END OF c_style.
    TYPES:
      BEGIN OF ty_col,
        field TYPE fieldname,
        style TYPE i,
      END OF ty_col,
      tt_col TYPE STANDARD TABLE OF ty_col WITH EMPTY KEY.
    CLASS-METHODS:
      build_xlsx     IMPORTING it_cols        TYPE tt_col
                               it_fcat        TYPE tt_fcat
                               iv_variant     TYPE csequence
                     RETURNING VALUE(rv_xlsx) TYPE xstring,
      sheet_template IMPORTING it_cols       TYPE tt_col
                     RETURNING VALUE(rv_xml) TYPE string,
      sheet_data     IMPORTING it_posted     TYPE tt_posted
                               iv_test       TYPE abap_bool
                     RETURNING VALUE(rv_xml) TYPE string,
      sheet_info     IMPORTING it_fcat       TYPE tt_fcat
                               iv_variant    TYPE csequence
                     RETURNING VALUE(rv_xml) TYPE string,
      styles         RETURNING VALUE(rv_xml) TYPE string,
      cell           IMPORTING iv_col        TYPE i
                               iv_row        TYPE i
                               iv_value      TYPE csequence
                               iv_style      TYPE i
                     RETURNING VALUE(rv_xml) TYPE string,
      col_letter     IMPORTING iv_col        TYPE i
                     RETURNING VALUE(rv_col) TYPE string,
      utf8           IMPORTING iv_xml      TYPE string
                     RETURNING VALUE(rv_x) TYPE xstring.
ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_screen DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      initialization,
      pbo,
      pai,
      f4_local_file  CHANGING cv_file TYPE string,
      get_operation  RETURNING VALUE(rv_opid) TYPE z_de_op_id.
  PRIVATE SECTION.
    CLASS-METHODS:
      set_listboxes,
      check_input,
      download_template,

      download_from_smw0
        IMPORTING iv_objid     TYPE wwwdatatab-objid
                  iv_target    TYPE string OPTIONAL
        RETURNING VALUE(rv_ok) TYPE abap_bool.


ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor.
    METHODS run.
  PRIVATE SECTION.
    DATA: mo_log    TYPE REF TO lcl_log,
          mo_config TYPE REF TO lcl_config,
          mo_bapi   TYPE REF TO lcl_material_bapi,
          mt_header TYPE tt_fieldname,        "template columns (index = column)
          mt_cell   TYPE tt_cell,             "template values
          mt_row    TYPE tt_row,              "template rows
          mt_copied TYPE tt_rowfield,         "values copied from reference
          mt_bapi   TYPE tt_bapi,             "mapped BAPI data per row
          mt_posted TYPE tt_postkey,          "rows of successfully posted materials
          mt_sheet  TYPE tt_posted,           "their data for the output file
          mt_ex_mara TYPE tt_ex_mara,         "existence buffers (PREFETCH_EXISTENCE)
          mt_ex_marc TYPE tt_ex_marc,
          mt_ex_mvke TYPE tt_ex_mvke,
          mt_ex_mard TYPE tt_ex_mard,
          mt_ex_mbew TYPE tt_ex_mbew,
          mt_ex_mlgn TYPE tt_ex_mlgn.

    METHODS:
      load_template          RAISING lcx_error,
      check_record_limit     RAISING lcx_error,
      check_defaults,
      apply_defaults         IMPORTING is_row  TYPE ty_row
                             CHANGING  cs_bapi TYPE ty_bapi,
      apply_unit_defaults    IMPORTING is_row  TYPE ty_row
                             CHANGING  cs_bapi TYPE ty_bapi,
      is_yyyymmdd            IMPORTING iv_value     TYPE string
                             RETURNING VALUE(rv_ok) TYPE abap_bool,
      apply_current_date     IMPORTING is_row  TYPE ty_row
                             CHANGING  cs_bapi TYPE ty_bapi,
      collect_characteristics IMPORTING is_row  TYPE ty_row
                              CHANGING  cs_bapi TYPE ty_bapi,
      check_classification   IMPORTING is_row  TYPE ty_row
                             CHANGING  cs_bapi TYPE ty_bapi,
      check_characteristic   IMPORTING is_row   TYPE ty_row
                                       is_info  TYPE ty_classinfo
                                       iv_param TYPE csequence
                                       iv_atnam TYPE csequence
                                       iv_value TYPE csequence OPTIONAL,
      check_class_conflicts,
      copy_reference_class   IMPORTING is_row    TYPE ty_row
                             EXPORTING et_params TYPE tt_fieldname
                             CHANGING  cs_bapi   TYPE ty_bapi,
      derive_values,
      inherit_org_keys,
      check_columns,
      validate_and_map,
      prefetch_existence,
      check_sales_text       IMPORTING is_row TYPE ty_row,
      check_row_control      IMPORTING is_row  TYPE ty_row,
      copy_reference         IMPORTING is_row   TYPE ty_row
                             EXPORTING es_ref   TYPE ty_bapi
                                       et_views TYPE tt_views
                             CHANGING  cs_bapi  TYPE ty_bapi,
      copy_reference_tables  IMPORTING is_row   TYPE ty_row
                                       is_ref   TYPE ty_bapi
                                       it_views TYPE tt_views
                             CHANGING  cs_bapi  TYPE ty_bapi,
      validate_row           IMPORTING is_row  TYPE ty_row
                                       is_fcat TYPE ty_fcat
                             CHANGING  cs_bapi TYPE ty_bapi,
      check_cond_mandatory   IMPORTING is_row      TYPE ty_row
                                       is_fcat     TYPE ty_fcat
                                       iv_supplied TYPE abap_bool,
      map_field              IMPORTING is_row   TYPE ty_row
                                       is_fcat  TYPE ty_fcat
                                       iv_value TYPE string
                             CHANGING  cs_bapi  TYPE ty_bapi,
      check_existence        IMPORTING is_row  TYPE ty_row
                                       is_bapi TYPE ty_bapi,
      process_materials,
      read_posted_data,
      build_call             IMPORTING iv_matkey      TYPE string
                                       iv_matnr       TYPE matnr
                                       iv_row         TYPE i OPTIONAL
                             RETURNING VALUE(rs_call) TYPE ty_call,
      get_value              IMPORTING iv_row          TYPE i
                                       iv_field        TYPE fieldname
                             RETURNING VALUE(rv_value) TYPE string,
      is_available           IMPORTING iv_row          TYPE i
                                       iv_field        TYPE fieldname
                             RETURNING VALUE(rv_avail) TYPE abap_bool,
      is_flag_set            IMPORTING iv_row        TYPE i
                                       iv_field      TYPE fieldname
                             RETURNING VALUE(rv_set) TYPE abap_bool.
ENDCLASS.
