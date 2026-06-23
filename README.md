# MMO FES Logic Apps

UK Government (DEFRA / Marine Management Organisation) fisheries export service (FES) integration workflows. Azure Logic Apps (Standard) that process export certificate data via Dynamics 365 (Dataverse) and synchronise reference data to Azure Table Storage.

These workflows are being incrementally optimised for **reliability, audit, consistency, and performance**, including a routing-slip decomposition of the monolithic ECC processor into smaller, independently-scalable stages connected by Service Bus queues.

## Logic Apps in this repository

| Logic App | Trigger | Role |
|-----------|---------|------|
| `mmo-ecc-dyn-processor-workflow` | Service Bus (peek-lock, session) on `mmo-ecc-dyn-req-queue` | **Monolith (baseline).** Reads ECC messages, creates/retrieves exporter records, creates the document + case, maps and upserts catch-certificate landings/products back to Dynamics 365. This is the regression baseline and is left **unmodified**. |
| `mmo-fes-processor-document-case-creation` | Service Bus (peek-lock, session) on `mmo-ecc-dyn-req-queue` | **Stage 1 of the split.** Reference-data resolution, exporter resolution, and **document + case creation only**. On success it publishes a hand-off envelope (with the new `documentId` and `caseId`) to `document-case-queue` and then completes the source message. |
| `mmo-ecc-dyn-processor-refdata-workflow` | Recurrence (monthly) | Pulls reference data (species, states, presentations, case types, landing statuses, devolved administrations) from Dynamics 365 and upserts into Azure Table Storage. |

> The downstream landings/catches stage (which consumes `document-case-queue`) is a later increment and is **not** part of this delivery.

---

## `mmo-fes-processor-document-case-creation` (new — Stage 1)

### Purpose

This logic app extracts the **document and case creation** responsibilities from the monolithic `mmo-ecc-dyn-processor-workflow` using the **routing-slip pattern**. It performs the early, document-scoped portion of the journey and hands the rest of the work (landings/catches upserts) to the next stage via a new Service Bus queue.

### Trigger (unchanged from the monolith)

- **Connector:** Service Bus `When a message is received in a queue (peek-lock)`
- **Queue:** `mmo-ecc-dyn-req-queue` (session-enabled)
- **Concurrency:** up to 10 concurrent runs; polling interval 30s
- **Correlation:** `clientTrackingId` is derived from the inbound payload's `_correlationId` (falling back to a generated GUID), so a run can be traced end-to-end across stages in Application Insights.

### What it does

1. Parse and transform the inbound ECC payload.
2. Resolve reference data via HTTP lookups against the reference-data store (species/states/presentations, case types, landing status, devolved administration).
3. Resolve / create the **exporter** (account + contact) in Dynamics 365.
4. Create or update the **document** and create the **case** in Dynamics 365 (including the document-level void status where applicable).
5. **Publish a versioned hand-off envelope** — including the newly created `documentId` and `caseId` plus the original payload — to **`document-case-queue`**.
6. **Complete (settle) the source message** on `mmo-ecc-dyn-req-queue` **only after** the hand-off has been published successfully.

### Reliability model

- **Top-level scope** (`Process_Document_Case_And_Handoff`) wraps all business logic, with a dedicated **error-handler scope** (`Handle_Failure`) that runs on `Failed | TimedOut | Aborted`.
- **Message settlement is explicit and ordered:**
  - Success path → publish to `document-case-queue` → **Complete** the source message.
  - Failure path → **Abandon** the source message so Service Bus redelivers it.
- **No custom retry policies.** External calls rely on the connector's built-in default retry plus **Service Bus native redelivery**. After the queue's max delivery count is exhausted, Service Bus automatically dead-letters the message.
- **Idempotency:** the hand-off envelope carries an `idempotencyKey` (`<documentNumber>-<iteration>`) so the downstream stage can safely de-duplicate under at-least-once delivery.

### Observability

Application Insights enhanced telemetry (`Runtime.ApplicationInsightTelemetryVersion: v2`) is enabled. Key actions (document/case create + update, publish, complete, abandon) emit consistent, **PII-free** `trackedProperties`: `correlationId`, `documentNumber`, `stage`, and an entity/message action descriptor. The `documentId` / `caseId` are included where they are available.

---

## `document-case-queue` (new inter-stage queue)

The hand-off contract between Stage 1 and the downstream landings/catches stage.

### Queue configuration (infrastructure — to be provisioned separately)

| Setting | Value |
|---------|-------|
| Name | `document-case-queue` |
| Sessions | **Enabled** |
| Session id | `documentNumber` (preserves per-document ordering downstream) |
| Max delivery count | `5` (Service Bus dead-letters after this) |
| Delivery | Peek-lock |

> This queue is **documented here but not provisioned by this repository.** It must be created in the Service Bus namespace via the infrastructure pipeline before the stage can run in a deployed environment.

