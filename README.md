# Secure Deployment of a Containerized Node.js App on Google Cloud (DevSecOps)

A REST API (Node.js/Express) backed by Cloud SQL (PostgreSQL), deployed to
Cloud Run through a GitHub Actions CI/CD pipeline, with all infrastructure
provisioned by Terraform.

---

## Repo layout

```
app/                      Node.js REST API + Dockerfile + tests
terraform/
  modules/                 network, cloudsql, secrets, iam, cloudrun, monitoring
  environments/prod/       root config that wires the modules together
.github/workflows/
  ci.yml                   lint, tests, dependency + image + secret scans, terraform fmt/validate/lint
  cd.yml                   build, push to Artifact Registry, deploy to Cloud Run (WIF auth)
  terraform-apply.yml      plan on PR / apply on manual approval
```

---

## Architecture

```
GitHub Actions (OIDC/WIF, no keys)
        │
        ▼
Artifact Registry  ──image──►  Cloud Run service (private runtime SA)
                                     │  VPC connector (egress: private ranges only)
                                     ▼
                               VPC network / subnet
                                     │  Private Services Access (VPC peering)
                                     ▼
                          Cloud SQL (PostgreSQL, NO public IP)

Secret Manager  ◄── secrets read by Cloud Run's runtime SA only
Cloud Monitoring ── alert policies ──► Google Chat (>70%) / Email (>80% sustained)
```

Traffic between Cloud Run and Cloud SQL never touches the public internet:
Cloud SQL has `ipv4_enabled = false` (no public IP), and Cloud Run reaches
it only via the Serverless VPC Access connector over the VPC peering
created for Private Services Access.

---

## Setup & deployment steps

