# mmo-ecc-dyn-processor-workflow — Functional Specification & Test Baseline

> **Purpose**: This document serves as a functional baseline for the ECC Dynamics Processor Logic App. It captures every scenario the workflow handles so it can be used as a regression test suite after optimisation work is complete.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Trigger](#2-trigger)
3. [Payload Parsing & Transformation](#3-payload-parsing--transformation)
4. [Variable Initialisation & Extraction](#4-variable-initialisation--extraction)
5. [Cloned Document Handling](#5-cloned-document-handling)
6. [Case Type 2 Mapping for PS and SD](#6-case-type-2-mapping-for-ps-and-sd)
7. [Reference Data Lookups (Parallel)](#7-reference-data-lookups-parallel)
8. [Exporter Resolution](#8-exporter-resolution)
9. [Document Processing](#9-document-processing)
10. [Catch/Product Processing](#10-catchproduct-processing)
11. [Landing Processing](#11-landing-processing)
12. [Message Completion & Final Status](#12-message-completion--final-status)
13. [End-to-End Scenario Matrix](#13-end-to-end-scenario-matrix)
14. [Identified Issues & Risks](#14-identified-issues--risks)

---

## 1. Overview

The workflow receives ECC (Export Catch Certificate) messages from an Azure Service Bus queue, processes the payload to create or update records in Dynamics 365 (Dataverse), and completes the message upon success.

**Dynamics 365 entities affected**:
- `mmofe_documents` — Export documents
- `incidents` — Cases (linked to documents)
- `mmofe_landingses` — Landing records
- `mmofe_catchproducts` — Catch/product records
- `accounts` / `contacts` — Exporter customer records

**Reference data sources** (Azure Table Storage, table `mmorefdata`):
- `CaseType` partition — Case type IDs
- `DevolvedAdministrations` partition — DA IDs
- `Species` partition — Species IDs
- `State` partition — Fish state IDs
- `Presentation` partition — Presentation IDs
- `LandingStatus` partition — Landing validation status IDs

---

## 2. Trigger

| Property | Value |
|----------|-------|
| Type | Service Bus peek-lock (session-enabled) |
| Queue | `mmo-ecc-dyn-req-queue` |
| Session | Next Available |
| Polling Interval | 30 seconds |
| Concurrency | 10 parallel runs |
| Queue Type | Main |
| Dead Letter | After 10 failed deliveries, message moves to dead letter queue |

### Test Scenarios — Trigger

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| T-01 | Valid message arrives on queue | Workflow triggers, message locked |
| T-02 | No messages on queue | No workflow run triggered |
| T-03 | 10+ messages arrive simultaneously | Max 10 concurrent workflow runs; remaining messages wait |
| T-04 | Session-based ordering | Messages with same SessionId processed in order |

---

## 3. Payload Parsing & Transformation

**Actions**: `Parse_Payload_to_Object` → `Tranform_Payload`

The Service Bus message body (`ContentData`) is Base64-decoded and parsed to JSON.

### Transformation Logic

| Condition | Transformation |
|-----------|---------------|
| Payload contains `documentNumber` property | Use payload as-is (document-level message: CC, PS, or SD) |
| Payload does NOT contain `documentNumber` (is an array) | Wrap in `{"landings": [<original array>]}` (landing-detail-only message) |

### Test Scenarios — Parsing

| ID | Scenario | Input | Expected Output |
|----|----------|-------|-----------------|
| P-01 | Catch Certificate payload | `{"documentNumber":"CC-123", "caseType1":"CC", ...}` | Payload used as-is |
| P-02 | Processing Statement payload | `{"documentNumber":"PS-456", "caseType1":"PS", ...}` | Payload used as-is |
| P-03 | Storage Document payload | `{"documentNumber":"SD-789", "caseType1":"SD", ...}` | Payload used as-is |
| P-04 | Landing-detail-only payload (array) | `[{"documentNumber":"CC-123", "landingDate":"...", ...}]` | Wrapped as `{"landings":[...]}` |
| P-05 | Malformed Base64 content | Invalid Base64 | Workflow fails at `Parse_Payload_to_Object` |
| P-06 | Invalid JSON after decode | Valid Base64, invalid JSON | Workflow fails at `Parse_Payload_to_Object` |

---

## 4. Variable Initialisation & Extraction

After parsing, the workflow initialises ~30 variables sequentially and extracts values from the payload.

### Key Variable Extraction Rules

| Variable | Source | Fallback |
|----------|--------|----------|
| `Payload` | Transformed payload object | — |
| `Landings` | `payload.landings` | `null` |
| `CatchesProductsArray` | `payload.catches` → `payload.products` | `null` |
| `Exporter` | `payload.exporter` → `payload.exporterDetails` → `payload.exporterId` (wrapped) → `first(Landings).exporter` | — |
| `Validation` | `payload.validation` | `null` |
| `CorrelationId` | `payload._correlationId` → `first(Landings)._correlationId` | `""` |
| `DocumentNumber` | `payload.documentNumber` → `first(Landings).documentNumber` | — (will error if both absent) |
| `DocumentDate` | `payload.documentDate` → `first(Landings).documentDate` | `""` |
| `DocumentUrl` | `payload.documentUrl` → `first(Landings).documentUrl` | `""` |
| `ContactId` | `Exporter.contactId` | `""` |
| `AccountId` | `Exporter.accountId` | `""` |
| `ExporterNumber` | `Exporter.exporterNumber` | `""` |
| `DevolvedAdministrationName` | `payload.da` | `null` |
| `CaseTypeName` | `payload.caseType1`: `CC`→`Catch Certificate`, `PS`→`Processing Statement`, `SD`→`Storage Document` | `Catch Certificate` |
| `CaseTypeName4` | `payload.caseStatusAtSubmission` | `null` |
| `Iteration` | `payload.numberOfFailedSubmissions` | `0` |
| `NumberOfFailedSubmissions` | `payload.numberOfFailedSubmissions` | `0` |
| `CloneDocNo` | `payload.clonedFrom` | `null` |
| `Terminate` | — | `false` |

### Test Scenarios — Variable Extraction

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| V-01 | CC payload with all fields present | All variables populated from root payload |
| V-02 | PS payload with `exporterDetails` instead of `exporter` | Exporter extracted from `exporterDetails` |
| V-03 | Payload with `exporterId` only (no exporter object) | Exporter wrapped as `{exporterNumber: <id>}` |
| V-04 | Landing-detail-only payload | DocumentNumber, CorrelationId, DocumentDate, DocumentUrl, Exporter all extracted from first landing |
| V-05 | Payload with `catches` array | `CatchesProductsArray` set to catches |
| V-06 | Payload with `products` array (no `catches`) | `CatchesProductsArray` set to products |
| V-07 | Payload with neither `catches` nor `products` | `CatchesProductsArray` = `null` |
| V-08 | Payload with no `landings` | `Landings` = `null` |
| V-09 | Payload with `numberOfFailedSubmissions` = 3 | `Iteration` = 3, `NumberOfFailedSubmissions` = 3 |
| V-10 | Payload without `numberOfFailedSubmissions` | `Iteration` = 0, `NumberOfFailedSubmissions` = 0 |

---

## 5. Cloned Document Handling

**Action**: `Is_Cloned_Document`

| Condition | Behaviour |
|-----------|-----------|
| `CloneDocNo` is not null and not empty | Query `mmofe_documents` by `mmofe_name eq CloneDocNo`, set `CloneDocId` from result |
| `CloneDocNo` is null or empty | Skip — `CloneDocId` remains empty |

### Test Scenarios — Cloning

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| CL-01 | Payload has `clonedFrom: "CC-100"` and CC-100 exists | `CloneDocId` set to the document ID of CC-100 |
| CL-02 | Payload has `clonedFrom: "CC-100"` but CC-100 does NOT exist | `CloneDocId` set to empty/null (no result from query; may fail on index access) |
| CL-03 | Payload has no `clonedFrom` | `CloneDocId` remains empty, query skipped |

---

## 6. Case Type 2 Mapping for PS and SD

**Action**: `Map_Casetype2_for_PS_and_SD`

This mapping runs ONLY when the payload does **not** contain `caseStatusAtSubmission`.

### CaseTypeName2 Derivation

The source value comes from `payload.caseType2` if present, otherwise from `first(Landings).status`.

| Source Value | Mapped CaseTypeName2 |
|-------------|----------------------|
| `Validation Success` | `Real Time Validation - Successful` |
| `Pending Landing Data` | `Pending Landing Data` |
| `Validation Failure - Overuse` | `Real Time Validation - Overuse Failure` |
| Any other value | Used as-is |

### Test Scenarios — CaseType2 Mapping

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| CT-01 | Payload has `caseType2: "Validation Success"`, no `caseStatusAtSubmission` | CaseTypeName2 = `Real Time Validation - Successful` |
| CT-02 | Payload has `caseType2: "Pending Landing Data"` | CaseTypeName2 = `Pending Landing Data` |
| CT-03 | Payload has `caseType2: "Validation Failure - Overuse"` | CaseTypeName2 = `Real Time Validation - Overuse Failure` |
| CT-04 | Payload has `caseType2: "Void by an Exporter"` | CaseTypeName2 = `Void by an Exporter` (pass-through) |
| CT-05 | No `caseType2` in payload; first landing status = `Validation Success` | CaseTypeName2 = `Real Time Validation - Successful` |
| CT-06 | Payload contains `caseStatusAtSubmission` | Entire mapping skipped; CaseTypeName2 unmodified |

---

## 7. Reference Data Lookups (Parallel)

After CaseType2 mapping, **five scopes run in parallel**:

| # | Scope | Source | Action |
|---|-------|--------|--------|
| 1 | `Retrieve_Case_Types_and_Set_CaseTypeId` | Table Storage: `CaseType` / `CaseTypeName` | Set `CaseTypeId`. If not found → default `00000000-0000-0000-0000-000000000000` |
| 2 | `Retrieve_Case_Types_and_Set_CaseTypeId2` | Table Storage: `CaseType` / `CaseTypeName2` | Set `CaseTypeId2`. If not found → remains empty |
| 3 | `Retrieve_Case_Types_and_Set_CaseStatusAtSubmission` | Table Storage: `CaseType` / `CaseTypeName4` | Set `CaseStatusAtSubmission`. If not found → remains empty |
| 4 | `Retrieve_Devolved_Administration_and_Set_DevolvedAdministrationId` | Table Storage: `DevolvedAdministrations` / `DevolvedAdministrationName` | Set `DevolvedAdministrationId`. If not found → remains empty |
| 5 | `Create_or_Retrieve_Exporter_and_Set_CustomerId` | Dataverse: `accounts` / `contacts` | See [Section 8](#8-exporter-resolution) |

All Table Storage HTTP calls use **exponential retry** (count: 10, interval: PT7S).

### Test Scenarios — Reference Data

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| RD-01 | CaseTypeName = `Catch Certificate` exists in Table Storage | `CaseTypeId` set to matching ID |
| RD-02 | CaseTypeName not found in Table Storage | `CaseTypeId` = `00000000-0000-0000-0000-000000000000` |
| RD-03 | CaseTypeName2 = `Real Time Validation - Successful` exists | `CaseTypeId2` set |
| RD-04 | CaseTypeName2 not found | `CaseTypeId2` remains empty |
| RD-05 | DevolvedAdministrationName = `England` exists | `DevolvedAdministrationId` set |
| RD-06 | DevolvedAdministrationName is null | `DevolvedAdministrationId` remains empty |
| RD-07 | Table Storage temporarily unavailable | Retried up to 10 times with exponential backoff |
| RD-08 | CaseStatusAtSubmission = `Pending` exists in Table Storage | `CaseStatusAtSubmission` set to matching ID |

---

## 8. Exporter Resolution

**Scope**: `Create_or_Retrieve_Exporter_and_Set_CustomerId`

Resolution follows a priority chain:

```
1. Look up Account by AccountId → if found, use Account
2. Look up Contact by ContactId → if found and no Account, use Contact
3. If neither found → use hardcoded fallback
```

### Detailed Logic

| Step | Condition | Action |
|------|-----------|--------|
| **If_AccountId_IS_NOT_null** | AccountId ≠ `""` | Query `accounts` where `accountid eq AccountId` (top 1) |
| **If_ContactId_IS_NOT_null** | ContactId ≠ `""` | Query `contacts` where `contactid eq ContactId` (top 1) |
| **Mapping_Account** | Account query returned results | Set `CustomerId` = accountid, `CustomerIdType` = `accounts` |
| **Mapping_Contact** | Account query returned NO results AND Contact query returned results | Set `CustomerId` = contactid, `CustomerIdType` = `contacts` |
| **Mapping_ExporterTemp** | BOTH Account and Contact queries returned no results | Set `CustomerId` = `3aad1982-5bb9-ea11-a812-000d3a20caa3` (hardcoded), `CustomerIdType` = `accounts` |

### Test Scenarios — Exporter Resolution

| ID | Scenario | Expected CustomerId | Expected CustomerIdType |
|----|----------|--------------------|-----------------------|
| EX-01 | AccountId exists in Dynamics | Account's accountid | `accounts` |
| EX-02 | AccountId does NOT exist, ContactId exists | Contact's contactid | `contacts` |
| EX-03 | Both AccountId and ContactId exist | Account's accountid (account takes priority) | `accounts` |
| EX-04 | Neither AccountId nor ContactId exist in Dynamics | `3aad1982-5bb9-ea11-a812-000d3a20caa3` | `accounts` |
| EX-05 | AccountId is empty, ContactId is empty | Queries skipped → hardcoded fallback | `accounts` |
| EX-06 | AccountId is empty, ContactId provided and exists | Contact's contactid | `contacts` |

---

## 9. Document Processing

**Scope**: `Document` — Runs after all parallel lookups complete.

### 9.1 Document Lookup

**Action**: `List_records_3` — Query `mmofe_documents` where `mmofe_documentnumber eq DocumentNumber` (top 1).

### 9.2 Scenario A: Document Does NOT Exist (New Document)

| Step | Action |
|------|--------|
| 1 | Create new `mmofe_documents` record with: DocumentNumber, CustomerId, CorrelationId, DocumentDate, DocumentUrl, payload, person responsible, processStatus=961040000 (Processing), statuscode based on void type |
| 2 | Set `DocumentId` from created record |
| 3 | **If** Landings ≥ 1 OR CatchesProductsArray ≥ 1 → Create Case (incident) with all case fields |
| 4 | Set `CaseId` from created case |

### 9.3 Scenario B: Document Already Exists

For each existing document record (`For_each_7`):

#### 9.3.1 Process Status Check

| Process Status | Meaning | Behaviour |
|---------------|---------|-----------|
| `961040000` | Processing | Continue processing (update document) |
| `961040001` | Processed | Continue processing (update/reprocess) |
| `null` | Unknown | Continue processing |
| Any other value | Fully processed | Set `Terminate = true` → skip further processing |

#### 9.3.2 Document Update (when processable)

| Step | Action |
|------|--------|
| 1 | Set `DocumentId` from existing record |
| 2 | Capture `Status_Reason` from existing document |
| 3 | Update document: `documentUrl`, `integrationpayload`, `statuscode` (void handling) |
| 4 | Query most recent Case by DocumentId (ordered by `createdon desc`, top 1) |

#### 9.3.3 Case Handling for Existing Documents

| Condition | Behaviour |
|-----------|-----------|
| No case exists AND (Landings ≥ 1 OR Catches ≥ 1) | Create new Case (`Create_Case_3`), set CaseId |
| No case exists AND no landings/catches | No case created, CaseId remains empty |
| Case exists AND case outcome = Rejected (961040001) AND payload has documentNumber | Create NEW Case (`Create_Case_2`) for resubmission, set CaseId |
| Case exists AND case outcome ≠ Rejected | Use existing CaseId |

#### 9.3.4 Voided Document — Landing Updates (`If_journey_is_CC`)

Triggered when:
- Existing landings found for this document (length > 0)
- AND document statuscode is `961040001` (Void by SMO/PMO) or `961040000` (Void by Exporter)

**Behaviour**: Iterates all existing landings and updates each with:
- `mmofe_daylimitreached` = `True`
- `statuscode` based on void type from payload

#### 9.3.5 Terminate Check

If `Terminate` = true (document was fully processed), the workflow terminates with `Succeeded` status — no landings or catches are processed.

### Test Scenarios — Document Processing

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| D-01 | New document, CC with landings | Document created → Case created → proceed to landings/catches |
| D-02 | New document, CC with catches only | Document created → Case created → proceed to catches |
| D-03 | New document, no landings or catches | Document created → NO case created → message completed |
| D-04 | Existing document (Processing status), no existing case, has landings | Document updated → new case created → proceed to landings/catches |
| D-05 | Existing document (Processed status), existing case (Issued) | Document updated → existing CaseId reused → proceed to landings/catches |
| D-06 | Existing document, existing case with Rejected outcome, payload has documentNumber | Document updated → NEW case created (resubmission) → proceed |
| D-07 | Existing document, existing case with Rejected outcome, payload has NO documentNumber | Document updated → existing CaseId reused (no resubmission) |
| D-08 | Existing document with non-processable status | `Terminate` = true → workflow ends Succeeded, no further processing |
| D-09 | Existing void document (`caseType2: "Void by an Exporter"`) with landings | Document updated with statuscode 961040000 → existing landings voided |
| D-10 | Existing void document (`caseType2: "Void by SMO/PMO"`) with landings | Document updated with statuscode 961040001 → existing landings voided |
| D-11 | Existing non-void document, no landings in Dynamics | Voiding step skipped |
| D-12 | Cloned document (CloneDocId populated) | `_mmofe_clonedfrom_value` set on new case |

---

## 10. Catch/Product Processing

**Scope**: `Create_or_Update_Catches_Products` — Runs after Document scope succeeds. Foreach concurrency: **20**.

### Per-Item Flow

For each item in `CatchesProductsArray`:

| Step | Action |
|------|--------|
| 1 | **List_records_7**: Query `mmofe_catchproducts` where `_mmofe_documentid_value eq DocumentId AND mmofe_name eq item.id` (top 1) |
| 2 | **If NOT exists** (length == 0): proceed to create |
| 3 | If `CaseId` is empty → Create new case (incident) with full case details, set CaseId |
| 4 | **Get_Species_for_CP**: Query Dynamics `mmofe_species` where `mmofe_name eq item.species` |
| 5 | **Get_Validation_Status_for_CP**: Query Dynamics `mmofe_validationstatuses` where `mmofe_name eq item.validation.status` |
| 6 | Compose `SpeciesId_CP` and `ValidationStatusId_CP` |
| 7 | **Create_a_new_record_9**: Create `mmofe_catchproducts` record |
| 8 | **If EXISTS**: No action (empty else branch — catch/product is NOT updated) |

### Catch/Product Record Fields

| Field | Source |
|-------|--------|
| `mmofe_name` | `item.id` |
| `mmofe_cncode` | `item.cnCode` |
| `mmofe_correlationid` | `CorrelationId` variable |
| `mmofe_exportedweight` | `item.exportedWeight` |
| `mmofe_foreigncatchcertificatenumber` | `item.foreignCatchCertificateNumber` |
| `mmofe_importedweight` | `item.importedWeight` |
| `mmofe_integrationpayload` | Entire item as string |
| `mmofe_iteration` | `Iteration` variable |
| `mmofe_type` | `true` if payload has `catches`, `false` if `products` |
| `_mmofe_caseid_value` | `CaseId` variable |
| `_mmofe_documentid_value` | `DocumentId` variable |
| `_mmofe_speciesid_value` | `SpeciesId_CP` |
| `_mmofe_validationstatusid_value` | `ValidationStatusId_CP` |

### Test Scenarios — Catches/Products

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| CP-01 | New catch item, CaseId already set | Catch/product created with existing CaseId |
| CP-02 | New catch item, CaseId is empty | New case created first → then catch/product created |
| CP-03 | Existing catch item (same DocumentId + item id) | Skipped — no update performed |
| CP-04 | Catch with species found in Dynamics | `_mmofe_speciesid_value` set to species ID |
| CP-05 | Catch with species NOT found in Dynamics | `SpeciesId_CP` = null |
| CP-06 | Catch with validation status found | `_mmofe_validationstatusid_value` set |
| CP-07 | Catch with no `validation.status` property | Validation status query uses empty string → likely not found → null |
| CP-08 | Item from `catches` array | `mmofe_type` = true |
| CP-09 | Item from `products` array | `mmofe_type` = false |
| CP-10 | Multiple catch items (e.g., 5) | All 5 processed (up to 20 concurrently) |
| CP-11 | CatchesProductsArray is null | Foreach not entered — scope completes |

---

## 11. Landing Processing

**Scope**: `Create_or_Update_Landings` — Runs after Document scope succeeds (parallel with catches). Foreach concurrency: **20**.

### Per-Landing Flow

For each landing in `Landings`:

#### 11.1 Reference Data Resolution (per landing, sequential)

| Step | Action | Source |
|------|--------|--------|
| 1 | `Get_Species` | Table Storage: `Species` / `landing.species` |
| 2 | `Get_Landing_Status` | Table Storage: `LandingStatus` / `landing.status` |
| 3 | `Get_State` | Table Storage: `State` / `landing.state` |
| 4 | `Get_Presentation` | Table Storage: `Presentation` / `landing.presentation` |
| 5 | Compose `SpeciesId` | From `Get_Species` result `.id` |
| 6 | Compose `ValidationStatusRetro` | Complex: if landing status is one of 3 specific IDs AND `landingOutcomeAtSubmission == 'Success'` AND `is14DayLimitReached == false` → `83770889-abc5-ea11-a812-000d3a20caa3`, else `""` |
| 7 | Compose `ValidationStatusId` | From `Get_Landing_Status` result `.id` |
| 8 | Compose `StateId` | From `Get_State` result `.id` |
| 9 | Compose `PresentationId` | From `Get_Presentation` result `.id` |
| 10 | Compose `Source` | `LANDING_DECLARATION` → 961040001, `CATCH_RECORDING` → 961040002, `ELOG` → 961040000, else null |
| 11 | Compose `VesselAdmin` | `England` → 961040000, `Scotland` → 961040001, `Wales` → 961040002, `Northern Ireland` → 961040003, `Isle of Man` → 961040004, `Jersey` → 961040005, `Guernsey` → 961040006 |
| 12 | Compose `NumberOfTotalSubmission` | `landing.numberOfTotalSubmissions` or null |

All Table Storage HTTP calls use **exponential retry** (count: 10, interval: PT7S).

#### 11.2 Landing Existence Check

**Action**: `List_records_6` — Query `mmofe_landingses` where:
- `_mmofe_documentid_value eq DocumentId`
- `AND mmofe_name eq landing.id`
- `AND mmofe_numberoftotalsubmissions eq NumberOfTotalSubmission`

#### 11.3 Scenario A: Landing Exists (length == 1) — Update

| Step | Action |
|------|--------|
| 1 | Compose `UpdateLandingId` from existing record |
| 2 | Compose `Existing_Source`, `Existing_Live_Export_Weight`, `Existing_IsLate` |
| 3 | If `CaseId` is empty → extract CaseId from existing landing's `_mmofe_caseid_value` |
| 4 | **Update_a_record**: Update ALL landing fields (see field mapping below) |
| 5 | **List_records_11**: Re-query landing after update |
| 6 | Compose `Updated_Source` from re-queried record |
| 7 | **Condition_9** (IsLate skip logic): see below |

**IsLate Skip Logic** (`Condition_9`): If ALL of the following are true, skip the isLate update:
- Existing Source == 961040000 (ELOG)
- Existing Live Export Weight < 50
- Existing IsLate == 961040001 (not late)
- Updated Source == 961040001 (LANDING_DECLARATION)

Otherwise → **Update_a_record_11**: Update `mmofe_late` field on the landing.

#### 11.4 Scenario B: Landing Does NOT Exist — Create

| Step | Action |
|------|--------|
| 1 | **Create_a_new_record_8**: Create new `mmofe_landingses` record with all fields |
| 2 | **List_records_10**: Re-query landing after creation |
| 3 | Compose `Updatelanding2` (new landing ID) |
| 4 | Set `Submission Landing Status` from created record |
| 5 | Set `Retrospective Period Complete` from created record's `mmofe_daylimitreached` |
| 6 | **Check_Submission_Landing_Status**: If landing status is one of 3 specific IDs AND `Retrospective Period Complete` == false → Update landing's `mmofe_landingoutcomeatretrospectivecheck` to 961040000 (Success) |

**The 3 specific landing status IDs**:
- `7d04d01c-d38f-ee11-8179-6045bd905f18`
- `3805cb04-d38f-ee11-8179-6045bd905f18`
- `954f914e-cd8e-ee11-8179-6045bd905d39`

### Landing Record Key Fields

| Field | Source |
|-------|--------|
| `mmofe_name` | `landing.id` |
| `mmofe_datelanding` | `landing.landingDate` (formatted yyyy-MM-dd) |
| `mmofe_weight` | `landing.weight` |
| `mmofe_sourcedata` | Composed `Source` value |
| `mmofe_vesseladministration` | Composed `VesselAdmin` value |
| `mmofe_vesselpln` | `landing.vesselName` |
| `mmofe_vesselnumber` | `landing.vesselPln` |
| `mmofe_commoditycode` | `landing.cnCode` |
| `mmofe_late` | `landing.isLate` → true=961040000, false=961040001 |
| `mmofe_liveexportweight` | `landing.validation.liveExportWeight` |
| `mmofe_numberoftotalsubmissions` | `NumberOfTotalSubmission` |
| `_mmofe_speciesid_value` | Composed `SpeciesId` |
| `_mmofe_stateid_value` | Composed `StateId` |
| `_mmofe_presentationid_value` | Composed `PresentationId` |
| `_mmofe_validationstatusid_value` | Landing update: prefers `ValidationStatusRetro` if non-empty, else `ValidationStatusId`. Landing create: `ValidationStatusRetro` |
| `_mmofe_validationstatusapplicationsubmissionid_value` | `ValidationStatusId` (create only) |

### Test Scenarios — Landings

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| L-01 | New landing (not in Dynamics) | Landing created with all fields |
| L-02 | Existing landing (same DocumentId + id + numberOfTotalSubmissions) | Landing updated with all fields |
| L-03 | Existing landing update — isLate skip condition met | `mmofe_late` NOT updated (ELOG source, weight < 50, not late, updated to LANDING_DECLARATION) |
| L-04 | Existing landing update — isLate skip condition NOT met | `mmofe_late` updated |
| L-05 | New landing with retrospective status (matching one of 3 IDs) and not 14-day-limited | `mmofe_landingoutcomeatretrospectivecheck` set to Success (961040000) |
| L-06 | New landing with non-retrospective status | No retrospective check update |
| L-07 | New landing, `Retrospective Period Complete` = true | Retrospective check update skipped |
| L-08 | Landing with source = `ELOG` | `mmofe_sourcedata` = 961040000 |
| L-09 | Landing with source = `LANDING_DECLARATION` | `mmofe_sourcedata` = 961040001 |
| L-10 | Landing with source = `CATCH_RECORDING` | `mmofe_sourcedata` = 961040002 |
| L-11 | Landing with vesselAdministration = `Scotland` | `mmofe_vesseladministration` = 961040001 |
| L-12 | Landing with vesselAdministration = `Guernsey` | `mmofe_vesseladministration` = 961040006 |
| L-13 | Landing with no `vesselAdministration` | `mmofe_vesseladministration` = null |
| L-14 | Landing with `speciesAlias: "Y"` | `mmofe_speciesalias` = true |
| L-15 | Landing with `speciesAlias: "N"` | `mmofe_speciesalias` = false |
| L-16 | Multiple landings (e.g., 10) | All 10 processed (up to 20 concurrently) |
| L-17 | Existing landing with CaseId empty | CaseId extracted from existing landing's `_mmofe_caseid_value` |
| L-18 | Landings array is null | Foreach not entered — scope completes |
| L-19 | Species not found in Table Storage | `Get_Species` returns 404 → `SpeciesId` compose likely fails |
| L-20 | Landing with `is14DayLimitReached: true` | `mmofe_daylimitreached` set accordingly; retrospective check skipped |

---

## 12. Message Completion & Final Status

### Flow

| Step | Action | runAfter |
|------|--------|----------|
| 1 | `Complete_the_message_in_a_queue` | `Create_or_Update_Catches_Products` [Succeeded] AND `Create_or_Update_Landings` [Succeeded] |
| 2 | `Update_Document_Process_Status` | `Complete_the_message_in_a_queue` [Succeeded] |

- Message completion: Deletes the peek-lock on the Service Bus message (using lock token and session ID)
- Document status update: Sets `mmofe_processstatus` = 961040001 (Processed) on the document

### Test Scenarios — Completion

| ID | Scenario | Expected Behaviour |
|----|----------|--------------------|
| MC-01 | Both landings and catches succeed | Message completed → document status = Processed |
| MC-02 | Landings succeed, no catches (null array) | Message completed → document status = Processed |
| MC-03 | Catches succeed, no landings (null array) | Message completed → document status = Processed |
| MC-04 | No landings and no catches (document-only) | Message completed → document status = Processed |

---

## 13. End-to-End Scenario Matrix

| ID | Scenario | Payload Shape | Key Outcomes |
|----|----------|---------------|-------------|
| E2E-01 | **New CC submission** — new exporter (account), new document, new case, new landings | `{documentNumber, caseType1:"CC", exporter:{accountId}, landings:[...]}` | Account found → Document created → Case created → Landings created → Message completed → Status = Processed |
| E2E-02 | **New CC submission** — exporter not in Dynamics | `{documentNumber, caseType1:"CC", exporter:{accountId:"unknown"}, landings:[...]}` | Fallback CustomerId used → Document created → Case created → Landings created |
| E2E-03 | **New PS submission** — with products | `{documentNumber, caseType1:"PS", exporter:{contactId}, products:[...]}` | Contact found → Document created → Case created → Products created |
| E2E-04 | **New SD submission** — with catches | `{documentNumber, caseType1:"SD", exporter:{accountId}, catches:[...]}` | Account found → Document created → Case created → Catches created |
| E2E-05 | **Resubmission** — document exists, case was Rejected | `{documentNumber, caseType1:"CC", ...}` (existing doc, case outcome=Rejected) | Document updated → NEW case created → new landings/catches |
| E2E-06 | **Update** — document exists, case was Issued | `{documentNumber, caseType1:"CC", ...}` (existing doc, case outcome=Issued) | Document updated → existing case reused → landings updated/created |
| E2E-07 | **Void by Exporter** — document exists with landings | `{documentNumber, caseType2:"Void by an Exporter", ...}` | Document updated (statuscode=961040000) → all existing landings voided |
| E2E-08 | **Void by SMO/PMO** — document exists with landings | `{documentNumber, caseType2:"Void by SMO/PMO", ...}` | Document updated (statuscode=961040001) → all existing landings voided |
| E2E-09 | **Landing-detail-only** — array payload | `[{documentNumber, landingDate, ...}, ...]` | Payload wrapped in `{landings:[...]}` → Document created → Case created → Landings created |
| E2E-10 | **Cloned document** — clonedFrom provided | `{documentNumber, clonedFrom:"CC-100", ...}` | CloneDocId resolved → passed to case as `_mmofe_clonedfrom_value` |
| E2E-11 | **Document already fully processed** | Existing document with process status ≠ Processing/Processed/null | `Terminate` = true → workflow ends immediately with Succeeded |
| E2E-12 | **Retrospective validation** — landing with pending status | New landing with status matching one of 3 retrospective IDs, `is14DayLimitReached: false` | Landing created → retrospective outcome set to Success |
| E2E-13 | **CC with both landings AND catches** | `{documentNumber, caseType1:"CC", landings:[...], catches:[...]}` | Both processed in parallel → message completed after both succeed |
| E2E-14 | **Update existing landing — isLate skip** | Existing ELOG landing, weight < 50, not late; new source = LANDING_DECLARATION | Landing updated but `mmofe_late` NOT modified |
| E2E-15 | **Existing catch/product resubmitted** | Catch with same DocumentId + item id already in Dynamics | Catch/product skipped (not updated) |
| E2E-16 | **CC with no landings and no catches** | `{documentNumber, caseType1:"CC"}` (no landings/catches arrays) | Document created → NO case created → message completed |

---

## 14. Identified Issues & Risks

### 14.1 Findings Table

| # | File | Action/Section | Issue | Severity | Detail |
|---|------|---------------|-------|----------|--------|
| 1 | workflow.json | Entire workflow | **No error handling or message abandonment on failure** | **Critical** | If ANY action fails (Dataverse 429/500, Table Storage timeout, expression error), the Service Bus message is NEVER explicitly abandoned or dead-lettered. The peek-lock will time out, and the message will be retried automatically up to 10 times. Each retry may create **partial data** in Dynamics (e.g., document exists but no case, case exists but only some landings). After 10 retries the message goes to the dead letter queue with no alerting or notification mechanism. |
| 2 | workflow.json | `Complete_the_message_in_a_queue` | **Message only completed on full success** — no graceful failure path | **Critical** | The `Complete_the_message_in_a_queue` action only runs after BOTH `Create_or_Update_Landings` [Succeeded] AND `Create_or_Update_Catches_Products` [Succeeded]. If either scope fails, the message lock expires, causing a silent retry. There is no `runAfter: ["Failed"]` branch anywhere in the workflow to abandon the message, log the error, or send a notification. |
| 3 | workflow.json | `Create_or_Update_Landings`, `Create_or_Update_Catches_Products` | **Partial write / data inconsistency on retry** | **Critical** | If the workflow partially succeeds (e.g., document + some landings created) and then fails, the retry will find the document already existing and take the "update" path. However: (a) landings already created won't be re-created (duplicate check passes) but other landings that weren't created yet will be created fresh — this is fine. (b) Catches/products that already exist are completely **skipped** (empty else branch) — they are **never updated**, so if a retry was caused by a failure mid-catches, the already-created catches will retain their original data even if the message had different values. |
| 4 | workflow.json | `Mapping_ExporterTemp` | **Hardcoded fallback CustomerId** | **High** | When neither Account nor Contact is found in Dynamics, the workflow falls back to a hardcoded GUID `3aad1982-5bb9-ea11-a812-000d3a20caa3`. If this account is deleted or deactivated in Dynamics, ALL messages with unknown exporters will fail. This should be a configurable parameter or app setting. |
| 5 | workflow.json | `For_each_4`, `For_each`, `For_each_2`, `For_each_6` | **SetVariable inside Foreach loops** | **High** | Multiple Foreach loops use `SetVariable` to set shared variables (`CustomerId`, `CustomerIdType`, `CaseId`). While the Foreach loops where this occurs only iterate over a single record (due to `$top: 1` queries), this is an anti-pattern. If queries ever returned multiple records, concurrent iterations would cause race conditions on the shared variable. |
| 6 | workflow.json | `For_each_3` (Landings) | **Concurrent Foreach mutates shared variables** | **High** | The landings Foreach has concurrency of 20 and mutates shared variables: `CaseId` (in `If_CaseId_is_null_Set_From_Dynamics`), `Submission Landing Status`, `Retrospective Period Complete`. If two landing iterations both find CaseId empty simultaneously, they could both attempt to read it from Dynamics, creating a race condition. The `Submission Landing Status` and `Retrospective Period Complete` variables are set per-iteration but read by subsequent logic — with concurrency enabled, values will be unpredictable. |
| 7 | workflow.json | `For_each_17` (Catches/Products) | **Concurrent Foreach mutates CaseId** | **High** | Similar to landings — if CaseId is empty, multiple concurrent iterations of the catches Foreach could all attempt to create a new case simultaneously, resulting in duplicate cases. The `Set_variable_18` action runs after `Create_a_new_record_4` on `["Succeeded", "Failed"]`, meaning CaseId could be set to null on failure, causing downstream issues. |
| 8 | workflow.json | `Set_variable_18`, `Set_Case_Id_3` | **CaseId set on both Succeeded AND Failed** | **High** | `Set_variable_18` (in catches) and `Set_Case_Id_3` (in document scope) have `runAfter: ["Succeeded", "Failed"]`. If the Create Case action fails, CaseId is set to whatever `body('...')?['incidentid']` evaluates to (likely null). Subsequent actions will then use a null/empty CaseId, creating orphaned records. |
| 9 | workflow.json | All Dataverse `ApiConnection` actions | **No retry policy on Dataverse API calls** | **Medium** | Table Storage HTTP actions have explicit exponential retry (count: 10, PT7S), but ALL Dataverse ApiConnection calls use the default retry policy. Dataverse is subject to throttling (429 responses), especially with concurrency of 20 on landing/catches loops. A single 429 could cascade into a workflow failure. |
| 10 | workflow.json | `List_records_12` | **No pagination / $top on landing query** | **Medium** | The query `List_records_12` (landings by DocumentId, used in void handling) has no `$top` parameter. For documents with large numbers of landings, this could exceed the Dataverse default page size (5000) and return incomplete results, leading to not all landings being voided. |
| 11 | workflow.json | `TODO_REMOVE:_Initialise_ExporterNumber` | **Dead code / TODO left in workflow** | **Low** | An action is named `TODO_REMOVE:_Initialise_ExporterNumber`, indicating it was intended to be removed. The `ExporterNumber` variable appears to be initialised but not used in any downstream actions. |
| 12 | workflow.json | `Get_Presentation` | **Duplicate query parameters** | **Low** | `Get_Presentation` has both a `queries` object (`PartitionKey`, `RowKey`) and a `path` that includes the entity key. Additionally it has a `uri` with the entity key. This is redundant and could cause confusion — the `queries` block is ignored when the path already includes the key. |
| 13 | workflow.json | Variable initialisation chain | **30+ sequential variable initialisations** | **Medium** | All ~30 variables are initialised in a strict sequential chain (`runAfter` one after another). This is a significant performance bottleneck — each initialisation is a separate action execution, adding latency. Many of these could potentially be parallelised or consolidated. |
| 14 | workflow.json | Landings Foreach | **4 sequential Table Storage lookups per landing** | **Medium** | Each landing iteration performs 4 sequential HTTP calls to Table Storage (Species → Landing Status → State → Presentation). With 20 landings, this means 80 sequential-per-item HTTP calls. These 4 lookups within each iteration could be parallelised. |
| 15 | workflow.json | `Create_Case`, `Create_Case_2`, `Create_Case_3`, `Create_a_new_record_4` | **Duplicated case creation logic in 4 places** | **Medium** | The case (incident) creation body is duplicated in at least 4 different actions with near-identical field mappings. Any change to the case creation logic must be applied in all 4 places, increasing maintenance risk and the chance of inconsistency. |
| 16 | workflow.json | `Create_a_new_record_8` (create landing), `Update_a_record` (update landing) | **Duplicated landing field mappings** | **Medium** | The landing create and update paths have nearly identical field mapping logic duplicated in two large action bodies. Any new field or mapping change must be applied in both places. |
| 17 | workflow.json | `Condition_9` (isLate skip) | **Undocumented business rule** | **Low** | The condition that skips isLate updates when (source=ELOG, weight<50, notLate, updatedSource=LANDING_DECLARATION) is a complex business rule embedded directly in workflow JSON with no comments or documentation explaining the rationale. |
| 18 | workflow.json | `ValidationStatusRetro` compose | **Complex inline expression** | **Low** | The `ValidationStatusRetro` compose uses a deeply nested inline expression with 3 hardcoded GUIDs, multiple boolean conditions, and a hardcoded result GUID (`83770889-abc5-ea11-a812-000d3a20caa3`). Any change to these status IDs requires editing the expression directly. |
| 19 | workflow.json | Entire workflow | **No observability / logging actions** | **Medium** | The workflow has no explicit logging, tracing, or alerting actions. Failures are silent — the only indication is the message eventually landing in the dead letter queue after 10 retries, or the workflow run history in the Azure portal. |
| 20 | workflow.json | Service Bus trigger + Document processing | **Idempotency not fully guaranteed** | **High** | While the workflow checks for existing documents and landings before creating, the checks and creates are NOT atomic. With the 10-retry mechanism and concurrent workflow runs (concurrency: 10), two workflow runs processing the same SessionId message could overlap if lock timeouts occur, potentially creating duplicate documents. |

### 14.2 Risk Summary

| Severity | Count | Key Concerns |
|----------|-------|-------------|
| **Critical** | 3 | No error handling, no message abandonment, partial writes on retry |
| **High** | 5 | Hardcoded IDs, race conditions in concurrent loops, CaseId set on failure |
| **Medium** | 5 | No Dataverse retry policies, missing pagination, sequential bottlenecks, duplicated logic, no logging |
| **Low** | 4 | Dead code, duplicate query params, undocumented rules, complex expressions |

### 14.3 Recommended Mitigations (for optimisation phase)

1. **Add top-level Scope with error handling**: Wrap all processing in a Scope with a `runAfter: ["Failed"]` error branch that explicitly abandons the Service Bus message and logs the error.
2. **Implement message dead-lettering for non-transient errors**: If the error is a validation issue (bad payload, missing required fields), dead-letter the message immediately rather than retrying 10 times.
3. **Add explicit message abandonment**: On failure, abandon the message with a reason so the retry mechanism is immediate rather than waiting for lock timeout.
4. **Replace hardcoded fallback CustomerId** with a configurable app setting / parameter.
5. **Reduce Foreach concurrency or eliminate shared variable mutation**: Either set concurrency to 1 for loops that mutate shared state, or refactor to avoid shared variables.
6. **Add retry policies to Dataverse API calls**: Especially important given 20-concurrent-iteration loops.
7. **Add Application Insights / custom logging** at key decision points.
8. **Consolidate duplicated case/landing creation logic** into sub-workflows or reduce to a single code path.
9. **Parallelise variable initialisation** where there are no data dependencies.
10. **Parallelise per-landing reference data lookups** (Species, State, Presentation, Landing Status can run concurrently).

---

*Document generated: 21 April 2026*
*Source: `mmo-ecc-dyn-processor-workflow/mmo-ecc-dyn-processor_workflow/workflow.json`*
*Baseline for: Workflow optimisation regression testing*
