# Comprehensive Analysis: GitHub Copilot Agents and Skills for Azure Bicep Deployment

## Executive Summary

The `oss-to-azure` project has a **solid foundation** but can be improved by following emerging best practices from GitHub's official documentation and community patterns. The current structure mixes concepts that should be separated: **agents** (personas/workflows) vs **skills** (reusable capabilities).

---

## 1. Current State Assessment

### Current Project Structure
```
~/projects/oss-to-azure/
├── .github/
│   ├── agents/
│   │   ├── n8n-deployment.bicep.agent.md    # ~450 lines, very detailed
│   │   └── n8n.deployment.terraform.agent.md # ~400 lines, similar structure
│   ├── skills/
│   │   └── n8n-azure-bicep/
│   │       ├── SKILL.md                      # ~100 lines
│   │       ├── assets/templates/azure.yaml
│   │       └── references/
│   │           ├── bicep-requirements.md     # ~200 lines
│   │           ├── n8n-config.md             # ~130 lines
│   │           └── troubleshooting.md        # ~170 lines
│   └── copilot-instructions.md               # ~60 lines
├── infra/
│   ├── main.bicep
│   ├── modules/*.bicep
│   └── hooks/
└── azure.yaml
```

### Strengths ✅
1. **Agents are in correct location** (`.github/agents/`)
2. **Skills follow the SKILL.md convention** with proper frontmatter
3. **Reference files are well-organized** with clear separation of concerns
4. **copilot-instructions.md exists** for repo-wide guidance
5. **Comprehensive technical content** - health probes, SSL, troubleshooting

### Issues/Gaps 🔴

| Issue | Description |
|-------|-------------|
| **Agent files too large** | 400-450 lines each. Best practice: < 200 lines. Large files overwhelm context. |
| **Duplication between agents** | Bicep and Terraform agents share ~60% content (MCP requirements, architecture, post-provision hooks) |
| **Agent does work of skill** | Agent files contain full Bicep code templates, scripts - this should be in skills |
| **Missing file extension convention** | Agent files use `.agent.md` (correct) but skill doesn't leverage the naming |
| **No handoffs defined** | No guided workflows between planning → implementation → validation |
| **Missing boundaries section** | No "never do" constraints in agents (best practice per GitHub research) |

---

## 2. Research Findings

### Source 1: VS Code Official Documentation
**URL**: https://code.visualstudio.com/docs/copilot/customization/agent-skills

**Key Patterns:**
- **Skills use progressive disclosure** - Only load when relevant
- **Three levels**: Discovery (name/description) → Instructions (SKILL.md body) → Resources (files)
- **Skills are portable** across VS Code, Copilot CLI, and coding agent
- Store in `.github/skills/<skill-name>/SKILL.md`

### Source 2: GitHub Official Documentation  
**URL**: https://docs.github.com/en/copilot/concepts/agents/about-custom-agents

**Key Patterns:**
- Agents are **personas with specific jobs**
- Store in `.github/agents/CUSTOM-AGENT-NAME.md`
- Frontmatter: `name`, `description`, `tools`, optionally `model`, `handoffs`
- Keep instructions focused on **behavior**, not implementation details

### Source 3: GitHub Blog - "How to write a great agents.md"
**URL**: https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/

**Critical Best Practices (from 2,500+ repos):**

| Practice | Rationale |
|----------|-----------|
| **Put commands early** | AI references these often |
| **Code examples over explanations** | One snippet > three paragraphs |
| **Set clear boundaries** | "Never touch secrets, vendor dirs, production configs" |
| **Be specific about stack** | "React 18 with TypeScript" not "React project" |
| **Cover 6 core areas** | Commands, testing, project structure, code style, git workflow, boundaries |
| **Use three-tier boundaries** | ✅ Always do, ⚠️ Ask first, 🚫 Never do |

### Source 4: Azure Developer CLI Template Patterns
**URL**: https://github.com/Azure-Samples/azd-starter-bicep

