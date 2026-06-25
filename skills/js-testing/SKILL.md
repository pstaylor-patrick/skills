---
name: pst:js-testing
description: Vitest, Jest, Cypress, and Testing Library tests. Auto-applied by the pst shim on every JS test change; also invocable directly.
auto:
  extensions: [js, jsx]
  detect: ["**/*.test.js", "**/*.spec.js", "**/*.cy.js", "vitest.config.*", "jest.config.*", "cypress.config.*"]
---

# JavaScript Testing Cheat Sheet

Source: Vitest docs + Jest CLI docs + Cypress Best Practices + Testing Library queries docs

Question: Do tests fail only on behavior regressions, not timing or environment luck?

Favor:
- Put unit logic in Vitest or Jest; browser flows in Cypress.
- Query UI by role, label, or text.
- Mock or intercept network with stable fixtures.
- Use fake timers for clock-driven behavior.
- Seed explicit state per test.
- Assert visible behavior, not implementation details.
- Keep coverage thresholds at package or changed-code scope.

Forbid by default:
- Committed `.only` or `.skip`.
- Arbitrary sleeps like `cy.wait(500)` or bare `setTimeout`.
- Snapshotting large markup trees by default.
- Real network calls to third-party services.
- Shared mutable globals between tests.

CI:
- `vitest run --coverage`
- `jest --ci --coverage`
- `cypress run`
- `! git grep -nE "\\.(only|skip)\\(|cy\\.wait\\([0-9]+" -- '*.test.js' '*.spec.js' '*.cy.js' 'cypress/**'`

Agent protocol:
1. Pick the smallest runner that matches the behavior.
2. Remove time and network flake first.
3. Tighten assertions around user-visible outcomes.
4. Preserve behavior.
