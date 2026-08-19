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

## Standards precedence (highest wins)

When guidance conflicts, follow this order:

1. **DEFRA Software Development Standards** (mandatory) — https://defra.github.io/software-development-standards/
2. **DEFRA Digital Service Manual** — https://digital.defra.gov.uk/service-manual
3. **GOV.UK Service Standard & Service Manual (GDS)** — https://www.gov.uk/service-manual
4. **Community best practice** — [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/), [12-factor](https://12factor.net/), widely-adopted Azure Logic Apps patterns

> **DEFRA takes precedence over GDS. GDS takes precedence over community guidance.** Any deviation from a DEFRA standard MUST be raised as a formal exception through DEFRA's architectural governance (Delivery Architecture team: `delivery.architecture@defra.gov.uk`).

## The working framework (Triage → Read → Research → Clarify → Plan → Approval → Implement → Test → Iterate → Summarise)

This section is the **single source of truth** for the working loop. The custom agents ([Orchestrator](.github/agents/logic-apps-orchestrator.agent.md), [Planner](.github/agents/logic-apps-planner.agent.md), [Developer](.github/agents/logic-apps-developer.agent.md) and [Reviewer](.github/agents/logic-apps-reviewer.agent.md)) reference it and **must not restate or fork it**. The guiding principle is **match effort to risk**: do the least work that still delivers the change safely and to standard.

Logic Apps are **declarative JSON workflow definitions** — there are no unit tests, coverage tiers, or compiled artefacts. "Implement" means authoring or modifying `workflow.json`, `connections.json`, and `parameters.json`. "Test / Validate" means confirming JSON is structurally valid, the `runAfter` DAG is correct, and the approved deployment pipeline passes.

**Triage first — pick one of three gears by size and risk:**

- **Trivial** (renaming an action, updating a static string parameter, adding a log message, fixing a typo in an expression): skip the planner, research and review. Do a light **Read → Implement → Validate → Summarise**, and research only the one point that is genuinely uncertain.
- **Standard** (a normal action/expression change or parameter update with **no** new connector, MSI scope, or security surface): use a **lightweight inline plan** (a short Objective · Plan · Files · Validation · Risks note from the Developer agent — no heavyweight Planner), get approval, then implement and validate. Run a **single** risk-scoped research pass **only if** something is genuinely uncertain.
- **Complex** (new workflow or trigger, new connector or managed connection, new managed identity scope, error-handling branch, retry policy change, parameterisation change, a security/MSI change, or anything affecting data correctness or the deployment pipeline): run the full loop with the Planner agent below.

**Manual override.** The user can force a gear — e.g. "treat this as trivial", "just a lightweight/standard plan", "force the full plan", "skip the planner" — and that instruction wins over the automatic classification. Always honour a request for **more** rigour. When the user asks for **less** rigour than the risk warrants, comply but **briefly flag the risk first**, and never drop the approval gate or security for a change that genuinely touches connectors, MSI scope, error handling or the deployment pipeline.

The loop (Standard and Complex; Trivial uses the light path above):

1. **Read** — Read the relevant `workflow.json`, `connections.json`, `parameters.json`, and `host.json` before acting. Map the `runAfter` dependency graph. Never assume; verify.
2. **Research (single pass, risk-scoped)** — When something is genuinely uncertain — an unfamiliar connector, MSI scope, expression syntax, or DEFRA/GDS policy — do **one** thorough, risk-scoped research pass in the open and validate findings against DEFRA/GDS and Azure Logic Apps guidance. Cite sources. **Do not run a second, separate validation research round** — the plan is checked against these same cited sources.
3. **Clarify** — Ask the user targeted questions whenever requirements are ambiguous or missing. Do not guess at intent.
4. **Plan** — For **Complex** work, delegate planning to the [Planner - Logic Apps](.github/agents/logic-apps-planner.agent.md) agent, which returns a complete plan with its research already cited. For **Standard** work, produce the lightweight inline plan directly — no separate planning agent. Either way, **check** the plan's risky steps are covered and cited; only send a targeted revision back if a genuine gap is found.
5. **Approval** — Present the plan to the user and obtain explicit approval before implementation. **Cap the plan → approve → implement cycle at 3 iterations**.
6. **Implement** — Deliver one task at a time from the approved plan. Author or modify `workflow.json`, `connections.json`, and `parameters.json`. When a significant design decision is made, capture it as an ADR and update docs **where the repo already keeps them**.
7. **Test / Validate** — Validate JSON structure → verify `runAfter` DAG integrity → confirm no secrets in committed files → confirm the approved deployment pipeline passes. No `npm test` step.
8. **Iterate** — Refine until the user is satisfied.
9. **Summarise** — End with a detailed **executive summary** of what changed, why, how it was validated, and any follow-ups or risks.

**Code review is optional and on-request.** A full code review is **not** part of the default loop. Run it only when the user asks for one. At the end of implementation, if no review has been run, **offer** one (a single Yes/No question); invoke the reviewer only on an explicit Yes.

## Workflow agents

Standard and Complex work is coordinated through four custom agents that all run the framework above:

| Agent | Role |
|-------|------|
| [Orchestrator - Logic Apps](.github/agents/logic-apps-orchestrator.agent.md) | Plans, delegates, verifies and reports; owns the Yes/No user-approval gate and the end-of-work review offer. Does **not** implement. |
| [Planner - Logic Apps](.github/agents/logic-apps-planner.agent.md) | Internal planning subagent; produces the approval-ready plan and the single research pass behind it. Invoked for **Complex** work. |
| [Developer - Logic Apps](.github/agents/logic-apps-developer.agent.md) | Implements an already-approved plan end-to-end: workflow JSON authoring, connector configuration, parameterisation; authors the lightweight inline plan for **Standard** work. |
| [Reviewer - Logic Apps](.github/agents/logic-apps-reviewer.agent.md) | Read-only review against DEFRA standards and workflow best practices; reports findings by severity. **Optional, on-request only** — not run by default. |

Research (§4.2) uses the [deep-research-defra-alignment](.github/skills/deep-research-defra-alignment/SKILL.md) skill — a single risk-scoped pass run by the **Planner** (Complex work) or the **Developer** (Standard work). The [Speckit](.github/agents) agents (`speckit.*`) are a separate spec-driven toolset and are **not** part of this workflow.

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