**Key Patterns:**
- `infra/` folder for all IaC
- `infra/core/` or `infra/modules/` for reusable modules
- `.devcontainer/` for dev environment setup
- `.github/workflows/` for CI/CD
- hooks in `infra/hooks/` for post-provision automation

### Source 5: Skills vs Custom Instructions Distinction
**URL**: https://github.com/orgs/community/discussions/183962

**Clarification:**
| Concept | Purpose | Loading |
|---------|---------|---------|
| **copilot-instructions.md** | Always-on repo norms (coding standards, build/test/deploy) | Every prompt |
| **Agent (.agent.md)** | Persona with specific job and tool access | When invoked (@agent-name) |
| **Skill (SKILL.md)** | Reusable capability with instructions + scripts + examples | On-demand by description |

---

## 3. Recommended Organization

### Proposed Structure

```
~/projects/oss-to-azure/
├── .github/
│   ├── copilot-instructions.md              # Always-on repo context (KEEP, enhance)
│   │
│   ├── agents/
│   │   ├── azure-bicep-deployer.agent.md    # SLIM: persona + workflow only
│   │   ├── azure-terraform-deployer.agent.md
│   │   └── azure-architect.agent.md         # NEW: for architecture decisions
│   │
│   └── skills/
│       ├── azure-bicep-generation/          # GENERIC: reusable across apps
│       │   ├── SKILL.md
│       │   ├── patterns/
│       │   │   ├── container-apps.md
│       │   │   ├── postgresql.md
│       │   │   └── log-analytics.md
│       │   └── examples/
│       │       └── complete-template.bicep
│       │
│       ├── azd-deployment/                  # GENERIC: azd patterns
│       │   ├── SKILL.md
│       │   ├── templates/
│       │   │   └── azure.yaml
│       │   └── hooks/
│       │       ├── postprovision.sh
│       │       └── postprovision.ps1
│       │
│       └── n8n-azure/                       # APP-SPECIFIC: n8n configuration
│           ├── SKILL.md
│           ├── config/
│           │   ├── environment-variables.md
│           │   └── health-probes.md
│           └── troubleshooting.md
│
├── infra/                                   # Actual Bicep implementation
│   ├── main.bicep
│   ├── modules/
│   └── hooks/
│
└── azure.yaml
```

### Key Changes

| Change | Before | After | Rationale |
|--------|--------|-------|-----------|
| **Slim down agents** | 450 lines | ~100 lines | Agents define persona + workflow, not implementation |
| **Split skills by concern** | 1 monolithic skill | 3 focused skills | Generic patterns vs app-specific config |
| **Extract shared content** | Duplicated in both agents | Shared `azd-deployment` skill | DRY principle |
| **Add handoffs** | None | Planning → Implementation | Guided workflows |
| **Add boundaries** | Implicit | Explicit ✅⚠️🚫 sections | Prevent destructive mistakes |

---

## 4. Specific Recommendations

### Recommendation 1: Restructure Agent Files

**Current Problem:** Agent files are 400+ lines with full Bicep code, scripts, and implementation details.

**Recommended Agent Structure:**
```markdown
---
name: azure-bicep-deployer
description: Deploy applications to Azure using Bicep and azd. Use when asked to create Azure infrastructure or deploy to Azure.
tools: ['edit', 'search', 'runCommands', 'fetch', 'Azure MCP/*']
model: Claude Sonnet 4.5 (copilot)
handoffs:
  - label: Validate Deployment
    agent: azure-validator
    prompt: Validate the generated Bicep and check for issues.
    send: false
---

# Azure Bicep Deployer

You are an Azure infrastructure specialist who deploys applications using Bicep and Azure Developer CLI (azd).

## Your Role
- Generate production-ready Bicep infrastructure code
- Configure azd for seamless deployment workflows
- Apply Azure best practices for security and cost optimization

## Workflow
1. Gather requirements (app type, database needs, scaling requirements)
2. Load relevant skills for patterns and examples
3. Generate Bicep modules following established patterns
4. Create azure.yaml configuration
5. Set up post-provision hooks if needed

## Commands You Can Run
\`\`\`bash
az bicep build --file main.bicep    # Validate Bicep syntax
azd provision --preview             # Preview deployment
azd up                              # Full deployment
\`\`\`

## Boundaries
- ✅ **Always:** Use managed identity, enable SSL, follow naming conventions
- ⚠️ **Ask first:** Changing SKU tiers, adding new Azure services
- 🚫 **Never:** Hard-code secrets, disable encryption, use public endpoints without auth
```

