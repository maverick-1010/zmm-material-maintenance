# ZMM_MATERIAL_MAINTENANCE

SAP ABAP report for mass **creation, update and extension of material masters** from an Excel file, using `BAPI_MATERIAL_SAVEREPLICA`.

## Operations

| Operation | ACTION value | Purpose |
|---|---|---|
| Create | `C` / `CREATE` | Create new materials (optionally copying data from a reference material) |
| Update | `U` / `UPDATE` / `CHANGE` | Change existing materials - only filled cells are sent, an empty cell never clears a field |
| Extend | `E` / `EXTEND` | Extend existing materials to new plants, storage locations or sales areas |

## Main features

- Variant selection by material type, industry sector, business profile and operation (`ZTMM_MATMAS_MAST`); mandatory/default fields come from the `ZTMM_*_DATA`, `ZTMM_DEFLT_DATA` and `ZTMM_COND_MAND` configuration tables.
- Reference material copy (Create / Extend) with `COPY_*` flags.
- Product hierarchy, classification (`BAPI_OBJCL_*`), purchase order text (`PO_TEXT`) and sales text (`SALES_TEXT`).
- **Test run** (simulation) and **actual run**. In an actual run every row is simulated first with a temporary number; a real number is drawn from the number range only after the simulation succeeded, so failed rows do not waste material numbers.
- Upload from the local PC or from the application server (background processing possible).
- ALV output, plus a result Excel file `MATMAINT_<C|U|E>_<date>_<time>.xlsx` (sheets `ALV_OUTPUT` and `MATERIAL_DATA`) written to the server and e-mailed in an actual run.

## Input file

- Excel `.xlsx`. Template layout: row 3 = technical field names, row 4 = descriptions, data from **row 5**.
- If the file has more than one worksheet, the **2nd sheet** is read (the 1st is an instruction sheet); with one worksheet, that sheet is read.
- Record limits (constants `gc_max_rows`): up to 1000 rows in foreground; 1001-2000 rows must be run in background; more than 2000 rows is rejected.
- Templates are stored in SMW0 (`ZMMCREATE_CRT_XLSX`, `ZMMCREATE_UPD_XLSX`, `ZMMCREATE_EXT_XLSX`) and downloaded from the selection screen.
- Excel files on the application server must be copied in **BINARY** mode (e.g. `CG3Z`); ASCII mode damages the file.

## Repository contents

| File | Content |
|---|---|
| `zmm_material_maintenance.abap` | Main report (includes the files below) |
| `zmm_material_maintenance_d01.abap` | Types, constants, data declarations |
| `zmm_material_maintenance_s01.abap` | Selection screen |
| `zmm_material_maintenance_c01.abap` | Local class definitions |
| `zmm_material_maintenance_c02.abap` | Local class implementations |
| `documents/Mass_Material_Maintenance_Training_Guide.docx` | End-user training guide (Create / Update / Extend) |
| `documents/ZMM_Material_Maintenance_Presentation.pptx` | Presentation of the development (functions and configuration tables) |
| `documents/instruction_sheets/` | Instruction sheets for the Create, Update and Extend Excel templates (add as the first sheet of each template) |

## Usage

1. Run the report, select the operation, material type, industry sector and business profile.
2. Download the template, fill the data sheet and save as `.xlsx`.
3. Run with **Test run** ticked and correct all errors in the ALV list.
4. Run again without Test run to post.
