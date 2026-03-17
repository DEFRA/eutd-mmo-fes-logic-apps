# MMO FES Logic Apps

UK Government (DEFRA/MMO) fisheries export service integration workflows. Azure Logic Apps (Standard) that process export certificate data via Dynamics 365 (Dataverse) and synchronise reference data to Azure Table Storage.

## Architecture

| Component | Role |
|-----------|------|
| `mmo-ecc-dyn-processor-workflow` | Service Bus–triggered workflow: reads ECC messages, creates/retrieves exporter records in Dynamics 365, maps catch certificate data, and writes processed records back |
| `mmo-ecc-dyn-processor-refdata-workflow` | Recurrence-triggered workflow (monthly): pulls reference data (species, states, presentations, case types, landing statuses, devolved administrations) from Dynamics 365 and upserts into Azure Table Storage |

## Project Structure

```
eutd-mmo-fes-logic-apps/
├── mmo-ecc-dyn-processor-workflow/          # ECC Dynamics processor
│   ├── host.json                            # Runtime config + extension bundle
│   ├── connections.json                     # Managed API connections
│   ├── parameters.json                      # Workflow parameters (HostUrl, BlobStorage)
│   ├── local.settings.json                  # Local dev app settings
│   ├── .funcignore
│   └── mmo-ecc-dyn-processor_workflow/
│       └── workflow.json                    # Workflow definition
├── mmo-ecc-dyn-processor-refdata-workflow/  # Reference data sync
│   ├── host.json
│   ├── connections.json
│   ├── parameters.json
│   ├── local.settings.json
│   ├── .funcignore
│   └── mmo-ecc-dyn-processor-refdata_workflow/
│       └── workflow.json
├── workflowDeployment.yaml                  # Azure DevOps CI/CD pipeline
└── README.md
```

## Managed API Connections

All connections authenticate via **Managed Service Identity (MSI)**.

| Connection | API | Purpose |
|------------|-----|---------|
| `commondataservice` | Dataverse | Read/write Dynamics 365 entities (accounts, contacts, catch certificates) |
| `servicebus` | Azure Service Bus | Receive messages from `mmo-ecc-dyn-req-queue` (peek-lock, session-enabled) |
| `refDataTable` | Azure Table Storage | Upsert reference data rows (species, states, presentations, etc.) |

## Parameters

| Parameter | Source | Usage |
|-----------|--------|-------|
| `HostUrl` | `@appsetting('ORG_NAME')` | Dynamics 365 organisation URL for Dataverse API calls |
| `BlobStorage` | `@appsetting('STORAGEACCOUNT_URL')` | Azure Storage account URL for Table Storage upserts |

## Runtime

- Extension bundle: `Microsoft.Azure.Functions.ExtensionBundle.Workflows` v1.x
- Functions worker runtime: `node`
- App kind: `workflowapp`
- Local storage: Azurite (`UseDevelopmentStorage=true`)

## CI/CD

Pipeline in `workflowDeployment.yaml` extends `DEFRA/eutd-mmo-fes-pipeline-common` template (`/includes/workflow-deployment.yaml`). Triggers on `main`, `develop`, `hotfix/*`, `feature/*` branches.

## Skills

Use `/develop` for implementing, modifying, or researching Logic Apps workflows. Use `/review` for reviewing workflow definitions and connections.
