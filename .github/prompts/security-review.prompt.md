---
mode: agent
description: Review changed workflows against Defra security standards and the OWASP Top 10.
---

# Security Review

Review the current changes (or the files I specify) for security issues against Defra security standards and the OWASP Top 10. This repo is Azure Logic Apps (Standard) — `workflow.json`, `connections.json`, `parameters.json`, `host.json` — so focus on workflow-level risks.

## What to check

- Secrets, API keys, access keys, connection strings, or SAS tokens hard-coded or committed in `connections.json`, `parameters.json`, `host.json`, or `local.settings.json` (real values must live in Azure App Settings / Key Vault and a git-ignored `local.settings.json`)
- Connections not using `ManagedServiceIdentity`, or using an incorrect/over-broad audience scope
- Over-privileged connectors or reused broadly-scoped identities (least-privilege breaches)
- PII in run history, `trackedProperties`, `clientTrackingId`, action names, or debug actions (names, addresses, emails, phone numbers, contact IDs, bank details, tokens)
- Environment-specific values (`HostUrl`, storage URLs, subscription IDs, resource groups) hardcoded instead of parameterised via `@appsetting()`
- Missing error handling / retry policies on external calls (Dataverse, Service Bus, HTTP), or Service Bus messages not completed/abandoned on failure
- Unvalidated trigger inputs; unauthenticated Request triggers without justification
- `local.settings.json` not excluded via `.funcignore` / `.copilotignore`

## Output

Produce a findings table: `File | Action/Section | Issue | Severity (Blocking/Recommended/Nit) | Recommendation`. Summarise total findings by severity and state whether the change is safe to merge. Do not edit workflows — report only.

## References

- [security-and-pii skill](../skills/security-and-pii/SKILL.md)
- [Defra security standards](https://github.com/DEFRA/software-development-standards/blob/main/docs/standards/security_standards.md)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
