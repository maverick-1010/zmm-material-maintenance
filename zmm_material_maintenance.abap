*&---------------------------------------------------------------------*
*& Report ZMM_MATERIAL_MAINTENANCE                                     *
*&---------------------------------------------------------------------*
* DESCRIPTION : Mass Material Maintenance Tool                         *
* AUTHOR      : Omkar Sutar(4023231)                                  *
* DATE        : 09 Sept 2026                                           *
* CHANGE REQ  : DMND0025421                                            *
* Description : This tool enables users to upload Mass Material Details*
*               using a template format to Create / Update or Extend   *
*               Materials                                              *
*----------------------------------------------------------------------*

REPORT zmm_material_maintenance.

* D01 : constants, types and global declarations
INCLUDE zmm_material_maintenance_d01.
* S01 : selection screen
INCLUDE zmm_material_maintenance_s01.
* C01 : local class definitions
INCLUDE zmm_material_maintenance_c01.
* C02 : local class implementations
INCLUDE zmm_material_maintenance_c02.

*----------------------------------------------------------------------*
* Initial screen values (template download button text)
INITIALIZATION.
  lcl_screen=>initialization( ).

* Screen output: enable / disable fields, fixed basic data checkbox, listboxes
AT SELECTION-SCREEN OUTPUT.
  lcl_screen=>pbo( ).

* F4 help for the template file on the PC
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file1.
  lcl_screen=>f4_local_file( CHANGING cv_file = p_file1 ).

* Screen input: template download button, check of the input on execute
AT SELECTION-SCREEN.
  lcl_screen=>pai( ).

* Processing: load configuration and template, validate and map, post the
* materials (test run: check only) and show / send the result log
START-OF-SELECTION.
  NEW lcl_app( )->run( ).
