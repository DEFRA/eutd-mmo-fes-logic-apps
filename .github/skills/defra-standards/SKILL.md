---
name: defra-standards
description: 'Defra software development standards for MMO FES Azure Logic Apps (Standard) workflows. Use when writing, reviewing, or refactoring workflow.json, connections.json, parameters.json, or host.json, or when checking compliance, security, PII handling, error handling, observability, deployment, or licensing on a Defra Logic Apps integration.'
license: OGL-UK-3.0
metadata:
  author: mmo-fes
  version: "1.0"
---

# Defra Standards — Logic Apps

This skill summarises the [Defra software development standards](https://github.com/DEFRA/software-development-standards) as they apply to Azure Logic Apps (Standard) workflows. Defra's published standards are the single source of truth; this skill encodes how they apply to workflow definitions, connections, and parameters — it does not replace them.

Logic Apps workflows are declarative JSON, not application code, so **not every Node.js standard applies**. There are no unit-test coverage tiers, container base-image rules, or `joi` validation requirements for workflows. Apply the standards below.

## Secrets and authentication (mandatory)

- **Managed Identity only.** Every managed API connection (`commondataservice`, `servicebus`, `refDataTable`) must authenticate via `ManagedServiceIdentity`. Never embed API keys, connection strings, SAS tokens, passwords, or client secrets in `connections.json`, `parameters.json`, or a committed `local.settings.json`.
- Set the correct MSI `audience` per service — Service Bus `https://servicebus.azure.net`, Azure Storage `https://storage.azure.com`, Dataverse the organisation URL.
- Real secrets and app settings belong in Azure (App Settings / Key Vault references) and in a local, git-ignored `local.settings.json` — never in source control. Confirm `local.settings.json` is excluded via `.funcignore` and `.copilotignore`.

## PII and run history

- **Never expose PII** (exporter names, addresses, emails, phone numbers, contact IDs, vessel owner details) in `trackedProperties`, `clientTrackingId`, action names, or any custom logging. Run history and tracked properties are retained and queryable — treat them as logs.
- Do not add actions that write raw trigger payloads or Dataverse records to logs, storage, or external endpoints for debugging. Redact or reference by non-personal identifier.
- Use correlation/tracking identifiers that are not personal data.

## Parameterisation and configuration

- Environment-specific values (`HostUrl` / `ORG_NAME`, storage URLs / `STORAGEACCOUNT_URL`, subscription IDs, resource group names) must come from `parameters.json` backed by `@appsetting()` — never hardcoded in `workflow.json`.
- Connection runtime URLs must be parameterised, not literal per-environment strings.

## Error handling and retries

- Give critical action chains explicit error handling: `Scope` blocks with failure branches, or `runAfter` conditions including `Failed` / `TimedOut`.
- Configure retry policies on actions that call external services (Dataverse, Service Bus, HTTP) — set a sensible `retryPolicy` rather than relying on defaults for non-idempotent operations.
- For Service Bus peek-lock triggers, complete or abandon messages correctly on success and failure so messages are not silently lost or endlessly re-delivered.

## Observability

- Propagate a correlation/tracking ID end-to-end (`clientTrackingId`) so a run can be traced across workflows and downstream systems — using non-PII values.
- Give actions descriptive names that reflect their purpose to make run history readable.

## Least-privilege connectors

- Grant each connection only the permissions it needs. Do not reuse an over-scoped identity or a broad connection where a narrower one suffices.
- Remove unused connections and parameters (dead configuration).

## Version control and deployment

- Branch `<type>/<brief-description>`; use Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`); `main` is always shippable.
- Deploy only via the approved pipeline (`workflowDeployment.yaml`, extending `DEFRA/eutd-mmo-fes-pipeline-common`). Do not hand-deploy workflows to shared environments.
- Validate the workflow in the VS Code Logic Apps designer / CLI before raising a PR.

## Licence and tooling

- All configuration is published under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) unless an approved exception exists.
- Only [Defra-approved MCP servers](https://defra.github.io/defra-ai-sdlc/pages/appendix/defra-mcp-guidance/) may be enabled.

## References

- [Defra software development standards](https://github.com/DEFRA/software-development-standards)
- [Defra security standards](https://github.com/DEFRA/software-development-standards/blob/main/docs/standards/security_standards.md)
- [Defra logging standards](https://github.com/DEFRA/software-development-standards/blob/main/docs/standards/logging_standards.md)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
- [Defra approved MCP servers](https://defra.github.io/defra-ai-sdlc/pages/appendix/defra-mcp-guidance/)
