---
description: 'Azure Logic Apps (Standard) observability and clean-logging standards for Application Insights. Enforces consistent tracked properties, correlation, and no-PII telemetry across split MMO FES workflows.'
applyTo: '**/workflow.json'
---

# Logic Apps Observability & Clean Logging Standards

Standards for emitting clean, consistent, correlated, and secure telemetry from MMO FES Logic Apps (Standard) workflows to Application Insights.

> Grounded in Microsoft guidance: [Enhanced telemetry in Application Insights for Standard workflows](https://learn.microsoft.com/azure/logic-apps/enable-enhanced-telemetry-standard-workflows) and [Monitor and collect diagnostic data](https://learn.microsoft.com/azure/logic-apps/monitor-workflows-collect-diagnostic-data).

## 1. Application Insights is the single observability sink

- Every logic app must be wired to Application Insights via the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting (kept in `local.settings.json` locally, app settings in Azure — never committed).
- Enable **enhanced telemetry** in `host.json` so trigger/action events, retries, traces, exceptions, and dependencies flow to the `requests`, `traces`, `exceptions`, and `dependencies` tables.
- Do not invent a parallel logging mechanism (e.g. HTTP calls to a custom log endpoint) when native telemetry + tracked properties already cover the need.

## 2. End-to-end correlation across split workflows

- Set a **Custom Tracking Id** on every trigger, derived from the business payload — use the existing `_correlationId` (fall back to a generated value only if absent). This populates `ClientTrackingId` and correlates all actions in a run.
- When a workflow publishes a message to the **next** Service Bus queue (routing-slip hand-off), propagate correlation by setting the `x-ms-client-tracking-id` header / a `correlationId` envelope field so the downstream logic app continues the same trace.
- Always include `correlationId` and `documentNumber` as tracked properties on key actions so a single document can be followed across every split logic app.

## 3. Tracked properties — what to log and where

- Use `trackedProperties` on **decision points, stage boundaries, and failure handlers** — not on every action. The object is a sibling of `type` and `runAfter`:

```json
{
  "Create_Document": {
    "type": "ApiConnection",
    "inputs": { "...": "..." },
    "runAfter": { "...": "..." },
    "trackedProperties": {
      "correlationId": "@variables('CorrelationId')",
      "documentNumber": "@variables('DocumentNumber')",
      "stage": "document-processing",
      "outcome": "@action().outputs.statusCode"
    }
  }
}
```

- Recommended standard property set (use consistent camelCase names everywhere):
  `correlationId`, `documentNumber`, `caseType`, `stage`, `messageAction` (complete/abandon/dead-letter), `outcome`, and on failures `failedAction` + `errorMessage` (from `@result(...)`).
- Emit one explicit telemetry/`Compose` action with tracked properties in **every error-handler scope** capturing the failed action name and error.

## 4. Clean-logging discipline

- **Consistency**: identical property names and `stage` values across all workflows. A property must mean the same thing everywhere.
- **Signal over noise**: log stage start/end, branch decisions, settlement outcomes, and failures. Do not emit a tracked property on every trivial `Compose`/`SetVariable` — it inflates cost and dilutes signal.
- **Actionable failures**: every failure log must answer "which document, which stage, which action, what error" without opening run history.
- Tune `host.json` log levels deliberately; avoid blanket verbose logging in production (telemetry volume = cost).

## 5. Security — never log sensitive data

- **No PII** in telemetry: do not put exporter names, addresses, contact details, or full integration payloads into tracked properties. Log identifiers (document number, ids) — not personal data.
- **No secrets**: never log tokens, connection strings, keys, or `@appsetting()` secret values.
- Mark actions that handle sensitive data with **secure inputs/outputs**. Note: tracked properties are **not permitted** on actions with secure inputs/outputs, and cannot reference a secured action — keep telemetry on non-sensitive actions.

## 6. Verification queries

After changes, validate telemetry with Application Insights Logs (KQL), e.g.:

```kusto
requests
| where customDimensions.Category == "Workflow.Operations.Actions"
| where customDimensions["correlationId"] == "<id>"
| project timestamp, name, success, resultCode, customDimensions
```

## Do Not

- Add JSON comments to `workflow.json`.
- Put tracked properties on secure or secret-bearing actions.
- Log PII, secrets, or entire payloads.
- Break correlation when handing a message to the next workflow — always propagate the tracking id.
