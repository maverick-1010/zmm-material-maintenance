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

INCLUDE zmm_material_maintenance_d01.
INCLUDE zmm_material_maintenance_s01.
INCLUDE zmm_material_maintenance_c01.
INCLUDE zmm_material_maintenance_c02.

*----------------------------------------------------------------------*
INITIALIZATION.
  lcl_screen=>initialization( ).

AT SELECTION-SCREEN OUTPUT.
  lcl_screen=>pbo( ).

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file1.
  lcl_screen=>f4_local_file( CHANGING cv_file = p_file1 ).

AT SELECTION-SCREEN.
  lcl_screen=>pai( ).

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