**Rationale:** 
- ~100 lines vs 450 lines - fits better in context
- Defines WHAT the agent does, not HOW (skills provide the how)
- Includes handoffs for guided workflows
- Clear boundaries prevent mistakes

---

### Recommendation 2: Create Generic Reusable Skills

**Current Problem:** Skills are app-specific (n8n-azure-bicep) but contain generic Azure patterns.

**Recommended: Generic Azure Bicep Skill**
```markdown
---
name: azure-bicep-generation
description: Generate Azure Bicep infrastructure code. Use when creating Container Apps, PostgreSQL, Log Analytics, or other Azure resources.
---

# Azure Bicep Generation Skill

Generate production-ready Bicep code for Azure resources following Microsoft best practices.

## When to Use
- Creating new Azure infrastructure
- Adding resources to existing deployments
- Modernizing Terraform to Bicep

## Key Patterns

### Container Apps Pattern
Load [patterns/container-apps.md](./patterns/container-apps.md) for:
- Health probe configuration (CRITICAL for slow-starting apps)
- Scale rules (scale-to-zero, KEDA)
- Managed identity integration

### PostgreSQL Pattern
Load [patterns/postgresql.md](./patterns/postgresql.md) for:
- Flexible Server configuration
- SSL/TLS requirements
- Firewall rules for Azure services

### Naming Conventions
\`\`\`bicep
var resourceToken = uniqueString(subscription().id, resourceGroup().id, environmentName)
var suffix = take(resourceToken, 6)
\`\`\`

## Critical Rules
1. `newGuid()` can ONLY be used as parameter defaults
2. Always use PostgreSQL FQDN, never internal names
3. Container health probes need extended timeouts for slow-starting apps
```

**Rationale:**
- Reusable across multiple applications (n8n, Gitea, any OSS app)
- Progressive disclosure - load specific patterns only when needed
- Single source of truth for Bicep patterns

---

### Recommendation 3: Separate App-Specific Configuration

**Current Problem:** n8n-specific config mixed with generic Azure patterns.

**Recommended: App-Specific Skill**
```markdown
---
name: n8n-azure
description: n8n workflow automation configuration for Azure. Use when deploying n8n specifically.
---

# n8n Azure Configuration

Configure n8n for deployment on Azure Container Apps with PostgreSQL.

## When to Use
- Deploying n8n to Azure
- Troubleshooting n8n on Azure
- Configuring n8n environment variables

## n8n Environment Variables

See [config/environment-variables.md](./config/environment-variables.md) for:
- Database configuration (SSL required!)
- Authentication settings
- Encryption key management

## Health Probe Requirements

n8n requires **60+ seconds** to start. See [config/health-probes.md](./config/health-probes.md) for:
- Liveness probe: `initialDelaySeconds: 60`
- Startup probe: `failureThreshold: 30`

## Troubleshooting

See [troubleshooting.md](./troubleshooting.md) for common issues:
- CrashLoopBackOff (health probe misconfiguration)
- Database connection refused (SSL/FQDN issues)
- WEBHOOK_URL not set (post-provision hook needed)
```

**Rationale:**
- Clear separation: Azure patterns vs n8n quirks
- When adding a new app (e.g., Gitea), only create gitea-azure skill
- Reuse azure-bicep-generation skill unchanged

---

### Recommendation 4: Enhance copilot-instructions.md

**Current:** Basic commands and architecture overview.

