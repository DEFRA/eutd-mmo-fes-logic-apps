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

## Defra standards and governance

This service must comply with [Defra software development standards](https://github.com/DEFRA/software-development-standards) — the single source of truth. The rules below encode those standards as they apply to Azure Logic Apps (Standard) workflows; they do not replace them. Logic Apps are declarative JSON, not application code, so there are **no unit-test coverage tiers, container base-image rules, or `joi`/Hapi requirements** here. When a standard changes, update this file.

### Quality gates

Before a workflow change is merged:

- `workflow.json`, `connections.json`, and `parameters.json` are valid JSON and the workflow renders in the VS Code Logic Apps designer / validates via CLI
- `runAfter` dependencies form a valid DAG; connection and parameter references resolve
- All connections use `ManagedServiceIdentity`; no secrets, keys, or connection strings committed
- Error handling and retry policies are present on external calls
- The approved deployment pipeline (`workflowDeployment.yaml`) succeeds
- At least one approving review from another developer

### Security and PII

- Every managed connection authenticates via `ManagedServiceIdentity` with the correct audience scope (Service Bus `https://servicebus.azure.net`, Storage `https://storage.azure.com`, Dataverse the org URL); grant least-privilege identities
- Never commit secrets, keys, connection strings, or SAS tokens in `connections.json`, `parameters.json`, `host.json`, or `local.settings.json` — real values live in Azure App Settings / Key Vault and a git-ignored `local.settings.json` (excluded via `.funcignore` and `.copilotignore`)
- **Never expose PII** (exporter names, addresses, emails, phone numbers, contact IDs, bank details) in run history, `trackedProperties`, `clientTrackingId`, action names, or debug actions
- Validate and normalise all trigger inputs (Service Bus messages, HTTP bodies, Dataverse records); fail safely (abandon/dead-letter malformed messages)
- Follow [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)

### Parameterisation and configuration

- Environment-specific values (`HostUrl`/`ORG_NAME`, storage URLs/`STORAGEACCOUNT_URL`, subscription IDs, resource groups) come from `parameters.json` backed by `@appsetting()` — never hardcoded in `workflow.json`
- Connection runtime URLs are parameterised, not literal per-environment strings; remove unused connections and parameters

### Observability

- Propagate a non-PII correlation/tracking ID (`clientTrackingId`) end-to-end so runs are traceable across workflows and downstream systems
- Give actions descriptive names that reflect their purpose to keep run history readable

### How Copilot should respond

- Follow conventions already in the workflows and connections — check existing patterns first
- Prefer modifying existing workflow definitions over creating new ones when the change fits naturally
- Provide minimal diffs touching only the necessary files; do not refactor unrelated actions
- Only use [Defra-approved MCP servers](https://defra.github.io/defra-ai-sdlc/pages/appendix/defra-mcp-guidance/)
- If a request conflicts with these instructions — a committed secret, a non-MSI connection, PII in run history, a missing error branch, or a broken quality gate — flag it explicitly and do not proceed silently

### Licence

All configuration is published under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) unless an approved exception exists.

<!-- STANDARDS NOTE: These instructions reflect Defra software development standards (https://github.com/DEFRA/software-development-standards). Review this file periodically or after any Defra standards update. -->
