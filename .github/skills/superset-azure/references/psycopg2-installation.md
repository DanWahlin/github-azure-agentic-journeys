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
```bash
# Check if using PostgreSQL (should show PostgresqlImpl)
kubectl logs -n superset <pod> -c superset | grep -i impl

# Verify psycopg2 is installed
kubectl exec -n superset <pod> -c superset -- python -c "import psycopg2; print('OK')"
```
