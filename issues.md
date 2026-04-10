# Journey README Student Review: Issues & Improvements

Student-perspective review of all 5 journey READMEs. Issues are prioritized by impact on the learning experience.

**Overall grades:** All journeys scored B+. The content is solid but each has specific gaps that would trip up a learner following along step by step.

---

## Cross-Journey Issues (Applies to Multiple READMEs)

### ✅ CJ-2: Duplicate Verify and Verification Checklist sections
**Journeys:** n8n, Grafana, Superset
**Impact:** Medium
**Problem:** Step 3 (Verify) and the later Verification Checklist section contain nearly identical curl commands and agent prompts. Learners read the same content twice and wonder if they missed something.
**Fix:** Merge into one Verification section. Either remove the duplicate or make the checklist substantively different (e.g., a table format with checkboxes covering health, browser access, login, and logs).

### ✅ CJ-3: First-time terminology not explained
**Journeys:** n8n, Grafana, Superset
**Impact:** Medium
**Problem:** Terms like "Bicep" (Azure's IaC language), "MCP" (Model Context Protocol), "Helm" (Kubernetes package manager), and "CrashLoopBackOff" are used without explanation. A learner new to Azure infrastructure will hit "wait, what?" moments.
**Fix:** Add a one-line parenthetical on first use: "Bicep (Azure's infrastructure-as-code language)", "MCP (Model Context Protocol)", etc.

### ✅ CJ-4: No expected output shown after verification commands
**Journeys:** n8n, Superset, SmartTodo
**Impact:** Medium
**Problem:** Verification commands like `curl` and `kubectl get pods` don't show what correct output looks like. Learners can't distinguish success from failure.
**Fix:** Add a commented expected-output block after each verification command:
```bash
kubectl get pods -n superset
# Expected: superset-xxxxx   1/1   Running   0   5m
```

### ✅ CJ-5: The `>` prompt convention is never explained
**Journeys:** All
**Impact:** Low
**Problem:** Prompts inside code blocks use `>` to indicate the Copilot CLI input, but this convention is never defined. A learner might type the `>` character literally.
**Fix:** Add a note before the first prompt in each journey: "Lines starting with `>` show what to type in the Copilot CLI session."

### ✅ CJ-6: Journey numbering mismatch
**Journeys:** n8n, Grafana, Superset
**Impact:** Low
**Problem:** The individual READMEs number themselves differently than the parent README. The parent has AIMarket as #01, but n8n calls itself "Journey 01." This undermines trust.
**Fix:** Since Journey's are all independent, we don't need any numbering mentioned in the READMEs. Remove "Journey 01" from n8n, "Journey 02" from Grafana, etc. The parent README can refer to them by name, not number.

---

## n8n Journey (journeys/n8n/README.md)

### ✅ N8N-1: Deployment is a "black box"
**Impact:** High
**Problem:** The single-prompt deployment (line 112) is exciting but the tutorial doesn't explain what the learner should expect to see while it runs. Will there be a progress indicator? Will it ask questions? A 7-minute wait with no context creates anxiety.
**Fix:** Add 2-3 sentences describing what to expect: "The deployment takes 5+ minutes. You'll see the agent generating Bicep files, registering providers, and running `azd up`. You may be prompted to confirm your subscription."

### ✅ N8N-3: Assignment is too simple
**Impact:** Low
**Problem:** The assignment (line 329) is just one question and a cleanup command. Compare to Superset's assignment which has a cross-journey comparison exercise.
**Fix:** Add a hands-on task: "Create a simple n8n workflow that sends an HTTP request to a public API." This exercises the deployed app, not just the deployment.

---

## Grafana Journey (journeys/grafana/README.md)

### ✅ GF-1: Verification section is too thin
**Impact:** High
**Problem:** Step 3 Verify (line 128) just checks an HTTP 200. It doesn't show how to log in, view the Grafana UI, or confirm the admin password works. The learner finishes and wonders "now what?"
**Fix:** Add steps: retrieve the admin password, open the browser URL, log in, and see the Grafana home page. This gives a more satisfying conclusion to the deployment and a clearer path to the troubleshooting section.

### ✅ GF-2: SQLite persistence warning should come earlier
**Impact:** Medium
**Problem:** The "Dashboards Lost After Restart" troubleshooting (line 260) is buried at the bottom. A learner who creates dashboards before reading this will be frustrated.
**Fix:** Add a prominent callout near the top (after Architecture): "⚠️ Grafana uses SQLite by default, which is ephemeral in containers. Dashboards are lost on container restart. See Storage Considerations for production options."

### ✅ GF-3: No explanation of what skills the agent loads
**Impact:** Low
**Problem:** The tutorial says the agent "handles the deployment" but doesn't mention which skills it loads (e.g., `grafana-azure`). Learners from Journey 01 know about skills, but direct visitors don't.
**Fix:** Add one sentence: "The agent loads the `grafana-azure` skill, which provides Grafana-specific configuration for health probes, ports, and environment variables."

---

## Superset Journey (journeys/superset/README.md)

### ✅ SS-1: No "how to use it" step after deployment
**Impact:** High
**Problem:** The tutorial deploys and verifies health, but never shows the learner how to open Superset in a browser, log in, or see the dashboard. The login URL and credentials are buried in the Configuration Reference.
**Fix:** Add a "Step 4: Open Superset" section after verification: get the URL, open the browser, log in with admin/[generated password]. Include a screenshot of the login page.

### ✅ SS-2: Configuration Reference breaks tutorial flow
**Impact:** High
**Problem:** 95 lines of Kubernetes reference material (ConfigMaps, emptyDir, psycopg2 YAML) sit between Deploy and Troubleshooting. The agent handles all of this automatically, so it's not actionable for the learner following the tutorial.
**Fix:** Wrap in a `<details><summary>Deep Dive: How the Agent Configures Superset</summary>` collapsible block, or move to an appendix. The main tutorial flow should be: Setup → Deploy → Verify → Use → Clean Up.

### ✅ SS-3: Missing "what if azd up fails?" troubleshooting
**Impact:** Medium
**Problem:** The troubleshooting section only covers post-deployment issues (psycopg2, init container failures). The most common failure point for learners is `azd up` itself (subscription quotas, region capacity, provider registration).
**Fix:** Add a "Deployment Failed" troubleshooting entry covering common `azd up` failures.

### ✅ SS-4: Kubernetes jargon unexplained
**Impact:** Medium
**Problem:** Terms like "emptyDir volumes", "ConfigMap", "Init:Error", and "CrashLoopBackOff" are used without context. The "Why AKS" section (line 75) lists Kubernetes patterns but doesn't explain them.
**Fix:** Add brief parenthetical explanations on first use. For example: "init containers (containers that run before the main app starts, used for setup tasks like database migrations)."

---

## AIMarket Journey (journeys/aimarket/README.md)

### ✅ AM-1: Phase 3 Step 1 missing environment variable setup
**Impact:** High (Critical)
**Problem:** Phase 3 requires Azure AI Search and Azure OpenAI credentials, but the tutorial doesn't show how to get them. Learners need to know the exact variable names (`AZURE_SEARCH_ENDPOINT`, `AZURE_SEARCH_API_KEY`, etc.), where to find the values in the Azure Portal, and how to set them locally.
**Fix:** Add an explicit setup block before Phase 3 Step 2 showing each required variable and how to obtain its value.

### ✅ AM-2: Phase 2 (Frontend) feels rushed compared to Phase 1
**Impact:** High
**Problem:** Phase 1 has 5 detailed steps with inspect/test blocks. Phase 2 has a single monolithic prompt (line 299) that generates the entire React frontend at once, with no intermediate inspection or testing guidance.
**Fix:** Split Phase 2 into 2 steps: (1) generate pages and components, (2) add cart and chat stub. Add a "🔍 Inspect" block for component structure. Add a screenshot or description of what the running frontend should look like.

### ✅ AM-3: Phase 3 search indexing step is implicit
**Impact:** Medium
**Problem:** Between generating the search integration code and testing it, learners must push products to the Azure AI Search index. This step is implied by the spec but never stated in the README.
**Fix:** Add an explicit step: "Before testing search, push your products to the index by calling `POST /api/products/reindex` or restarting the API."

### ✅ AM-4: Phase 4 Docker rebuild commands are unexplained
**Impact:** Medium
**Problem:** The Docker rebuild step (Phase 4, Step 3) uses bash variable substitutions like `ACR_NAME=${ACR%%.*}` without explanation. Learners who aren't bash experts will be confused.
**Fix:** Add inline comments explaining each variable substitution, or replace with simpler multi-line commands.

### ✅ AM-5: No Docker troubleshooting section
**Impact:** Medium
**Problem:** The most common Phase 4 failures are Docker-related (build context too large, wrong platform on Apple Silicon, missing build args). These aren't covered in troubleshooting.
**Fix:** Add 2-3 Docker troubleshooting entries: build context errors, `--platform linux/amd64` for M1/M2/M3, and `VITE_API_URL` not reaching the build step.

---

## SmartTodo Journey (journeys/smart-todo/README.md)

### ✅ ST-1: Phase 1 has no local database solution
**Impact:** High (Critical)
**Problem:** The API uses Azure SQL, but a learner following Phase 1 locally has no database to connect to. Phase 3 creates the Azure SQL instance, but Phase 1 asks you to build and test the API against it. There's no guidance on setting up a local SQL Server (Docker or otherwise) or using a different local database.
**Fix:** Restructure to use SQLite locally (like AIMarket) with a note that deployment switches to Azure SQL later in the journey. Update the plan to account for this change.

### ✅ ST-2: Phase 2 (iOS) is macOS-only but not called out prominently
**Impact:** High
**Problem:** The Xcode/SwiftUI requirement means Windows and Linux users can't complete Phase 2. This isn't stated prominently until the prerequisites, which are easy to skim past.
**Fix:** Add a prominent callout near the top: "⚠️ Phase 2 requires macOS with Xcode installed. Windows/Linux users can skip to Phase 3 and test the API via curl." Don't let someone invest 45 minutes in Phase 1 before discovering they can't continue.

### ✅ ST-3: Managed identity SQL setup needs more explanation
**Impact:** High
**Problem:** Phase 3, Step 3 has a `sqlcmd` one-liner that creates a managed identity user. This is the most intimidating command in the entire tutorial. It requires being "Azure AD admin on the SQL server" but doesn't explain how to verify this or what to do if you're not.
**Fix:** Double-check that this is the only way to handle this. If it is, add 4-5 sentences explaining what the command does, why Bicep can't do it, and how to verify you have the right permissions. Make the Azure AD admin requirement a ⚠️ callout.

### ✅ ST-4: local.settings.json never shown
**Impact:** Medium
**Problem:** Phase 1 Steps 4 and 5 reference environment variables (`AZURE_AI_ENDPOINT`, `AZURE_AI_KEY`, database connection) in `local.settings.json`, but this file is never shown with template values.
**Fix:** Add a `local.settings.json` template snippet showing placeholder values so learners know what to fill in.

### ✅ ST-5: No Swift/SwiftUI context for non-iOS developers
**Impact:** Medium
**Problem:** Phase 2 generates SwiftUI code but provides no context for learners unfamiliar with Swift. Concepts like `Codable`, `async/await`, `#if DEBUG`, and the `.xcodeproj` file structure are Swift-specific.
**Fix:** Add a 3-4 sentence primer: "SwiftUI uses `Codable` for JSON serialization (similar to TypeScript interfaces), `async/await` for network calls (same concept as JavaScript), and `#if DEBUG` for compile-time feature flags."

---

## Potential Content Removals (Won't Lose Quality)

| Journey | Section | Why Remove |
|---------|---------|------------|
| n8n | Verification Checklist (lines 286-304) | Duplicates Step 3: Verify |
| Grafana | Verification Checklist (lines 292-308) | Duplicates Step 3: Verify |
| Superset | Configuration Reference (lines 192-286) | 95 lines of reference material the agent handles. Collapse into `<details>` block |
| Superset | Verification Checklist (lines 372-389) | Duplicates Step 3: Verify |
| AIMarket | Phase 4 apple silicon note (line 560 area) | Already covered in PLAN.md Known Deployment Gotchas |

---
