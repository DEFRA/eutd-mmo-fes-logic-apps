---
description: 'Azure Logic Apps Standard workflow definition rules. Enforces correct JSON structure, connector patterns, expression syntax, and parameterisation for workflow.json files.'
applyTo: '**/workflow.json'
---

# Logic Apps Workflow Rules

Rules for editing `workflow.json` workflow definitions in Azure Logic Apps (Standard) projects.

## Mandatory Rules

- Always use the Logic Apps schema: `https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#`
- Never hardcode environment-specific values (subscription IDs, resource group names, connection strings) — use `@appsetting()` or `parameters()` references
- All managed API connections must use `ManagedServiceIdentity` authentication — never embed credentials
- Every action must declare `runAfter` dependencies (except the first action after a trigger)
- Use `@{encodeURIComponent(encodeURIComponent(...))}` for Dataverse table/entity path segments
- Scope actions logically — use `Scope` type for groupable operations with shared error handling
- Set `concurrency.runs` on triggers to control parallelism (currently 10 for Service Bus)
- Use `paginationPolicy.minimumItemCount` for Dataverse queries that may return large datasets (e.g., species)

## Expression Syntax

```
@variables('VariableName')             — read variable
@body('ActionName')?['property']       — read action output safely
@items('ForEachName')?['property']     — read current item in foreach
@parameters('ParamName')               — read workflow parameter
@appsetting('SETTING_NAME')            — read app setting
@null / @true / @false                 — literal values
@empty(collection)                     — check if collection is empty
```

## Connection References

```json
{
  "host": {
    "connection": {
      "referenceName": "connectionName"
    }
  }
}
```

Connection names must match keys in the sibling `connections.json` file.

## Error Handling

- Use `runAfter` with `["Failed"]` or `["Failed", "TimedOut"]` to build error-handling branches
- Wrap related actions in `Scope` blocks and add error scopes that run after failure
- Never leave actions without error handling in production workflows

## Do Not

- Add comments to `workflow.json` — JSON does not support comments
- Duplicate logic across workflows — extract shared patterns to reusable sub-workflows where possible
- Change trigger recurrence intervals without discussing impact on API throttling and costs
- Remove or rename existing actions without checking downstream `runAfter` dependencies
