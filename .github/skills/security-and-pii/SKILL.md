---
name: security-and-pii
description: 'Apply Defra security and PII handling rules when writing or reviewing Azure Logic Apps (Standard) workflows — connections.json, parameters.json, workflow.json, triggers, and actions in MMO FES integrations. Covers Managed Identity, secret handling, run-history PII, input validation, and least-privilege connectors.'
license: OGL-UK-3.0
metadata:
  author: mmo-fes
  version: "1.0"
---

# Security and PII — Logic Apps

Security and personal-data rules for MMO FES Azure Logic Apps (Standard) workflows. Follow these whenever you add or change a connection, trigger, action, parameter, or app setting. Aligned to [Defra security standards](https://github.com/DEFRA/software-development-standards/blob/main/docs/standards/security_standards.md) and [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/).

## Authenticate with Managed Identity

- Every managed API connection must use `ManagedServiceIdentity` authentication. Never use API keys, access keys, connection strings, SAS tokens, or shared credentials in a connection.
- Set the correct audience per connector:
  - Service Bus → `https://servicebus.azure.net`
  - Azure Storage / Table → `https://storage.azure.com`
  - Dataverse → the Dynamics 365 organisation URL
- Grant the workflow's identity only the roles it needs (least privilege). Do not reuse a broadly-scoped identity across unrelated connectors.

## Never commit secrets

- Do not place secrets, keys, or connection strings in `connections.json`, `parameters.json`, `host.json`, or a committed `local.settings.json`.
- Keep real values in Azure App Settings (or Key Vault references) and a local, git-ignored `local.settings.json`. Confirm it is listed in `.funcignore` and `.copilotignore`.
- Reference environment-specific values via `@appsetting()` / `parameters()` only.

## Keep PII out of run history and logs

- Run history, `trackedProperties`, and `clientTrackingId` are retained and searchable — treat them like logs. Never put PII in them: exporter names, addresses, emails, phone numbers, contact IDs, bank details, or vessel-owner personal data.
- Do not add debug actions that persist or forward raw trigger payloads or Dataverse records. Reference records by a non-personal identifier.
- Use non-PII correlation/tracking identifiers.

## Validate and normalise trigger inputs

- Treat all trigger inputs (Service Bus messages, HTTP request bodies, Dataverse records) as untrusted. Validate required fields and expected shapes before use; branch to error handling on invalid input rather than proceeding.
- Do not construct queries or downstream calls by naively concatenating untrusted input — use typed parameters/expressions and encode where required.
- Fail safely: abandon/dead-letter malformed Service Bus messages instead of silently dropping them.

## Least-privilege and hygiene

- Remove unused connections and parameters.
- Do not weaken trigger security (e.g. unauthenticated Request triggers) without an approved reason.
- Report any secret, key, or PII you find in committed files instead of proceeding silently.

## References

- [Defra security standards](https://github.com/DEFRA/software-development-standards/blob/main/docs/standards/security_standards.md)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