**Recommended Addition:**
```markdown
## Agent & Skill Usage

### Available Agents
- `@azure-bicep-deployer` - Deploy apps using Bicep and azd
- `@azure-terraform-deployer` - Deploy apps using Terraform and azd
- `@azure-architect` - Architecture decisions and resource selection

### Available Skills
Skills are loaded automatically based on context:
- `azure-bicep-generation` - Bicep code patterns
- `azd-deployment` - Azure Developer CLI workflows
- `n8n-azure` - n8n-specific configuration

### Workflow
1. Start with `@azure-architect` for new projects to choose architecture
2. Use `@azure-bicep-deployer` or `@azure-terraform-deployer` for implementation
3. Skills load automatically to provide code patterns

### Adding New Applications
1. Create app-specific skill in `.github/skills/<app>-azure/`
2. Reference generic patterns from `azure-bicep-generation` skill
3. Document app-specific quirks (startup time, env vars, ports)
```

**Rationale:**
- Developers understand the system at a glance
- Clear workflow for extending to new applications
- Complements agents/skills rather than duplicating

---

### Recommendation 5: Add Handoffs for Guided Workflows

**Implement this pattern:**

```yaml
# In azure-architect.agent.md
handoffs:
  - label: Generate Bicep
    agent: azure-bicep-deployer
    prompt: Implement the architecture above using Bicep.
    send: false
  - label: Generate Terraform
    agent: azure-terraform-deployer
    prompt: Implement the architecture above using Terraform.
    send: false

# In azure-bicep-deployer.agent.md
handoffs:
  - label: Deploy to Azure
    agent: azure-bicep-deployer
    prompt: Run azd up to deploy the infrastructure.
    send: false
```

**Rationale:**
- Creates guided workflow: Architecture → Code Generation → Deployment
- User maintains control at each step
- Reduces context switching and confusion

---

## 5. Implementation Priority

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 1️⃣ | Slim down agent files to ~100 lines | Medium | High - better context usage |
| 2️⃣ | Extract generic azure-bicep-generation skill | Medium | High - reusability |
| 3️⃣ | Add boundaries section to agents | Low | Medium - prevents mistakes |
| 4️⃣ | Create azd-deployment skill with shared hooks | Low | Medium - DRY |
| 5️⃣ | Add handoffs between agents | Low | Medium - workflow |
| 6️⃣ | Update copilot-instructions.md | Low | Low - documentation |

---

## 6. Summary

### The Core Principle

**Agents = WHO (persona/workflow) | Skills = HOW (patterns/implementation)**

| Component | Current State | Recommended State |
|-----------|--------------|-------------------|
| **Agents** | Monolithic, 450+ lines, include implementation | Slim, ~100 lines, define persona + workflow |
| **Skills** | App-specific only | Generic patterns + app-specific config |
| **copilot-instructions** | Basic commands | System overview + workflow guidance |
| **Handoffs** | None | Guided workflows between agents |
| **Boundaries** | Implicit | Explicit ✅⚠️🚫 sections |

### Expected Benefits

1. **Better AI context utilization** - Slim agents don't overwhelm context
2. **Easier maintenance** - Change generic patterns in one place
3. **Faster extension** - Add new apps by creating one small skill
4. **Fewer mistakes** - Explicit boundaries prevent destructive actions
5. **Smoother workflows** - Handoffs guide developers through the process

---

## Sources Referenced

1. VS Code Agent Skills Documentation - https://code.visualstudio.com/docs/copilot/customization/agent-skills
2. GitHub Docs: About Agent Skills - https://docs.github.com/en/copilot/concepts/agents/about-agent-skills
3. GitHub Docs: About Custom Agents - https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-custom-agents
4. GitHub Blog: How to write a great agents.md - https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/
5. Azure-Samples/azd-starter-bicep - https://github.com/Azure-Samples/azd-starter-bicep
6. VS Code Custom Agents Documentation - https://code.visualstudio.com/docs/copilot/customization/custom-agents
7. GitHub Community Discussion on Agents vs Skills - https://github.com/orgs/community/discussions/183962
