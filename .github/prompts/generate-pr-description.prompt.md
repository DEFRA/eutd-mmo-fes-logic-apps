---
mode: agent
description: Write a structured pull request description from the staged/committed changes.
---

# Generate PR Description

Summarise the current branch changes into a pull request description ready to paste into GitHub.

## Format

```markdown
## What
Short summary of what changed and why.

## Changes
- Bullet list of the notable changes (workflows, actions, connections, parameters, config)

## Testing
- How the change was validated (designer render, local run, run history)

## Standards checklist
- [ ] Workflow validates in the designer / CLI with no JSON errors
- [ ] All connections use Managed Identity; no secrets or keys committed
- [ ] No PII in run history, tracked properties, or action names
- [ ] Environment values parameterised via `@appsetting()`
- [ ] Error handling / retry policies present on external calls
- [ ] Conventional commit messages; branch follows `<type>/<brief-description>`

## Notes
Anything reviewers should know (breaking changes, follow-ups, deviations with justification).
```

## Rules

- Derive content from the actual diff; do not invent changes
- Use conventional-commit-style language
- Flag any standards deviation explicitly

## References

- [copilot-instructions.md](../copilot-instructions.md) — quality gates and standards
- [Defra software development standards](https://github.com/DEFRA/software-development-standards)
