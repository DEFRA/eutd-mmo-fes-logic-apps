---
name: harden-workflow
description: 'Repeatable procedure to retrofit error handling, retry policies, Service Bus message settlement, idempotency, and Application Insights telemetry into an existing Azure Logic Apps (Standard) workflow. Use when: adding error handling, fixing silent retries/partial writes, adding retry policies, settling Service Bus messages, removing race conditions, or adding clean logging to a workflow.'
---

# Skill: Harden Workflow (Error Handling + Observability Retrofit)

Make an existing Logic Apps (Standard) workflow reliable, idempotent, and observable — without changing its documented functional behaviour.

## When to Use

- Adding error handling and message settlement to a workflow that currently relies on lock timeout.
- Eliminating partial-write / silent-retry risks.
- Adding retry policies, pagination, and removing concurrency race conditions.
- Adding clean, correlated Application Insights telemetry.

## Prerequisites

- Read `logic-apps-error-handling.instructions.md` and `logic-apps-observability.instructions.md`.
- Keep `docs/mmo-ecc-dyn-processor-workflow-functional-spec.md` open as the regression baseline (see its §14 Identified Issues & Risks for the concrete defects to fix).

## Procedure

### 1. Map the current failure surface

1. Identify the trigger settlement model and every action that writes to Dataverse/Storage.
2. List actions with no failure path, no retry policy, or shared-variable mutation inside concurrent loops.
3. Cross-reference the spec's §14 risk findings.

### 2. Introduce scopes and a failure path

1. Wrap the main business logic in one or more `Scope` actions.
2. Add a dedicated **error-handler scope** with `runAfter: ["Failed", "TimedOut", "Aborted"]`.
3. In the handler, capture context with `@result('<MainScope>')`, filter to `status == 'Failed'`, and surface failed action name + error.

### 3. Make message settlement explicit

1. **Success path** → Complete the message.
2. **Transient failure** (429/5xx/timeout) → Abandon (immediate redelivery, no lock-timeout wait).
3. **Poison / validation failure** → Dead-letter with `reason` + `description`.
4. Always pass `lockToken` and `sessionId`. Never depend on lock expiry.

### 4. Add retry policies

1. Add explicit `exponential` retry policies to all Dataverse and HTTP actions (Dataverse throttles under concurrent loops).
2. Use `type: "none"` only for non-idempotent operations where retry would duplicate.

### 5. Enforce idempotency

1. Guard creates with natural-key existence checks; prefer upserts.
2. Re-evaluate "skip if exists" branches — update when the message may carry newer data.
3. Confirm safe behaviour under resubmission and concurrent runs.

### 6. Remove concurrency anti-patterns

1. For any `Foreach` that mutates shared variables: set concurrency to `1`, or refactor to per-iteration `Compose`/`items()`.
2. Resolve shared ids (e.g. case id) **before** concurrent loops to avoid duplicate creation.
3. Change id-capture actions from `runAfter: ["Succeeded","Failed"]` to `["Succeeded"]` so failures don't set null ids.

### 7. Fix pagination and hardcoded values

1. Add `$top` and `paginationPolicy.minimumItemCount` to queries that can exceed page size.
2. Move hardcoded GUIDs / fallback ids / environment values to `@appsetting()` / `parameters()`.

### 8. Add clean, correlated telemetry

1. Set the trigger **Custom Tracking Id** from `_correlationId`.
2. Add `trackedProperties` (`correlationId`, `documentNumber`, `caseType`, `stage`, `messageAction`, `outcome`) on stage boundaries, decision points, and the error handler.
3. Ensure **no PII or secrets** in telemetry; keep tracked properties off secure actions.

### 9. Validate

- [ ] Every main scope has a failure path that settles the message.
- [ ] Transient vs poison failures handled distinctly (abandon vs dead-letter).
- [ ] Retry policies on all external calls.
- [ ] No shared-variable mutation in concurrent loops; ids captured on success only.
- [ ] Pagination set; no hardcoded environment values.
- [ ] Correlated telemetry present, PII/secret-free.
- [ ] `workflow.json` valid JSON; `runAfter` graph valid; behaviour matches spec.

## Completion Checklist Output

Summarise: risks addressed (map to spec §14 numbers), settlement model, retry coverage, idempotency changes, telemetry added, and confirmation of behavioural parity.
