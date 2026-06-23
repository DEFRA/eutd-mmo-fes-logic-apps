---
description: 'Azure Logic Apps (Standard) error-handling, resiliency, retry, message-settlement, and idempotency standards. Enforces robust failure handling for workflow.json during the optimisation effort.'
applyTo: '**/workflow.json'
---

# Logic Apps Error Handling & Resiliency Standards

Mandatory standards for making MMO FES Logic Apps (Standard) workflows reliable and fault-tolerant.
These rules apply whenever you add, refactor, or review actions in a `workflow.json` definition.

> Grounded in Microsoft guidance: [Handle errors and exceptions in Azure Logic Apps](https://learn.microsoft.com/azure/logic-apps/error-exception-handling), [Group actions into scopes](https://learn.microsoft.com/azure/logic-apps/logic-apps-control-flow-run-steps-group-scopes), and [Reliability in Azure Logic Apps (Standard)](https://learn.microsoft.com/azure/reliability/reliability-logic-apps).

## 1. Every workflow must have an explicit failure path

- **Never** rely on a Service Bus peek-lock simply timing out to trigger a retry. A timed-out lock causes a silent, delayed redelivery and risks partial writes.
- Group the main business logic inside one or more `Scope` actions. Add a **dedicated error-handler scope** that runs after the main scope using `runAfter` with `["Failed", "TimedOut", "Aborted"]`.
- The error-handler scope is responsible for: capturing failure context, emitting telemetry (see observability instructions), and **settling the Service Bus message correctly** (abandon or dead-letter).

```json
{
  "Process_Document": {
    "type": "Scope",
    "actions": { "...": "..." },
    "runAfter": {}
  },
  "Handle_Failure": {
    "type": "Scope",
    "actions": { "...": "..." },
    "runAfter": {
      "Process_Document": ["Failed", "TimedOut", "Aborted"]
    }
  }
}
```

## 2. Capture failure context with `result()`

- In the error-handler scope, use the [`result()` function](https://learn.microsoft.com/azure/logic-apps/workflow-definition-language-functions-reference#result) to read the outcomes of the failed scope's top-level actions: `@result('Process_Document')`.
- Filter to failures only (`status == 'Failed'`) and surface the failed action `name`, `error`, status code, and `clientTrackingId` into telemetry. `result()` returns only top-level actions — nest scopes deliberately if you need deeper context.

## 3. Service Bus message settlement is explicit and deterministic

| Outcome | Settlement action | When |
|---------|-------------------|------|
| Success | **Complete** the message | All processing succeeded |
| Transient failure (429, 5xx, timeout, throttling) | **Abandon** the message | Safe to redeliver immediately; lets the retry happen without waiting for lock timeout |
| Poison / non-transient (malformed payload, missing required fields, schema violation) | **Dead-letter** the message with a `reason` and `description` | Retrying will never succeed — fail fast instead of exhausting all delivery attempts |

- Always pass the message `lockToken` and `sessionId` to settlement actions.
- Dead-letter for validation errors rather than letting the message cycle through all delivery attempts and land in the DLQ with no diagnostic reason.

## 4. Retry policies on every external call

- Connector operations use the **Default** retry policy (exponential, ~4 retries, 7.5s scaling, capped 5–45s) unless overridden. Make retry behaviour **explicit** on all Dataverse (`commondataservice`) and HTTP actions — Dataverse throttles with HTTP 429, especially under concurrent `Foreach` loops.
- Prefer an `exponential` retry policy for idempotent reads/writes. Standard stateful workflows allow intervals from `PT5S` to `P1D`.

```json
"retryPolicy": { "type": "exponential", "count": 5, "interval": "PT7S", "minimumInterval": "PT5S", "maximumInterval": "PT1H" }
```

- Use retry `type: "none"` only where a retry would cause incorrect duplication and the operation is not idempotent.

## 5. Idempotency — assume at-least-once delivery

- Service Bus peek-lock, retries, concurrent runs, and manual resubmission all mean **the same message may be processed more than once**. Design every write to be safe to repeat.
- Use upserts / "check-then-create-or-update" guarded by a natural key (document number, item id, submission number). Treat existing-record checks as **advisory, not atomic** — two concurrent runs can both pass the check.
- Where a record already exists and the message may carry newer values, **update it** rather than silently skipping (the current catches/products path skips existing items — re-evaluate that during hardening).

## 6. Concurrency and shared-variable anti-patterns

- **Do not** mutate workflow-scoped variables (`SetVariable`) inside a `Foreach` that has concurrency > 1 — this causes race conditions. Either:
  - set the loop concurrency to `1` when shared state is mutated, or
  - refactor to use per-iteration `Compose` actions and `items()` instead of shared variables.
- **Do not** capture an entity id with `runAfter: ["Succeeded", "Failed"]`. On failure the id resolves to `null`, producing orphaned records. Capture ids only on `["Succeeded"]`.
- Avoid creating records (e.g. cases) inside concurrent loops where the id is shared — duplicate creation will result. Resolve such ids before the loop.

## 7. Pagination and query limits

- Set `$top` on every Dataverse query, and `paginationPolicy.minimumItemCount` on queries that may exceed the default page size (e.g. all landings for a document). Missing pagination silently truncates results.

## 8. No hardcoded environment values or fallback identifiers

- Never hardcode GUIDs, fallback customer/account ids, subscription ids, resource group names, or connection strings. Move them to `@appsetting()` / `parameters()` so they are environment-specific and survive entity deletion.

## 9. Controlled termination

- Use the `Terminate` action with an explicit status (`Succeeded`/`Failed`) for intentional early exits. Make the reason observable via telemetry — never terminate silently.

## Do Not

- Leave any production action chain without a failure path.
- Add JSON comments (`workflow.json` does not support them) — document rationale in the repo `docs/`.
- Remove or rename actions without re-checking every downstream `runAfter`.
- Introduce non-idempotent writes that duplicate data on retry.
