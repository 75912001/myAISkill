---
name: find-bug
description: Use this skill when the user asks to find one bug, 找bug, 找一个 P0/P1 bug, continue bug hunting, audit for a critical issue, or find a reproducible high-severity defect across server, client, frontend, mobile, desktop, CLI, deployment, testing, or integration workflows.
---

# 找bug

## Goal

Find one real P0/P1 bug with reproducible evidence. Cover any target the user gives: backend, frontend, mobile, desktop, CLI, APIs, tests, deployment, logs, runtime services, or integrations.

Stop expanding once one credible P0/P1 is found unless the user explicitly asks to continue.

## Severity Bar

Only report P0/P1 as the primary result.

- P0: security compromise, data loss/corruption, account takeover, privacy leak, production-wide outage, payment/order corruption, deterministic crash on a critical path, or a core user flow becoming unusable.
- P1: high-probability severe regression, auth/session bypass, cross-user data mixup, state inconsistency, serious race, deploy breakage, large-scale login/payment/workflow failure, or a bug that can reliably block a critical operation.

Do not inflate low-value log noise, style issues, test-only quirks, harmless warnings, or unclear speculation into P0/P1.

## Workflow

1. Ground in the target.
   - Read local instructions first when present, such as AGENTS.md, README, TEST docs, package manifests, configs, routing, auth/session code, API clients, state management, deploy files, and likely entrypoints.
   - Check the current worktree before edits or tests if the task may touch files.
   - If the target is ambiguous and cannot be inferred, ask a short clarifying question.

2. Choose the highest-risk surfaces.
   - Server/API: auth, session, token, permissions, control-plane RPCs, persistence, migrations, queues, retries, idempotency, concurrency, crash paths, and exposed ports.
   - Client/frontend/mobile/desktop: login state, token storage/refresh, route guards, permission gates, cache invalidation, cross-user data residue, offline/reconnect, duplicate submit, payment/order flows, WebSocket/push binding, environment endpoints, and privacy leaks.
   - CLI/tools/tests/deploy: destructive defaults, wrong environment targeting, secret exposure, missing auth, flaky release blockers, data cleanup, and startup/runtime failures.
   - Integration: contract mismatches, stale generated code, version skew, schema drift, timeout/retry behavior, and inconsistent state across services.

3. Prove or disprove quickly.
   - Prefer static audit first, then the smallest safe dynamic verification.
   - Use existing tests, scripts, logs, browser tools, simulators, or local probes when appropriate.
   - Dynamic tests that affect real accounts, production data, payments, external systems, service restarts, Redis/etcd/database state, or destructive actions require user confirmation.
   - Use unique test data and clean up only when permitted by the user and project rules.

4. Stop at the first real P0/P1.
   - Provide phenomenon, severity, exact reproduction steps, key code/log/network/screenshot evidence, impact, and initial root cause.
   - Include tests or commands run, and distinguish confirmed facts from inference.
   - If only a candidate is found, label it as a candidate and state what verification remains.

5. Ask how to handle it.
   - After reporting the bug, ask the user whether to record it in the current project BUG.md, continue finding another P0/P1, or start a fix plan.
   - Do not create or modify BUG.md until the user confirms.
   - If recording is confirmed, inspect or create BUG.md according to local project rules and record: title, severity, status, discovery time, reproduction, evidence, impact, root cause, and suggested handling.

## Output Shape

Use concise sections:

**Finding**
- Severity, title, and affected surface.

**Evidence**
- Code references, logs, screenshots, network traces, test output, or reproduction commands.

**Impact**
- Who or what can be affected and under what conditions.

**Validation**
- What was run, passed, failed, or not run.

**Next Handling**
- Ask whether to record in BUG.md, continue hunting, or plan a fix.

If no P0/P1 is found, say so directly, list what was checked, and note remaining high-risk areas.
