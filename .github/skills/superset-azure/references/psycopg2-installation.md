# psycopg2-binary Installation for Superset on AKS

## ⚠️ Critical: psycopg2-binary Installation

The official `apache/superset:latest` image does NOT include psycopg2 for PostgreSQL connections. Without it, Superset falls back to SQLite.

### The Problem
- The image's virtualenv at `/app/.venv` is read-only
- `pip install --user` installs to a location the venv Python doesn't see
- PYTHONPATH alone doesn't work because the venv ignores it

### The Solution
1. Install psycopg2-binary to a writable emptyDir volume:
   ```bash
   pip install psycopg2-binary --target=/psycopg2-lib
   ```

2. Set PYTHONPATH to include this directory in BOTH init and main containers:
   ```yaml
   env:
   - name: PYTHONPATH
     value: "/psycopg2-lib"
   ```

3. Mount the emptyDir in both containers so init installs it and main uses it:
   ```yaml
   volumes:
   - name: psycopg2-install
     emptyDir: {}
   ```

### Verification

Run `node .github/scripts/verify-superset.mjs`; it fails if the pod isn't Ready/Running, PostgreSQL evidence is absent, SQLite appears in logs, or `/health` doesn't return HTTP 200. To isolate the package import, run `kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"`.