### Message envelope (`ContentData`)

The message body is the UTF-8 JSON string below, base64-encoded into `ContentData`, with `ContentType: application/json`:

```json
{
  "schemaVersion": "1.0",
  "messageType": "DocumentCaseCreated",
  "stage": "document-case-creation",
  "correlationId": "<correlation id propagated from the source message>",
  "documentNumber": "<FES document number>",
  "idempotencyKey": "<documentNumber>-<iteration>",
  "documentId": "<Dynamics 365 document record id>",
  "caseId": "<Dynamics 365 case record id>",
  "payload": { "...": "the original transformed ECC payload" }
}
```

### Brokered message properties

| Field | Value |
|-------|-------|
| `SessionId` | `documentNumber` |
| `CorrelationId` | propagated correlation id |
| `Properties.correlationId` | propagated correlation id |
| `Properties.documentNumber` | FES document number |
| `Properties.stage` | `document-case-creation` |
| `Properties.messageType` | `DocumentCaseCreated` |

---

## Managed API connections

All connections authenticate via **Managed Service Identity (MSI)** — no embedded credentials or keys.

| Connection | API | Used by | Purpose |
|------------|-----|---------|---------|
| `commondataservice` | Dataverse | both processors | Read/write Dynamics 365 entities (accounts, contacts, documents, cases). |
| `servicebus` | Azure Service Bus (audience `https://servicebus.azure.net`) | both processors | Receive from `mmo-ecc-dyn-req-queue`; Stage 1 also sends to `document-case-queue`. |
| `refDataTable` | Azure Table Storage | refdata workflow | Upsert reference-data rows. |

### Least-privilege roles for the new app

| Resource | Role |
|----------|------|
| `mmo-ecc-dyn-req-queue` | Azure Service Bus Data Receiver |
| `document-case-queue` | Azure Service Bus Data Sender |
| Dataverse (Dynamics 365) | App user with the required entity privileges |

Reference data is read over plain HTTPS against `@{parameters('BlobStorage')}/mmorefdata` (audience `https://storage.azure.com`), so the new app needs only the `commondataservice` and `servicebus` connections.

## Parameters

| Parameter | Source | Usage |
|-----------|--------|-------|
| `HostUrl` | `@appsetting('ORG_NAME')` | Dynamics 365 organisation URL for Dataverse API calls. |
| `BlobStorage` | `@appsetting('STORAGEACCOUNT_URL')` | Storage account URL for reference-data lookups / Table Storage upserts. |

## Runtime

- Extension bundle: `Microsoft.Azure.Functions.ExtensionBundle.Workflows` `[1.*, 2.0.0)`
- Functions worker runtime: `node`
- App kind: `workflowapp`
- Local storage: Azurite (`UseDevelopmentStorage=true`)

## Declared behaviour changes vs. the baseline

The new Stage 1 app preserves the documented behaviour of the monolith for the document/case portion of the journey, with these **intentional** differences (the work is moved, not dropped):

1. **Landings/products upserts and landing-row voiding are deferred** to the downstream stage that consumes `document-case-queue`. Stage 1 still applies the **document-level** void status. (Affects `E2E-07` / `E2E-08`, which are now validated across two stages.)
2. **`Update_Document_Process_Status` (Processed) is not set in Stage 1.** The document remains in `Processing`; the final stage is responsible for marking it `Processed`.
3. **Reference-data retries** rely on the connector default plus Service Bus redelivery instead of an explicit exponential retry policy. (`RD-07` is now satisfied by redelivery / dead-lettering.)
4. **Max delivery count of 5** governs redelivery before dead-lettering.

## CI/CD

The pipeline in `workflowDeployment.yaml` extends the `DEFRA/eutd-mmo-fes-pipeline-common` template (`/includes/workflow-deployment.yaml`) and discovers logic-app folders automatically, so the new `mmo-fes-processor-document-case-creation/` folder is picked up without changes to the pipeline file. Triggers on `main`, `develop`, `hotfix/*`, and `feature/*` branches.

## Repository structure

```
eutd-mmo-fes-logic-apps/
├── mmo-ecc-dyn-processor-workflow/                     # Monolith (baseline, unmodified)
├── mmo-fes-processor-document-case-creation/           # Stage 1: document + case creation
│   ├── host.json
│   ├── connections.json                                # commondataservice + servicebus (MSI)
│   ├── parameters.json                                 # HostUrl, BlobStorage
│   ├── local.settings.json
│   └── mmo-fes-processor-document-case-creation_workflow/
│       └── workflow.json
├── mmo-ecc-dyn-processor-refdata-workflow/             # Monthly reference-data sync
├── docs/
│   └── mmo-ecc-dyn-processor-workflow-functional-spec.md   # Regression baseline
├── workflowDeployment.yaml
└── README.md
```