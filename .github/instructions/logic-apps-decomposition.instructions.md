---
description: 'Azure Logic Apps (Standard) workflow decomposition and Service Bus messaging-contract standards. Enforces the routing-slip pattern, queue conventions, message envelopes, and per-app isolation when splitting MMO FES workflows across logic apps.'
applyTo: '**/workflow.json, **/connections.json, **/parameters.json, **/host.json'
---

# Logic Apps Decomposition & Service Bus Contract Standards

Standards for splitting large MMO FES workflows into multiple smaller workflows hosted on **separate logic apps**, connected asynchronously by Azure Service Bus queues.

> Grounded in Microsoft guidance: [Fixed routing slip pattern / Multi-region message patterns](https://learn.microsoft.com/azure/logic-apps/multi-region-disaster-recovery#logic-app-state-and-history) and [BizTalk → Logic Apps Standard (peek-lock, idempotency)](https://learn.microsoft.com/azure/logic-apps/biztalk-server-migration-overview).

## 1. Decomposition follows the routing-slip pattern

- Split a business process into **smaller, single-responsibility stages**. Each stage is its own workflow, hosted on its own logic app, communicating with the next stage **only** via an asynchronous Service Bus queue.
- Benefits to preserve as design goals: fewer abandoned in-progress instances on failure, fault isolation per stage, independent concurrency/scaling, smaller workflows that are easier to test, resubmit, and reason about.
- **One responsibility per workflow.** A workflow owns a cohesive unit of work (e.g. a single entity group). Do not mix unrelated responsibilities back into one app.
- **No shared mutable state across apps.** Apps coordinate exclusively through messages; never through a shared variable, table row, or implicit ordering assumption.

## 2. Functional parity is non-negotiable

- The split must reproduce the behaviour captured in `docs/mmo-ecc-dyn-processor-workflow-functional-spec.md`. That document is the **regression baseline** — every scenario (T-, P-, V-, RD-, EX-, D-, CP-, L-, MC-, E2E-) must still pass end to end after decomposition.
- When moving actions between workflows, preserve the same conditions, mappings, and outcomes. Record any intended behaviour change explicitly; do not let it happen by accident.

## 3. Service Bus queue conventions (new queues)

- Provision **new** queues for inter-stage hand-offs that mirror the existing setup; do not overload the existing ingress queue.
- Naming: lowercase, hyphenated, descriptive of the stage it feeds, consistent with the existing `mmo-ecc-dyn-*-queue` style (the concrete names are decided per design).
- **Sessions**: enable sessions where per-document ordering matters (mirror the current session-enabled ingress behaviour). Use a stable session id (e.g. document number) so related messages process in order.
- **Peek-lock** receive on every trigger; settle explicitly (see error-handling instructions).
- Configure **max delivery count** and a reachable **dead-letter queue**; set message **TTL** appropriate to the stage.
- Set explicit trigger **concurrency** per stage — never leave it unbounded.

## 4. Message envelope / contract

- Every inter-stage message uses a **versioned, explicit envelope**. Minimum fields:
  - `schemaVersion` — contract version for forward/backward compatibility.
  - `correlationId` — propagated from ingress for end-to-end tracing (see observability instructions).
  - `documentNumber` — business key.
  - `stage` / `messageType` — what this message represents.
  - `idempotencyKey` — natural key enabling safe at-least-once processing downstream.
  - `payload` — the stage's data (or a claim-check reference, see below).
- Keep messages within Service Bus size limits. For large payloads use the **claim-check pattern**: write the payload to blob storage and pass a reference in the message rather than embedding it.
- Treat the envelope as a **published contract**: additive, versioned changes only; never silently break a field a downstream stage relies on.

## 5. Per-app project structure

Each split logic app is a self-contained folder mirroring the existing layout:

```
mmo-ecc-dyn-<stage>-workflow/
├── host.json              # Runtime + extension bundle + telemetry config
├── connections.json       # Managed API connections for THIS app only
├── parameters.json        # Parameters for THIS app only
├── local.settings.json    # Local settings (excluded via .funcignore)
├── .funcignore
└── mmo-ecc-dyn-<stage>_workflow/
    └── workflow.json
```

- Each app declares only the connections it actually uses — no dead connections carried over from the monolith.
- Update `workflowDeployment.yaml` so each new logic app is built and deployed.

## 6. Security & least privilege

- All Service Bus, Dataverse, and Storage connections use **`ManagedServiceIdentity`** — never embedded credentials. Service Bus connections set `connectionProperties.authentication.audience` to `https://servicebus.azure.net`.
- Grant each logic app's managed identity **least-privilege, queue-scoped** roles: `Azure Service Bus Data Receiver` on the queue it consumes, `Azure Service Bus Data Sender` on the queue it publishes to — not blanket namespace access.
- All environment-specific values via `@appsetting()` / `parameters()`; nothing hardcoded.

## Do Not

- Re-merge responsibilities back into a single oversized workflow.
- Share state between apps through anything other than the message contract.
- Reuse the ingress queue for inter-stage hand-offs.
- Embed credentials or grant namespace-wide Service Bus access.
- Change documented functional behaviour as an undeclared side effect of splitting.
