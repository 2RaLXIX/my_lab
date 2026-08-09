# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

GitOps source-of-truth for a single-node **k3s** cluster running on a Raspberry Pi 4 (8GB RAM, 490GB SSD). There is no application code here — this repo only contains Argo CD `ApplicationSet`/`Application` manifests, Helm `values.yaml` overrides, and raw Kubernetes YAML. Reconciliation is done entirely by Argo CD watching this repo (`https://github.com/2RaLXIX/my_lab.git`); nothing is applied by CI or by hand-run scripts.

There is no build, lint, or test tooling in this repo (no Makefile, no CI workflow, no README). The only "correctness check" is whether Argo CD can parse and sync a given path, and whether `kubectl`/`helm` accept the resulting manifests.

## The app-of-apps pattern

Two root `ApplicationSet`s in `applicationsets/` use the Argo CD **git files generator** to turn files under `apps/` into Argo CD `Application`s. Adding a new app means adding a correctly-named file under `apps/<category>/<app-name>/` — nothing needs to be registered elsewhere.

- **`applicationsets/apps.yaml`** (`apps-simple`) — globs `apps/**/appset.yaml`. Each match becomes a directory-type Application pointing at that folder (`path: '{{.path.path}}'`). The app name is the folder's basename. The matched file's only required key is `namespace:`. If the folder also has a `kustomization.yaml`, Argo CD applies it via Kustomize; otherwise it applies the raw YAML in the folder directly.
- **`applicationsets/apps-charts.yaml`** (`apps-charts`) — globs `apps/**/appset-chart.yaml`. Each match becomes a **3-source** Application: (1) the Helm chart named in the file (`chart.repoURL`/`chart.name`/`chart.targetRevision`) with values from `$values/<path>/values.yaml` sitting next to the `appset-chart.yaml`, (2) this repo as the `values` ref source, (3) this repo again at `extraManifestsPath` for any extra raw manifests (ClusterIssuers, ingresses, secrets, etc.) to apply alongside the chart. The Application name is `{{ index .path.segments 1 }}-{{ .path.basename }}` (i.e. `<category>-appset-chart`).

Both ApplicationSets set `syncPolicy.automated.{prune,selfHeal}: true` and `CreateNamespace=true` — everything is fully auto-synced and auto-pruned. There is no manual "argocd app sync" step in the normal workflow; committing to `main` is the deploy action.

**Filename matching is exact and glob-based — this is the most common failure mode in this repo.** A file that is almost-but-not-quite named `appset.yaml` / `appset-chart.yaml` (wrong extension, leading dot, trailing suffix) silently never becomes an Application — no error is raised anywhere, the app just never deploys. When adding or debugging an app, always verify the file is literally named `appset.yaml` or `appset-chart.yaml`, not a variant.

## Directory layout

```
apps/<category>/<app-name>/
  appset.yaml           # plain-manifest apps: just `namespace: <ns>`
  appset-chart.yaml      # helm-chart apps: chart.{repoURL,name,targetRevision}, namespace, extraManifestsPath
  values.yaml             # helm values for chart apps (referenced via extraManifestsPath sibling)
  kustomization.yaml      # optional, for plain-manifest apps with multiple files
  manifests/              # extra raw manifests applied alongside a helm chart (extraManifestsPath target)
  *.yaml                  # deployment/service/ingress/pvc/secret/etc for plain-manifest apps
```

Categories currently in use: `security` (sealed-secrets), `networking` (cert-manager, ingress-nginx, wg-easy), `monitoring` (kube-prometheus-stack), `registry` (docker-registry), `utilities` (uptime-kuma), `cloudnative-pg` (operator + a Postgres `Cluster` CR for Gitea), `gitea`, `valkey` (Gitea's redis-compatible cache/session store, deployed into the `gitea` namespace on purpose — see `apps/gitea/manifests/configmap.yaml`). `apps/pki`, `apps/storage`, `apps/backup` exist as empty placeholder directories for future apps. `bootstrap/argocd` and `docs/` are also currently empty — there is no committed bootstrap procedure for installing Argo CD itself, and no written documentation yet.

## Known inconsistencies to be aware of

- `apps/networking/wg-easy/.appset-chart.yaml` has a leading dot — it does **not** match the `apps-charts` glob and is therefore not actually deployed by Argo CD despite being fully configured.
- `apps/networking/ingress-nginx/appset.yaml.tmp` has a `.tmp` suffix — same problem, and the file only contains a `namespace:` key anyway (no chart source), so ingress-nginx's Argo CD wiring is incomplete either way.
- `apps/networking/cert-manager/clusterissuer.yaml` lives at the app root, but `extraManifestsPath` for that app points at `apps/networking/cert-manager/manifests/` (which only has a placeholder file). The ClusterIssuer is therefore **not** managed via GitOps and must have been applied by hand.
- Several `Secret` manifests are committed in plaintext with real credentials (`apps/gitea/manifests/secret.yaml`, `apps/cloudnative-pg/cluster/secret.yaml`), even though the `sealed-secrets` chart is installed. No `SealedSecret` resources exist anywhere in the repo (`apps/security/sealed-secrets/manifests/` only has a `.gitkeep`) — sealed-secrets is installed but unused.

When asked to fix or extend this repo, treat the above as real bugs, not intentional design — flag them rather than silently working around them.
