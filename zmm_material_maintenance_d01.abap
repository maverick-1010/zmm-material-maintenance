*&---------------------------------------------------------------------*
*& Include          ZMM_MATERIAL_MAINTENANCE_D01
*&---------------------------------------------------------------------*
*& Mapping syntax in the view tables (BAPI_STRUCT_NAME / BAPI_FIELD_NAME
*&---------------------------------------------------------------------*
TABLES sscrfields.
DATA gv_email TYPE ad_smtpadr.                 "basis of S_EMAIL (recipients)

*----------------------------------------------------------------------*
* Constants
*----------------------------------------------------------------------*
CONSTANTS:
  BEGIN OF gc_op,                             "ZTMM_MATMAS_MAST-OPERATION_ID
    create TYPE z_de_op_id VALUE 'C',
    update TYPE z_de_op_id VALUE 'U',
    extend TYPE z_de_op_id VALUE 'E',
  END OF gc_op,

  BEGIN OF gc_view,                           "view tables
    basic  TYPE char10 VALUE 'BASIC',
    class  TYPE char10 VALUE 'CLASS',
    purch  TYPE char10 VALUE 'PURCH',
    mrp    TYPE char10 VALUE 'MRP',
    frcst  TYPE char10 VALUE 'FRCST',
    plntst TYPE char10 VALUE 'PLNTST',
    sales  TYPE char10 VALUE 'SALES',
    val    TYPE char10 VALUE 'VAL',
  END OF gc_view,

  BEGIN OF gc_col,                            "template columns with fixed meaning
    action     TYPE fieldname VALUE 'ACTION',
    message    TYPE fieldname VALUE 'MESSAGE',
    profile    TYPE fieldname VALUE 'PROCESS_PROFILE',
    ref_matnr  TYPE fieldname VALUE 'REFERENCE_MATNR',
    ref_werks  TYPE fieldname VALUE 'REF_WERKS',
    ref_lgort  TYPE fieldname VALUE 'REF_LGORT',
    lgort      TYPE fieldname VALUE 'LGORT',
    ref_vkorg  TYPE fieldname VALUE 'REF_VKORG',
    ref_vtweg  TYPE fieldname VALUE 'REF_VTWEG',
    ref_ekorg  TYPE fieldname VALUE 'REF_EKORG',
    def_mode   TYPE fieldname VALUE 'DEFAULT_MODE',
    copy_basic TYPE fieldname VALUE 'COPY_BASIC',
    copy_purch TYPE fieldname VALUE 'COPY_PURCH',
    copy_mrp   TYPE fieldname VALUE 'COPY_MRP',
    copy_frcst TYPE fieldname VALUE 'COPY_FRCST',
    copy_sales TYPE fieldname VALUE 'COPY_SALES',
    copy_acct  TYPE fieldname VALUE 'COPY_ACCOUNTING',
    copy_class TYPE fieldname VALUE 'COPY_CLASS',
    matnr      TYPE fieldname VALUE 'MATNR',
    mtart      TYPE fieldname VALUE 'MTART',
    mbrsh      TYPE fieldname VALUE 'MBRSH',
    werks      TYPE fieldname VALUE 'WERKS',
    vkorg      TYPE fieldname VALUE 'VKORG',
    vtweg      TYPE fieldname VALUE 'VTWEG',
    prdha      TYPE fieldname VALUE 'PRDHA',
    sales_text TYPE fieldname VALUE 'SALES_TEXT',   "sales text (text object MVKE)
  END OF gc_col,

  gc_hdr_row        TYPE i         VALUE 3,          "header = technical names
  gc_data_row       TYPE i         VALUE 5,          "first data row
  gc_prodh_levels   TYPE i         VALUE 5,          "PRODH_LVL1..5 -> PRDHA
  gc_objtab_mara    TYPE tabelle   VALUE 'MARA',     "classification object table
  gc_def_classtype  TYPE klassenart VALUE '001',     "default class type
  gc_max_longtext   TYPE i         VALUE 132,       "max. length of a material long text
  gc_stext_object   TYPE tdobject  VALUE 'MVKE',    "sales text: text object
  gc_stext_id       TYPE tdid      VALUE '0001',    "sales text: text id
  "Conditional mandatory: check CONDMAT_FIELD only if SOURCE_FIELD is filled
  gc_cond_if_source TYPE abap_bool VALUE abap_true,
  "Test run + Create without MATNR: draw internal number to simulate?
  "(the number is lost after the rollback)
  gc_sim_int_num    TYPE abap_bool VALUE abap_false.

*----------------------------------------------------------------------*
* Types
*----------------------------------------------------------------------*
TYPES:
  tt_fieldname TYPE STANDARD TABLE OF fieldname WITH EMPTY KEY,
  tt_raw       TYPE STANDARD TABLE OF string_table WITH EMPTY KEY,  "file rows/columns

  "View table directory
  BEGIN OF ty_viewtab,
    view    TYPE char10,
    tabname TYPE tabname,
    active  TYPE abap_bool,
  END OF ty_viewtab,
  tt_viewtab TYPE STANDARD TABLE OF ty_viewtab WITH EMPTY KEY,

  "Mapping target (parsed from BAPI_STRUCT_NAME / BAPI_FIELD_NAME)
  BEGIN OF ty_fixed,
    comp  TYPE fieldname,
    value TYPE string,
  END OF ty_fixed,
  tt_fixed TYPE STANDARD TABLE OF ty_fixed WITH EMPTY KEY,

  BEGIN OF ty_target,
    param   TYPE fieldname,          "BAPI parameter, e.g. PLANTDATA
    comp    TYPE fieldname,          "component,      e.g. MRP_TYPE
    table   TYPE abap_bool,          "TABLES parameter
    linekey TYPE string,             "explicit line (LINE=...)
    fixed   TYPE tt_fixed,           "fixed component values
  END OF ty_target,
  tt_target TYPE STANDARD TABLE OF ty_target WITH EMPTY KEY.

"Field catalogue = view table line + view id + parsed targets
TYPES BEGIN OF ty_fcat.
INCLUDE TYPE ztmm_basic_data.
TYPES:
  view    TYPE char10,
  targets TYPE tt_target,
  END OF ty_fcat.

TYPES:
  tt_fcat TYPE STANDARD TABLE OF ty_fcat WITH EMPTY KEY
          WITH NON-UNIQUE SORTED KEY k_field COMPONENTS temp_field_name,
  tt_cond TYPE STANDARD TABLE OF ztmm_cond_mand WITH EMPTY KEY,
  "Default values per template field (ZTMM_DEFLT_DATA)
  tt_deflt TYPE STANDARD TABLE OF ztmm_deflt_data WITH EMPTY KEY
           WITH NON-UNIQUE SORTED KEY k_field COMPONENTS temp_field_name,

  "Template content (only non-empty cells)
  BEGIN OF ty_cell,
    row   TYPE i,
    field TYPE fieldname,
    value TYPE string,
  END OF ty_cell,
  tt_cell TYPE SORTED TABLE OF ty_cell WITH UNIQUE KEY row field,

  BEGIN OF ty_rowfield,
    row   TYPE i,
    field TYPE fieldname,
  END OF ty_rowfield,
  tt_rowfield TYPE SORTED TABLE OF ty_rowfield WITH UNIQUE KEY row field,

  "Template row
  BEGIN OF ty_row,
    row    TYPE i,
    matkey TYPE string,              "MATNR or '#<row>' (internal numbering)
    werks  TYPE werks_d,
    vkorg  TYPE vkorg,
    vtweg  TYPE vtweg,
  END OF ty_row,
  tt_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY
         WITH NON-UNIQUE SORTED KEY k_mat COMPONENTS matkey
         WITH NON-UNIQUE SORTED KEY k_row COMPONENTS row,

  "Log / ALV output
  BEGIN OF ty_msg,
    icon  TYPE icon_d,
    msgty TYPE symsgty,
    row   TYPE i,
    matnr TYPE char40,
    werks TYPE werks_d,
    vkorg TYPE vkorg,
    vtweg TYPE vtweg,
    view  TYPE char10,
    field TYPE fieldname,
    fdesc TYPE z_de_field_desc,
    text  TYPE bapi_msg,
  END OF ty_msg,
  tt_msg TYPE STANDARD TABLE OF ty_msg WITH EMPTY KEY
         WITH NON-UNIQUE SORTED KEY k_row COMPONENTS row msgty
         WITH UNIQUE HASHED KEY k_dup COMPONENTS row msgty field text,   "duplicate check

  tt_msg_out TYPE STANDARD TABLE OF ty_msg WITH EMPTY KEY,    "ALV copy of the log

  "Message counter per type
  BEGIN OF ty_msgcnt,
    msgty TYPE symsgty,
    cnt   TYPE i,
  END OF ty_msgcnt,
  tt_msgcnt TYPE HASHED TABLE OF ty_msgcnt WITH UNIQUE KEY msgty,

  "Line index of table parameters (param + line key -> index)
  BEGIN OF ty_linekey,
    param TYPE fieldname,
    key   TYPE string,
    idx   TYPE i,
  END OF ty_linekey,
  tt_linekey TYPE STANDARD TABLE OF ty_linekey WITH EMPTY KEY,

  tt_views   TYPE SORTED TABLE OF char10 WITH UNIQUE KEY table_line,
  tt_atnam   TYPE SORTED TABLE OF atnam WITH UNIQUE KEY table_line,

  "Further classes of the same class type (copied from the reference material)
  BEGIN OF ty_classdata,
    classkey        TYPE bapi1003_key,
    allocvalueschar TYPE STANDARD TABLE OF bapi1003_alloc_values_char WITH EMPTY KEY,
    allocvaluesnum  TYPE STANDARD TABLE OF bapi1003_alloc_values_num  WITH EMPTY KEY,
    allocvaluescurr TYPE STANDARD TABLE OF bapi1003_alloc_values_curr WITH EMPTY KEY,
  END OF ty_classdata,
  tt_classdata TYPE STANDARD TABLE OF ty_classdata WITH EMPTY KEY,

  "Template data of one row, mapped to the structures of
  "BAPI_MATERIAL_SAVEREPLICA (one line per org. level parameter).
  "Component names = BAPI parameter names (used dynamically!)
  BEGIN OF ty_bapi,
    headdata            TYPE bapie1matheader,
    clientdata          TYPE bapie1mara,
    plantdata           TYPE bapie1marc,
    forecastparameters  TYPE bapie1mpop,
    planningdata        TYPE bapie1mpgd,
    storagelocationdata TYPE bapie1mard,
    valuationdata       TYPE bapie1mbew,
    warehousenumberdata TYPE bapie1mlgn,
    salesdata           TYPE bapie1mvke,
    storagetypedata     TYPE bapie1mlgt,
    materialdescription TYPE STANDARD TABLE OF bapie1makt WITH EMPTY KEY,
    unitsofmeasure      TYPE STANDARD TABLE OF bapie1marm WITH EMPTY KEY,
    internationalartnos TYPE STANDARD TABLE OF bapie1mean WITH EMPTY KEY,
    materiallongtext    TYPE STANDARD TABLE OF bapie1mltx WITH EMPTY KEY,
    taxclassifications  TYPE STANDARD TABLE OF bapie1mlan WITH EMPTY KEY,

    prtdata             TYPE bapie1mfhm,
    extensionin         TYPE bapie1parex,
    forecastvalues      TYPE bapie1mprw,
    unplndconsumption   TYPE bapie1mveu,
    totalconsumption    TYPE bapie1mveg,
    returnmessages      TYPE bapie1ret2,
    clientdatacwm       TYPE /cwm/bapie1mara,
    unitsofmeasurecwm   TYPE /cwm/bapie1marm,
    valuationdatacwm    TYPE /cwm/bapie1mbew,
    matplstadata        TYPE bapie1matplsta,
    marc_aps_extdata    TYPE bapie1marc_aps_ext,
    demand_penaltydata  TYPE bapie1ppo_dmnd_penalty,

    "classification (BAPI_OBJCL_*)
    classkey            TYPE bapi1003_key,
    allocvalueschar     TYPE STANDARD TABLE OF bapi1003_alloc_values_char WITH EMPTY KEY,
    allocvaluesnum      TYPE STANDARD TABLE OF bapi1003_alloc_values_num  WITH EMPTY KEY,
    allocvaluescurr     TYPE STANDARD TABLE OF bapi1003_alloc_values_curr WITH EMPTY KEY,
    extra_class         TYPE tt_classdata,       "further classes (reference with several classes)
    "meta data
    row                 TYPE i,
    matkey              TYPE string,
    views               TYPE tt_views,           "views with data in this row
    line_keys           TYPE tt_linekey,
  END OF ty_bapi,
  tt_bapi TYPE STANDARD TABLE OF ty_bapi WITH EMPTY KEY
          WITH NON-UNIQUE SORTED KEY k_mat COMPONENTS matkey,

  "Origin of a BAPI table line (for message -> template row)
  BEGIN OF ty_origin,
    param TYPE fieldname,
    idx   TYPE i,
    row   TYPE i,
  END OF ty_origin,
  tt_origin TYPE STANDARD TABLE OF ty_origin WITH EMPTY KEY,

  "One BAPI_MATERIAL_SAVEREPLICA call = one material, all org. levels.
  "Component names = TABLES parameter names of the BAPI
  BEGIN OF ty_call,

    headdata             TYPE STANDARD TABLE OF bapie1matheader            WITH EMPTY KEY,
    clientdata           TYPE STANDARD TABLE OF bapie1mara                 WITH EMPTY KEY,
    clientdatax          TYPE STANDARD TABLE OF bapie1marax                WITH EMPTY KEY,
    plantdata            TYPE STANDARD TABLE OF bapie1marc                 WITH EMPTY KEY,
    plantdatax           TYPE STANDARD TABLE OF bapie1marcx                WITH EMPTY KEY,
    forecastparameters   TYPE STANDARD TABLE OF bapie1mpop                 WITH EMPTY KEY,
    forecastparametersx  TYPE STANDARD TABLE OF bapie1mpopx                WITH EMPTY KEY,
    planningdata         TYPE STANDARD TABLE OF bapie1mpgd                 WITH EMPTY KEY,
    planningdatax        TYPE STANDARD TABLE OF bapie1mpgdx                WITH EMPTY KEY,
    storagelocationdata  TYPE STANDARD TABLE OF bapie1mard                 WITH EMPTY KEY,
    storagelocationdatax TYPE STANDARD TABLE OF bapie1mardx                WITH EMPTY KEY,
    valuationdata        TYPE STANDARD TABLE OF bapie1mbew                 WITH EMPTY KEY,
    valuationdatax       TYPE STANDARD TABLE OF bapie1mbewx                WITH EMPTY KEY,
    warehousenumberdata  TYPE STANDARD TABLE OF bapie1mlgn                 WITH EMPTY KEY,
    warehousenumberdatax TYPE STANDARD TABLE OF bapie1mlgnx                WITH EMPTY KEY,
    salesdata            TYPE STANDARD TABLE OF bapie1mvke                 WITH EMPTY KEY,
    salesdatax           TYPE STANDARD TABLE OF bapie1mvkex                WITH EMPTY KEY,
    storagetypedata      TYPE STANDARD TABLE OF bapie1mlgt                 WITH EMPTY KEY,
    storagetypedatax     TYPE STANDARD TABLE OF bapie1mlgtx                WITH EMPTY KEY,
    materialdescription  TYPE STANDARD TABLE OF bapie1makt                 WITH EMPTY KEY,
    unitsofmeasure       TYPE STANDARD TABLE OF bapie1marm                 WITH EMPTY KEY,
    unitsofmeasurex      TYPE STANDARD TABLE OF bapie1marmx                WITH EMPTY KEY,
    internationalartnos  TYPE STANDARD TABLE OF bapie1mean                 WITH EMPTY KEY,
    materiallongtext     TYPE STANDARD TABLE OF bapie1mltx                 WITH EMPTY KEY,
    taxclassifications   TYPE STANDARD TABLE OF bapie1mlan                 WITH EMPTY KEY,
    prtdata              TYPE STANDARD TABLE OF bapie1mfhm                 WITH EMPTY KEY,
    prtdatax             TYPE STANDARD TABLE OF bapie1mfhmx                WITH EMPTY KEY,
    extensionin          TYPE STANDARD TABLE OF bapie1parex                WITH EMPTY KEY,
    extensioninx         TYPE STANDARD TABLE OF bapie1parexx               WITH EMPTY KEY,
    forecastvalues       TYPE STANDARD TABLE OF bapie1mprw                 WITH EMPTY KEY,
    unplndconsumption    TYPE STANDARD TABLE OF bapie1mveu                 WITH EMPTY KEY,
    totalconsumption     TYPE STANDARD TABLE OF bapie1mveg                 WITH EMPTY KEY,
    returnmessages       TYPE STANDARD TABLE OF bapie1ret2                 WITH EMPTY KEY,
    clientdatacwm        TYPE STANDARD TABLE OF /cwm/bapie1mara            WITH EMPTY KEY,
    clientdatacwmx       TYPE STANDARD TABLE OF /cwm/bapie1marax           WITH EMPTY KEY,
    unitsofmeasurecwm    TYPE STANDARD TABLE OF /cwm/bapie1marm            WITH EMPTY KEY,
    unitsofmeasurecwmx   TYPE STANDARD TABLE OF /cwm/bapie1marmx           WITH EMPTY KEY,
    valuationdatacwm     TYPE STANDARD TABLE OF /cwm/bapie1mbew            WITH EMPTY KEY,
    valuationdatacwmx    TYPE STANDARD TABLE OF /cwm/bapie1mbewx           WITH EMPTY KEY,
    matplstadata         TYPE STANDARD TABLE OF bapie1matplsta             WITH EMPTY KEY,
    matplstadatax        TYPE STANDARD TABLE OF bapie1matplstax            WITH EMPTY KEY,
    marc_aps_extdata     TYPE STANDARD TABLE OF bapie1marc_aps_ext         WITH EMPTY KEY,
    marc_aps_extdatax    TYPE STANDARD TABLE OF bapie1marc_aps_extx        WITH EMPTY KEY,
    demand_penaltydata   TYPE STANDARD TABLE OF bapie1ppo_dmnd_penalty     WITH EMPTY KEY,
    demand_penaltydatax  TYPE STANDARD TABLE OF bapie1ppo_dmnd_penaltyx    WITH EMPTY KEY,

    origin               TYPE tt_origin,

  END OF ty_call,

  "Reference material cache
  BEGIN OF ty_refcache,
    key  TYPE string,
    data TYPE ty_bapi,
  END OF ty_refcache,
  tt_refcache TYPE STANDARD TABLE OF ty_refcache WITH EMPTY KEY,

  "Class master (KLAH / KSML / CABN / CAWN) - read once per class
  tt_atwrt TYPE SORTED TABLE OF cawn-atwrt WITH UNIQUE KEY table_line,
  BEGIN OF ty_charinfo,
    atnam  TYPE atnam,
    atinn  TYPE atinn,
    atfor  TYPE cabn-atfor,                       "CHAR NUM CURR DATE TIME
    anzst  TYPE cabn-anzst,                       "number of characters
    atein  TYPE cabn-atein,                       "single value
    atson  TYPE cabn-atson,                       "additional values allowed
    atkle  TYPE cabn-atkle,                       "case sensitive
    values TYPE tt_atwrt,                         "allowed values (CAWN)
  END OF ty_charinfo,
  tt_charinfo TYPE HASHED TABLE OF ty_charinfo WITH UNIQUE KEY atnam,
  BEGIN OF ty_classinfo,
    class  TYPE klah-class,
    klart  TYPE klah-klart,
    exists TYPE abap_bool,
    chars  TYPE tt_charinfo,                      "incl. superior classes
  END OF ty_classinfo,
  tt_classinfo TYPE HASHED TABLE OF ty_classinfo WITH UNIQUE KEY class klart,

  "Existence buffers (one SELECT per table for all template materials)
  tt_matnr_set TYPE SORTED TABLE OF matnr WITH UNIQUE KEY table_line,
  BEGIN OF ty_matnr_line,
    matnr TYPE matnr,
  END OF ty_matnr_line,
  tt_matnr_list TYPE STANDARD TABLE OF ty_matnr_line WITH EMPTY KEY,
  BEGIN OF ty_ex_mara,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    mbrsh TYPE mara-mbrsh,
  END OF ty_ex_mara,
  tt_ex_mara TYPE SORTED TABLE OF ty_ex_mara WITH UNIQUE KEY matnr,
  BEGIN OF ty_ex_marc,
    matnr TYPE marc-matnr,
    werks TYPE marc-werks,
  END OF ty_ex_marc,
  tt_ex_marc TYPE SORTED TABLE OF ty_ex_marc WITH UNIQUE KEY matnr werks,
  BEGIN OF ty_ex_mvke,
    matnr TYPE mvke-matnr,
    vkorg TYPE mvke-vkorg,
    vtweg TYPE mvke-vtweg,
  END OF ty_ex_mvke,
  tt_ex_mvke TYPE SORTED TABLE OF ty_ex_mvke WITH UNIQUE KEY matnr vkorg vtweg,
  BEGIN OF ty_ex_mard,
    matnr TYPE mard-matnr,
    werks TYPE mard-werks,
    lgort TYPE mard-lgort,
  END OF ty_ex_mard,
  tt_ex_mard TYPE SORTED TABLE OF ty_ex_mard WITH UNIQUE KEY matnr werks lgort,
  BEGIN OF ty_ex_mbew,
    matnr TYPE mbew-matnr,
    bwkey TYPE mbew-bwkey,
    bwtar TYPE mbew-bwtar,
  END OF ty_ex_mbew,
  tt_ex_mbew TYPE SORTED TABLE OF ty_ex_mbew WITH UNIQUE KEY matnr bwkey bwtar,
  BEGIN OF ty_ex_mlgn,
    matnr TYPE mlgn-matnr,
    lgnum TYPE mlgn-lgnum,
  END OF ty_ex_mlgn,
  tt_ex_mlgn TYPE SORTED TABLE OF ty_ex_mlgn WITH UNIQUE KEY matnr lgnum.
