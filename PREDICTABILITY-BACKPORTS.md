# Solution Predictability Backports

This ledger tracks defects discovered by deploying the generated solutions from `DanWahlin/github-azure-agentic-journeys-solution` with fresh `azd` environments. Working fixes are first proven against live Azure resources in the solution repository, then backported into this source repository's journey README/PLAN and reusable skill guidance.

## Status legend

- **Solution verified**: repaired implementation passed the live deployment check.
- **Source pending**: source journey and skill guidance still needs the proven behavior integrated.
- **Source integrated**: relevant source documentation and skills contain the proven behavior.

## Backports

### BP-001: n8n post-provision must wait for the replacement revision

- **Journey:** n8n
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** A clean `azd up` returned success after setting `WEBHOOK_URL`, while an immediate Playwright navigation received HTTP 404 with `Cannot GET /`. The same page rendered correctly after the replacement Container App revision settled.
- **Root cause:** Updating `WEBHOOK_URL` changes the Container App revision. The generated hook returned before both `/healthz` and `/` were serving HTTP 200.
- **Proven fix:** After `az containerapp update`, poll `/healthz` and the editor root for up to five minutes. Exit successfully only after both return HTTP 200 for six consecutive probes over 30 seconds. A brand-new deployment proved the old revision could still intermittently return 404 after one successful probe; the sustained check eliminated that race, and immediate HTTP, metadata, and browser verification passed.
- **Solution files:**
  - `n8n/infra-n8n/hooks/postprovision.js`
  - `n8n/issues.md`
- **Source files updated:**
  - `journeys/n8n/README.md`
  - `.github/skills/n8n-azure/SKILL.md`
  - `.github/skills/n8n-azure/config/environment-variables.md`
  - `.github/skills/n8n-azure/troubleshooting.md`
  - `.github/skills/journey-runner/SKILL.md`

### BP-002: Bicep module parameters derived from `uniqueString` need explicit length constraints

- **Journey:** n8n, reusable for generated Bicep
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** Bicep emitted `BCP334` warnings because a module's `resourceToken` parameter had no length contract, even though `uniqueString()` always produces 13 characters.
- **Proven fix:** Decorate the module parameter with `@minLength(13)` and `@maxLength(13)`. All n8n Bicep then compiled without `BCP334` warnings.
- **Solution file:** `n8n/infra-n8n/resources.bicep`
- **Source files updated:**
  - `.github/skills/n8n-azure/SKILL.md`
  - `.github/skills/container-apps-deployment/SKILL.md`
  - `.github/skills/journey-template/SKILL.md`

### BP-003: Superset clean `azd up` must initialize hook-owned secrets

- **Journey:** Superset
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** Bicep and Azure provisioning succeeded, then `postprovision` failed with `Missing required azd env value: SUPERSET_SECRET_KEY`. `SUPERSET_ADMIN_PASSWORD` had the same undeclared prerequisite.
- **Root cause:** The hook required both values, but neither `azure.yaml`, Bicep parameters, nor clean-environment setup generated them.
- **Proven fix:** In the cross-platform Node hook, generate cryptographically random values when absent, persist them with `azd env set`, never print them, and reuse existing values on reruns. A brand-new environment with neither value preconfigured completed Helm installation, Kubernetes secret creation, Superset rollout, LoadBalancer discovery, PostgreSQL verification, and authenticated browser login.
- **Solution implementation module:** `superset/infra-superset/hooks/postprovision.mjs`, invoked by `azure.yaml` through the explicit command `node ./infra-superset/hooks/postprovision.mjs`. The unsupported pattern is a bare `.mjs` lifecycle path without an explicit runtime.
- **Source files updated:**
  - `journeys/superset/README.md`
  - `.github/skills/superset-azure/SKILL.md`
  - `.github/skills/journey-runner/SKILL.md`
  - `.github/agents/oss-to-azure-deployer.agent.md`

### BP-004: SmartTodo must document and preflight every required Entra principal input

- **Journey:** SmartTodo
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** A clean non-interactive `azd up` stopped before creating resources because `AZURE_PRINCIPAL_LOGIN` was missing. The generated parameter contract requires `principalId`, `principalLogin`, and `principalType`; at discovery time, the SmartTodo README/PLAN and shared skill guidance did not explain how to populate all three.
- **Integrated fix:** Cross-platform preflight guidance now resolves and stores `AZURE_PRINCIPAL_ID`, `AZURE_PRINCIPAL_LOGIN`, and `AZURE_PRINCIPAL_TYPE` before `azd up`, with separate user and service-principal handling and one actionable failure before provisioning if any value is unavailable.
- **Solution contract:** `smart-todo/infra/main.parameters.json`
- **Source files updated:**
  - `journeys/smart-todo/README.md`
  - `journeys/smart-todo/PLAN.md`
  - `.github/skills/journey-runner/SKILL.md`
  - `.github/skills/journey-template/SKILL.md`

### BP-005: Serialize Microsoft Foundry account and model deployment

- **Journey:** SmartTodo, reusable for Foundry-based journeys
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** The resource-group deployment failed with `RequestConflict` because the model child operation raced the parent `Microsoft.CognitiveServices/accounts` resource while its provisioning state was non-terminal.
- **Proposed/proven pattern:** Place the model child resource in a separate nested Bicep module and pass the parent account name from the account resource. The module boundary creates a deployment-stage dependency instead of issuing account and model operations in the same flat resource deployment.
- **Solution files:**
  - `smart-todo/infra/resources.bicep`
  - `smart-todo/infra/ai-model-deployment.bicep`
- **Live proof:** A brand-new environment successfully deployed the nested model deployment, Foundry account, Function App, SQL database, and full SmartTodo API lifecycle.
- **Source files updated:**
  - `journeys/smart-todo/README.md`
  - `journeys/smart-todo/PLAN.md`
  - `.github/skills/journey-template/SKILL.md`
  - `.github/skills/journey-runner/SKILL.md`

### BP-006: Don't use reserved words in generated SQL firewall-rule names

- **Journey:** SmartTodo, reusable for Azure SQL generation
- **Status:** Solution verified from a fresh environment, source integrated
- **Observed:** `azd` validation warned that `AllowAllWindowsAzureIps` contains the reserved word `WINDOWS` and stated that deployment would fail.
- **Fix:** Use a neutral name such as `AllowAzureServices` while retaining the documented `0.0.0.0` start/end semantics.
- **Solution file:** `smart-todo/infra/resources.bicep`
- **Live proof:** A brand-new environment emitted no reserved-name warning and Azure created the `AllowAzureServices` rule successfully.
- **Source files updated:**
  - `journeys/smart-todo/README.md`
  - `journeys/smart-todo/PLAN.md`
  - `.github/skills/journey-template/SKILL.md`

## Already integrated before this deployment pass

- `azd` lifecycle hooks use supported CommonJS `.js` or `.ts` paths rather than bare `.mjs` hook paths.
- Superset browser verification uses `input[type="submit"], button[type="submit"]`.
- SmartTodo shared verification uses the documented list endpoint rather than an undefined detail endpoint.

## Integration rule

Do not mark a backport **Source integrated** until:

1. The source README/PLAN and every listed skill agree on the behavior.
2. Generated scripts remain Windows, macOS, and Linux compatible.
3. Syntax/static validation passes.
4. The repaired solution behavior has already been demonstrated against live Azure resources.
