# Journey Test Harness Issues

## 2026-07-17 — SmartTodo verifier called an endpoint outside the journey contract

- **Observed:** `.github/scripts/verify-smart-todo.mjs` created a todo successfully, then failed with HTTP 404 on `GET /api/todos/:id`.
- **Cause:** SmartTodo's PLAN defines `GET /api/todos?userId=<id>` but no GET-by-ID route.
- **Fix:** Fetch the user list and locate the created ID before deletion.
- **Verification:** Passed against both the original live deployment and a separate brand-new SmartTodo environment, including create, AI step generation, step completion, list-based fetch, delete, and final absence.
- **Status:** Resolved and integrated.
