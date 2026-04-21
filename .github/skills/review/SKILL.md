---
name: review
description: 'Expert reviewer for Azure Logic Apps (Standard) workflows. Use when: reviewing workflow definitions, auditing connections and parameters, checking security posture, validating error handling, assessing best practice compliance, reviewing VS Code Logic Apps extension configuration.'
---

# Logic Apps — Review Skill

Expert reviewer for Azure Logic Apps (Standard) workflows. Performs read-only analysis of workflow definitions, connections, parameters, and project configuration against security, reliability, and best practice standards.

## When to Use

- Reviewing workflow definitions (`workflow.json`) for correctness
- Auditing managed API connections and authentication
- Checking for hardcoded secrets or environment-specific values
- Validating error handling and retry patterns
- Assessing workflow performance (concurrency, pagination, throttling)
- Reviewing changes before merge or deployment

## Review Procedure

### 1. Structural Validation

- Verify `workflow.json` uses schema `https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#`
- Map the `runAfter` dependency graph — check for orphaned actions, circular references, or missing predecessors
- Confirm every variable is initialised before use (`InitializeVariable` action precedes `SetVariable`)
- Verify `foreach` loops do not concurrently mutate shared variables

### 2. Connection & Parameter Audit

- Cross-reference `workflow.json` connection references against `connections.json` keys
- Verify all connections use `ManagedServiceIdentity` authentication
- Check `connectionProperties.authentication.audience` is correct for each service:
  - Service Bus: `https://servicebus.azure.net`
  - Azure Storage: `https://storage.azure.com`
- Verify `parameters.json` entries use `@appsetting()` references (not hardcoded values)
- Confirm `local.settings.json` is listed in `.funcignore`

### 3. Security Review

| Check | Expected |
|-------|----------|
| Authentication type | `ManagedServiceIdentity` on all connections |
| No embedded credentials | No API keys, connection strings, or passwords in JSON files |
| Parameterised references | Subscription ID, resource group, org name via `@appsetting()` |
| Sensitive settings | Only in `local.settings.json` (excluded from source control) |
| HTTP action auth | MSI with correct audience scope on all HTTP actions |

### 4. Error Handling Review

- Check that critical action chains have error-handling branches
- Verify `Scope` blocks are used to group related actions with shared error handling
- Confirm Service Bus peek-lock triggers have proper message completion/abandonment on failure
- Check that HTTP actions have appropriate timeout and retry policies

### 5. Performance Review

| Setting | Guideline |
|---------|-----------|
| Trigger concurrency (`runs`) | Set explicitly — avoid unlimited (default) for Service Bus |
| Polling interval | Appropriate for the use case (30s for Service Bus, less frequent for reference data) |
| Pagination (`minimumItemCount`) | Set for Dataverse queries that may exceed default page size |
| Foreach concurrency | Limited when actions have side effects or ordering matters |

### 6. VS Code Extension Configuration Review

- `host.json` extension bundle version: `Microsoft.Azure.Functions.ExtensionBundle.Workflows` v1.x–2.x
- `local.settings.json` has `APP_KIND: workflowapp` and `FUNCTIONS_WORKER_RUNTIME: node`
- `.funcignore` excludes development-only files
- `ProjectDirectoryPath` in `local.settings.json` points to valid local path

## Output Format

Present findings as a Markdown table sorted by severity:

| File | Action/Section | Issue | Severity | Recommendation |
|------|---------------|-------|----------|----------------|

Severity levels:
1. **Critical** — Security or data integrity risk (credential exposure, missing auth, broken dependencies)
2. **High** — Reliability risk (missing error handling, hardcoded values, invalid references)
3. **Medium** — Maintainability concern (naming, pagination, concurrency settings)
4. **Low** — Documentation or cosmetic improvement
