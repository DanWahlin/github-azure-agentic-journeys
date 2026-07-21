# Cross-Platform Tool Installation

The journeys support Windows, macOS, and Linux. Install only the tools listed in the prerequisite section of the journey you are running. Validate every required command before generating code or creating Azure resources.

> Windows examples use PowerShell. macOS and Linux examples use a POSIX shell. Generated Azure Developer CLI hooks use JavaScript or TypeScript instead of OS-specific `.sh` or `.ps1` scripts.

## Standard tools

### Node.js 24 LTS or later

Node.js 20 reached end of life in April 2026. Install a currently supported Long-Term Support release, preferably Node.js 24, from the [official Node.js downloads](https://nodejs.org/en/download). Check the [release lifecycle](https://nodejs.org/en/about/previous-releases) before pinning a new journey.

```text
node --version
npm --version
```

### Azure CLI

Use Microsoft's [Azure CLI installation guide](https://learn.microsoft.com/cli/azure/install-azure-cli) for Windows, macOS, or your Linux distribution. Don't pipe a remote installer directly into an elevated shell.

```text
az version
az login
az account show
```

### Azure Developer CLI

This repository requires Azure Developer CLI (`azd`) 1.28.0 or later for cross-platform JavaScript and TypeScript hooks.

| OS | Install |
|---|---|
| Windows | `winget install --exact --id Microsoft.Azd` |
| macOS | `brew install azure/azd/azd` |
| Linux | Use the signed `.deb`/`.rpm` from [Azure Developer CLI releases](https://github.com/Azure/azure-dev/releases), or download and inspect Microsoft's installer before executing it |

The [official azd installation guide](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) has current distribution-specific steps. Upgrade through the same package manager used to install it.

```text
azd version
azd config set auth.useAzCliAuth true
```

The second command makes `azd` reuse the authenticated Azure CLI session instead of relying on a separate cached credential.

### GitHub CLI

| OS | Install |
|---|---|
| Windows | `winget install --exact --id GitHub.cli --source winget` |
| macOS | `brew install gh` |
| Linux | Follow the [official package repository instructions](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) |

```text
gh --version
gh auth status
```

### Docker (optional local container work)

- Windows: [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
- macOS: [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/)
- Linux: [Docker Engine](https://docs.docker.com/engine/install/)

Verify the daemon and Buildx, not just the client binary:

```text
docker version
docker buildx version
docker info
```

Don't automatically add a Linux user to the `docker` group. Docker documents that daemon access is effectively root-equivalent in its [daemon attack-surface guidance](https://docs.docker.com/engine/security/#docker-daemon-attack-surface).

## Journey-specific tools

### kubectl (optional direct cluster access)

Keep `kubectl` within one minor version of the target AKS cluster.

| OS | Install |
|---|---|
| Windows | `winget install --exact --id Kubernetes.kubectl` |
| macOS | `brew install kubectl` |
| Linux | Use the signed Kubernetes package repository or a checksum-verified binary from the [Linux installation guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) |

Official platform guides: [Windows](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/), [macOS](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/), and [Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).

```text
kubectl version --client
```

`az aks install-cli` is an official alternative, but it downloads the current release, also installs `kubelogin`, and may target a privileged path on Unix. Don't run it silently on a managed host.

### Helm 3 (optional direct cluster access)

The Superset journey runs Helm inside Azure through AKS run command, so Helm is not required on the host. If you install Helm for direct cluster work, use Helm 3. Unversioned package-manager commands may install Helm 4.

| OS | Install |
|---|---|
| Windows | Run `winget show --exact --id Helm.Helm --versions`, then install an available 3.x version with `winget install --exact --id Helm.Helm --version <3.x-version>` |
| macOS | `brew install helm@3`, then add `$(brew --prefix helm@3)/bin` to `PATH` |
| Linux | Use a checksum-verified Helm 3 archive from [Helm releases](https://github.com/helm/helm/releases), or download and inspect `get-helm-3` before running it |

See the [official Helm 3 installation guide](https://helm.sh/docs/v3/intro/install/).

```text
helm version
```

The reported major version must be `v3`.

### Azure Functions Core Tools v4

| OS | Install |
|---|---|
| Windows | `winget install --exact --id Microsoft.Azure.FunctionsCoreTools` |
| macOS | `brew tap azure/functions && brew install azure-functions-core-tools@4` |
| Linux | Configure Microsoft's repository for the exact distribution, then install `azure-functions-core-tools-4` |

Use Microsoft's [Core Tools installation guide](https://learn.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools). Avoid global npm installation with elevated permissions.

```text
func --version
```

The reported major version must be `4`.

### Azurite

SmartTodo's default local Functions configuration uses `UseDevelopmentStorage=true`, so local execution requires Azurite unless the generated app is configured for a real Azure Storage account. Prefer a project-local development dependency:

```text
npm install --save-dev azurite
npx azurite --version
```

See the [official Azurite documentation](https://learn.microsoft.com/azure/storage/common/storage-use-azurite).

### sqlcmd

Use the current Go-based `sqlcmd`, which supports Microsoft Entra authentication on Windows, macOS, and Linux.

| OS | Install |
|---|---|
| Windows | `winget install sqlcmd` |
| macOS | `brew install sqlcmd` |
| Linux | Use Microsoft's distribution package repository, or download the matching release archive and verify its published SHA-256 digest |

Use the [official sqlcmd installation guide](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install). Release archives are published in [microsoft/go-sqlcmd](https://github.com/microsoft/go-sqlcmd/releases); don't describe archives as signed unless a signature is actually provided.

```text
sqlcmd --version
```

### Playwright Chromium

The runner has a pinned package and lockfile in `.github/skills/journey-runner/scripts/`. From that directory:

```text
npm ci
npx playwright install chromium
```

On Linux, browser system dependencies may require an administrator-approved change:

```text
npx playwright install --with-deps chromium
```

Don't run `--with-deps` silently. Use Playwright's bundled `chromium`, not the branded `chrome` channel, which isn't available on Linux ARM64. See the [Playwright browser guide](https://playwright.dev/docs/browsers).

## SmartTodo local SQL on ARM64

The standard Microsoft SQL Server Linux container is AMD64-only. On Apple Silicon, Windows ARM64, or Linux ARM64, prefer the deployed Azure SQL database unless Docker's AMD64 emulation has already been enabled and verified. The journey runner must not install privileged QEMU/binfmt handlers automatically.

## ARM64 hosts and Azure Container Apps

Azure Container Apps expects Linux AMD64 images. On any ARM64 host, including Apple Silicon, Windows ARM64, and Linux ARM64:

1. Use an ACR cloud build targeting `linux/amd64` for deployment images.
2. Do not require local Docker, Buildx, or emulation for the deployment path.
3. Never install privileged QEMU/binfmt handlers automatically.

## Secure cross-platform secret generation

Don't require OpenSSL solely to create random values. Node.js is already a prerequisite for portable hooks:

```text
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Copy the result into the relevant `azd env set` command. Don't place generated secrets in committed files or shell history on shared machines.

## Documentation and shell portability

- Use `text` fences for single executable commands that are identical across shells.
- For stateful variables, loops, pipelines, or line continuations, provide both `bash` and `powershell` examples or replace them with a portable Node.js script.
- Required lifecycle hooks must be CommonJS JavaScript (`.js`) or TypeScript (`.ts`) files referenced directly from `azure.yaml`; azd 1.28.0 rejects `.mjs` hook paths.
- Invoke child processes with argument arrays and don't build interpolated shell strings. On macOS and Linux, execute `az` and `azd` directly. On Windows, use the repository's static `powershell.exe` JSON-payload launcher so Node does not try to execute Azure CLI `.cmd` shims directly.