### 1. One-time bootstrap (see "Bootstrapping without long-lived keys" below)
A human with sufficient temporary permissions runs the first `terraform
apply` to create the VPC, Cloud SQL instance, Secret Manager secrets,
Artifact Registry repo, the two service accounts, and the Workload
Identity Federation pool/provider itself.

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars   # fill in real values, do NOT commit
terraform init
terraform plan
terraform apply
```

### 2. Wire up GitHub
After the first apply, take the Terraform outputs and set them as
repository **Variables** (not secrets, they aren't sensitive) and one
**Secret**:

| Name | Source | Type |
|---|---|---|
| `GCP_PROJECT_ID` | your project id | Variable |
| `WORKLOAD_IDENTITY_PROVIDER` | `terraform output workload_identity_provider` | Variable |
| `DEPLOYER_SA_EMAIL` | `terraform output deployer_sa_email` | Variable |
| `ALERT_EMAIL` | ops email | Variable |
| `PLACEHOLDER_IMAGE` | any valid image ref, used only for `terraform plan` before the first image exists | Variable |
| `GCHAT_WEBHOOK_URL` | Google Chat space webhook | **Secret** |

No `GCP_SA_KEY` JSON secret is needed anywhere — authentication is via
OIDC (see below).

### 3. Push the app
On push (or PR) to `staging`: **CI** runs (lint, unit tests, `npm audit`,
Trivy filesystem/image/secret scans, `terraform fmt/validate`, `tflint`,
`tfsec`). Once CI succeeds on `staging`, **CD** triggers automatically
(`workflow_run` on CI's success), builds the Docker image, pushes it to
Artifact Registry, runs the DB migration job, and updates the Cloud Run
service's image only — all other infra config stays owned by Terraform
so CD can never drift the service away from what Terraform declared.

#### Branch strategy
This exercise uses a single working branch, `staging`, for everything:
CI (`ci.yml`), CD (`cd.yml`), and the Terraform plan/apply gate
(`terraform-apply.yml`) all key off `staging`. The Terraform environment
itself is still named `prod` (`terraform/environments/prod/`) since this
is the one and only environment provisioned for the exercise — `staging`
here refers to the git branch used to drive that single environment,
not a second, separate infrastructure environment. A real multi-env
setup would give each environment (e.g. `staging`, `prod`) both its own
branch *and* its own `terraform/environments/<env>/` directory and
state file, per the "Assumptions made" section below.

### 4. Schema initialization
Handled automatically — `cd.yml` updates and executes the `*-migrate`
Cloud Run Job (`app/scripts/migrate.js`, which idempotently applies
`app/scripts/init.sql` via `CREATE TABLE IF NOT EXISTS`) before every
deploy, so a new revision never serves traffic against a schema it
doesn't expect. The job runs over the same private VPC connector path
as the app itself — the instance has no public IP, so this is
intentionally never exposed to the open internet. To run it manually
(e.g. the very first time, before any CD run) use `gcloud run jobs
execute <name_prefix>-migrate --region=<region> --wait`.

---

## Security measures taken

- **No public IP on Cloud SQL** — `ipv4_enabled = false`; reachable only
  via VPC peering + the Serverless VPC Access connector.
- **`egress = PRIVATE_RANGES_ONLY`** on the Cloud Run VPC access config —
  only RFC1918-bound traffic is routed through the connector; general
  internet egress isn't unnecessarily tunneled.
- **Explicit deny-all-ingress firewall rule** on the VPC in addition to
  the implied default, for auditability.
- **Secrets never touch code, images, or CI logs.** DB credentials are
  generated by Terraform (`random_password`), stored only in Secret
  Manager, and injected into Cloud Run as `secret_key_ref` env vars —
  Cloud Run pulls them directly from Secret Manager at container start.
  They're never written to `.env`, the Docker image, or a workflow log.
- **No primitive roles anywhere.** Two custom, minimally-scoped IAM
  roles: a runtime "secret reader" role (only
  `secretmanager.versions.access` + `secretmanager.secrets.get`) for the
  app's own identity, and a "deployer" role (only the specific
  `run.services.*`, `artifactregistry.*` permissions CD needs) for
  GitHub Actions. Neither ever holds `roles/owner`, `roles/editor`, or
  `roles/viewer`.
- **`serviceAccountUser` is scoped to one resource**, not project-wide —
  the deployer can only `actAs` the specific runtime SA, not any SA in
  the project.
- **Workload Identity Federation (OIDC)** for GitHub Actions → GCP. No
  service-account JSON key exists anywhere, so there's no long-lived
  credential to leak, rotate, or accidentally commit. The WIF provider's
  `attribute_condition` restricts token exchange to this exact repo.
- **CI-side scanning:** `npm audit` (dependency CVEs) + Trivy filesystem
  scan (source-level issues) + Trivy image scan (OS/package CVEs in the
  built container) + a dedicated Trivy secret scan against the built
  image layers + `tfsec` (IaC misconfiguration policy checks) — all set
  to fail the build on HIGH/CRITICAL findings.
- **Least-privilege container:** multi-stage Alpine build, `npm ci
  --omit=dev`, runs as a non-root uid/gid, no shell-dependent entrypoint
  tricks, `helmet` + rate limiting + a 100kb JSON body cap at the app
  layer, parameterized SQL everywhere (no string-built queries).
- **`.dockerignore` / `.gitignore`** keep `.env`, key files, and
  `.tfvars` (except the `.example` template) out of both the build
  context and version control.
- **State isolation:** Terraform state lives in a versioned GCS bucket
  (`backend.tf`), never local, never committed.
- **Deletion protection + PITR** enabled on Cloud SQL so a stray
  `terraform destroy` or `apply` can't silently drop production data.
- **Artifact Registry cleanup policy** keeps only the 10 most recent
  tagged images, limiting the pool of old (potentially vulnerable)
  images sitting around.
- **CD deploys the image only.** It never runs `terraform apply` against
  full infra credentials — it uses the narrowly-scoped deployer role, so
  even a compromised CD run can't touch IAM, networking, or Cloud SQL.

---

## Bootstrapping without long-lived keys

This is the one genuine chicken-and-egg problem: the *first* `terraform
apply` has to create the Workload Identity Federation pool/provider
itself, plus the VPC, Cloud SQL, and IAM resources — none of which the
narrowly-scoped `deployer` service account is allowed to touch (by
design, since it should only ever need `run.*` and
`artifactregistry.*`).

How to bootstrap this securely, without ever generating a long-lived SA
key:

1. A human operator authenticates locally with their own Google
   identity (`gcloud auth application-default login`), which itself can
   be an SSO/2FA-backed account — not a service account at all.
2. That operator needs `roles/owner`-equivalent *temporarily and only
   for this one bootstrap run* — in practice, a purpose-built
   `terraform-bootstrap` custom role covering exactly: `compute.*`
   (network), `sqladmin.*`, `secretmanager.*`, `iam.serviceAccounts.*`,
   `iam.workloadIdentityPools.*`, `artifactregistry.*`,
   `serviceusage.services.enable`, `resourcemanager.projects.setIamPolicy`.
   This is granted via a break-glass process (e.g. a time-boxed IAM
   binding with `google_project_iam_member` conditioned on an expiry, or
   simply removed again right after `apply` succeeds) — not left standing.
3. Run `terraform apply` once from that identity to create the WIF
   pool/provider and the two application service accounts.
4. From that point on, GitHub Actions authenticates as the `deployer`
   SA purely through WIF — no key material ever existed for it.
5. Any *future* infra change goes through `terraform-apply.yml`'s
   `plan`-on-PR / manual-`apply`-on-approval flow, still using the
   `deployer` identity's federation — if a future change needs
   permissions the deployer role doesn't have, that's a deliberate
   signal to go back to the human-bootstrap step for that one change,
   rather than quietly widening the CI identity's standing permissions.

If your organization can't use WIF at all (e.g. GitHub Enterprise
Server without outbound HTTPS to Google's OIDC endpoint), the documented
fallback is a single JSON key for a *bootstrap-only* SA, stored as a
GitHub encrypted secret, used exactly once, then deleted/rotated — never
used for routine CD.

---

## Alerting setup, explained

Two independent alert policies per metric (CPU and memory), each pointed
at a different notification channel, mirroring the requirement:

- **>70% utilization → Google Chat (warning).** `threshold_value = 0.70`,
  `duration = "0s"`, `trigger.count = 1` — fires on the very first
  datapoint above 70%. Routed to a `webhook_tokenauth` notification
  channel pointed at a Google Chat incoming webhook. This is meant to be
  a fast, low-friction heads-up, not a page.
- **>80% sustained → email (critical).** `threshold_value = 0.80`,
  `duration = "180s"` with `trigger.count = 3` on a 60s alignment period
  — requires the condition to hold across multiple consecutive
  datapoints (not a single momentary spike) before it fires, which is
  what "for subsequent datapoints" means in the brief. Routed to an
  `email` notification channel.
- A **log-based metric** (`*-5xx-errors`) counts application-level 5xx
  responses from Cloud Run request logs, giving an app-correctness
  signal alongside the resource-utilization signals — useful to extend
  with its own alert policy the same way if needed.
- `alert_strategy.auto_close = "1800s"` auto-resolves stale incidents
  instead of leaving them open forever if metrics recover quietly.

---

## Assumptions made

- Single region (`asia-south1` by default, configurable) and a single
  environment (`prod`) for this exercise; a real multi-env setup would
  duplicate `terraform/environments/` per stage with separate state.
- PostgreSQL was chosen over MySQL (either satisfies the brief); the
  `pg` driver and schema are Postgres-specific but the Terraform
  `database_version` variable makes swapping straightforward.
- Cloud Run's `ingress` is left at `INGRESS_TRAFFIC_ALL` with
  `allow_unauthenticated = false` by default (IAM-gated) so the service
  is reachable for demo/interview purposes while still requiring
  authenticated invocation; a stricter internal-only posture
  (`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` behind an internal HTTPS LB)
  is noted inline in the module as the production-hardened option.
  This trade-off is a judgment call to explain in interview, not a
  fixed answer.
- The Cloud SQL tier (`db-custom-1-3840`) and `ZONAL` availability are
  sized for a demo, not for HA production load — `REGIONAL` availability
  and a larger tier are one variable change away.
- `npm audit`/Trivy/`tfsec` thresholds are set to fail on
  HIGH/CRITICAL only, to avoid the pipeline being blocked by every LOW
  finding in a demo context; a real pipeline would tune this with a
  documented exception/waiver process instead of just lowering severity.
- The GitHub Actions "Variables" used in the workflows (`GCP_PROJECT_ID`,
  `WORKLOAD_IDENTITY_PROVIDER`, etc.) are assumed to be configured once
  in repo settings after the bootstrap `apply`, as described above.

---

## A note on how this was built

This solution was produced with AI assistance as an accelerant for
scaffolding (boilerplate Terraform/YAML, standard security patterns),
per the brief's request to minimize excessive AI use in favor of
demonstrating personal expertise — every design decision above (private
IP + connector, WIF bootstrap trade-off, custom IAM roles, the two-tier
alerting) should be treated as something to be defended and modified
live in discussion, not just read aloud.
