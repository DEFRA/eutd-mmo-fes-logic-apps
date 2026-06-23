---
name: split-workflow
description: 'Repeatable procedure to split a large Azure Logic Apps (Standard) workflow into smaller workflows on separate logic apps connected by Service Bus queues. Use when: decomposing a monolithic workflow, extracting a stage into its own logic app, applying the routing-slip pattern, provisioning a new inter-stage queue, or designing the message contract between split workflows.'
---

# Skill: Split Workflow (Routing-Slip Decomposition)

Extract a stage from a monolithic Logic Apps (Standard) workflow into its own logic app, connected to the rest of the process by a new Service Bus queue — without changing documented behaviour.

## When to Use

- Breaking the ECC Dynamics Processor into independently deployable stages.
- Extracting a cohesive unit of work (e.g. a single entity group) into a new logic app.
- Adding a new inter-stage Service Bus queue and message contract.

## Prerequisites

- Read the decomposition & Service Bus contract standards: `logic-apps-decomposition.instructions.md`.
- Have the functional spec open as the regression baseline: `docs/mmo-ecc-dyn-processor-workflow-functional-spec.md`.
- Confirm the target split (stage boundaries, logic app names, queue names, session requirements) before editing — these are design decisions.

## Procedure

### 1. Define the stage boundary

1. Identify the cohesive set of actions to extract and the exact point in the upstream workflow where the hand-off occurs.
2. List every variable/value the extracted stage consumes — these become the **message contract** fields.
3. Confirm the stage has a single responsibility and no hidden dependency on shared variables that won't cross the queue boundary.

### 2. Design the message contract

1. Define the versioned envelope: `schemaVersion`, `correlationId`, `documentNumber`, `stage`/`messageType`, `idempotencyKey`, `payload`.
2. If the payload may be large, use the **claim-check** pattern (blob reference) instead of embedding it.
3. Document the contract so both producer and consumer agree on it.

### 3. Provision the new queue

1. Choose a name consistent with `mmo-ecc-dyn-*-queue`.
2. Decide **session-enabled** (yes if per-document ordering matters; use document number as session id).
3. Configure peek-lock, max delivery count, dead-letter queue, and TTL.

### 4. Add the publish step to the upstream workflow

1. At the hand-off point, add a Service Bus **send message** action that emits the envelope.
2. Propagate correlation: set `x-ms-client-tracking-id` / `correlationId` so the trace continues downstream.
3. Add `trackedProperties` (`correlationId`, `documentNumber`, `stage`, `messageAction`) per the observability standards.
4. Ensure the upstream message is only settled after the hand-off publish succeeds (no lost work on failure).

### 5. Scaffold the new logic app

Create the self-contained folder structure (mirror the existing apps):

```
mmo-ecc-dyn-<stage>-workflow/
├── host.json
├── connections.json        # only the connections THIS app uses (MSI auth)
├── parameters.json         # only THIS app's parameters
├── local.settings.json     # excluded via .funcignore
├── .funcignore
└── mmo-ecc-dyn-<stage>_workflow/
    └── workflow.json
```

### 6. Build the new workflow

1. Add a Service Bus **peek-lock** trigger on the new queue (session-enabled if chosen); set explicit concurrency.
2. Set the **Custom Tracking Id** from the inbound `correlationId`.
3. Move the extracted actions in; preserve every condition, mapping, and outcome from the baseline.
4. Apply the harden-workflow standards: top-level scope + error-handler scope, explicit settlement (complete/abandon/dead-letter), retry policies, idempotent writes, pagination, no hardcoded values.

### 7. Wire connections, parameters, and deployment

1. Add `connections.json` entries (MSI, queue-scoped audience for Service Bus).
2. Add `parameters.json` entries sourced from `@appsetting()`.
3. Add the new app to `workflowDeployment.yaml` so it builds and deploys.
4. Plan least-privilege role assignments: Data Receiver on the consumed queue, Data Sender on any published queue.

### 8. Validate

- [ ] Producer publishes a valid, versioned envelope with correlation.
- [ ] Consumer trigger, tracking id, concurrency, and sessions configured.
- [ ] All moved actions retain baseline behaviour (walk the relevant spec scenarios).
- [ ] Error-handler scope settles the message correctly on failure.
- [ ] No hardcoded environment values; all connections use MSI.
- [ ] `workflow.json` is valid JSON; `runAfter` graph is a valid DAG.
- [ ] Correlation id flows end-to-end across the split (verify in App Insights).
- [ ] Deployment pipeline updated for the new app.

## Completion Checklist Output

Summarise: stage extracted, new app name, new queue (+ session setting), contract fields, parity scenarios covered, and any declared behaviour changes.
