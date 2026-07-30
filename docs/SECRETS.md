AnyCloud secret protection
==========================
1. scripts/scan-secrets.ps1 - run: powershell -File scripts/scan-secrets.ps1
2. Enable hook (once per clone):
   git config core.hooksPath .githooks
3. API keys belong only in AnyCloud Runtime API keys & secrets (session).
   Never put them in k8s/configmap.yaml or Non-secret environment variables.
4. Kubernetes: deploy injects keys into Secret <app>-api-keys at runtime;
   Deployment mounts them via envFrom.secretRef (optional: true).
