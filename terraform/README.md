# Terraform module

The Terraform-native way to apply Nodrik's access grants — the same
grants as [`../docs/granting-access.md`](../docs/granting-access.md) and
[`../grant-nodrik-access.sh`](../grant-nodrik-access.sh), no more.
Read the doc first: it is the spec, and this module is a mechanical
rendering of it, not a separate decision about what Nodrik gets.

## What it applies

On every project you list, this module:

1. grants `tenant_service_account` the four read-only roles below
2. creates one Pub/Sub-type Cloud Monitoring notification channel
   labelled with `tenant_topic`

| Role | What it reads |
| --- | --- |
| `roles/logging.viewer` | Log entries, and the Admin Activity audit log |
| `roles/monitoring.viewer` | Metrics and alert policies |
| `roles/errorreporting.viewer` | Error groups |
| `roles/run.viewer` | Cloud Run service and revision configuration, environment-variable values included |

`run.viewer` returns the full revision spec, environment-variable values
included; Nodrik keeps the names and discards the values, but the
permission allows reading them — see
[the doc](../docs/granting-access.md#1-grant-the-four-read-only-roles).

Optionally, per family you list in `families`, one more read-only
**custom** role is defined in the project and bound — see
[Optional: a configuration role per service](../docs/granting-access.md#optional-a-configuration-role-per-service)
for what each reads, what the permission itself allows, and what Nodrik's
tool discards. `terraform destroy` removes the definition with the
binding.

That is the complete list — this module never requests, and never
grants, anything beyond it. It also never touches the tenant topic's own
IAM policy: granting your projects' Cloud Monitoring service agent
publish rights on that topic happens on Nodrik's side, against our hub
project, once you send us the `project_numbers` output below. A
customer's Terraform run has no access to grant that even if this module
tried to.

## Usage

```hcl
module "nodrik" {
  source = "github.com/thoughtgears/nodrik-onboarding//terraform?ref=v0.2.1"

  tenant_service_account = "tenant-acme-prod@tg-shard-N.iam.gserviceaccount.com"
  tenant_topic           = "projects/tg-hub-N/topics/tenant-acme-prod-alerts"
  project_ids            = ["my-production-project"]

  # Optional — omit for the four roles and nothing else.
  families = ["managed-sql"]
}

output "nodrik_project_numbers" {
  value = module.nodrik.project_numbers
}
```

**Pin `ref` to a tag rather than tracking a branch**, so an upstream
change never lands in your plan unannounced. `v0.2.1` is the current
release; [`../CHANGELOG.md`](../CHANGELOG.md) says what changed at each
tag.

A commit SHA works too and is equally immutable, if you would rather not
trust that a tag stays put.

A working, minimal root module is in
[`../examples/single-project`](../examples/single-project).

## Inputs

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| `tenant_service_account` | `string` | yes | The service account Nodrik gave you, e.g. `tenant-acme-prod@tg-shard-N.iam.gserviceaccount.com`. The only principal these resources ever grant anything to. Validated against that shape. |
| `tenant_topic` | `string` | yes | Your alert intake topic as a full resource path, e.g. `projects/tg-hub-N/topics/tenant-acme-prod-alerts`. Validated against that shape. |
| `project_ids` | `set(string)` | yes | The GCP projects Nodrik should investigate. One set of grants and one notification channel are created per project. |
| `channel_display_name` | `string` | no | Notification channel display name. Defaults to `"Nodrik (@nodrik)"`, matching the doc and the script. |
| `families` | `set(string)` | no | Optional configuration roles, one per service: a subset of `managed-sql`, `cache`, `kubernetes`, `compute`, `networking`. Default `[]` — exactly the four roles above. Defining a role needs `iam.roles.create` on the project. |

## Outputs

| Name | Description |
| --- | --- |
| `notification_channel_ids` | Map of `project_id => notification channel resource name` (`projects/<id>/notificationChannels/<n>`). Attach these to the alert policies you want investigated. |
| `granted_roles` | Every role granted — the four, plus one custom role per project and family. The complete access list, to check for yourself. |
| `family_roles` | The custom roles this module defined, per project and family, with their permissions. Empty when `families` is. |
| `project_numbers` | Map of `project_id => project number`. Send these to Nodrik: see "What it applies" above. |

## The known gotcha: domain-restricted sharing

If your org enforces `iam.allowedPolicyMemberDomains`, `apply` fails on
the first `google_project_iam_member` with a `FAILED_PRECONDITION` error
that does not mention the policy by name. This is the same failure the
script and the doc describe, just surfaced by Terraform instead of
`gcloud`.

See [`../docs/domain-restricted-sharing.md`](../docs/domain-restricted-sharing.md)
for the two ways to allow the grant, a comparison to help you choose,
and an optional module —
[`../terraform/org-policy-exception`](org-policy-exception) — for the
narrower one. It is deliberately a **separate** module: applying it
needs `roles/orgpolicy.policyAdmin` (or the `orgpolicy.policy.set`
permission) on whichever level you set it at — organisation, folder, or
a single project; that module's README recommends project or folder,
which keeps the ask close to this module's own project-scoped viewer
roles. A reviewer approving this module should never be handed
org-policy access by accident, whichever level someone else picks for
the exception. Once the exception is in place, `apply` here again — the
resources are idempotent, so re-running picks up exactly where it
stopped.

We deliberately do not ask this module to pre-check the policy, for the
same reason the script does not: reading it needs the Org Policy API
enabled, and the customer most likely to hit this — one project, no org
access — is also the one least able to enable it safely.

## Removing Nodrik

```bash
terraform destroy
```

The exact reverse of `apply`: it removes the four role bindings, any
family role binding and its role definition, and deletes the
notification channel. The channel resource is configured
with `force_delete = true` for the same reason
`revoke-nodrik-access.sh` always deletes with `--force`: Cloud Monitoring
refuses to delete a channel still referenced by an alert policy, and the
policies referencing it are the customer's own. `force_delete` deletes
the channel and unlinks it from those policies; the policies survive and
keep firing, just with one fewer notification target — which is what
removing Nodrik means. Your alert policies themselves are never touched.

You do not have to run this for your data to be deleted. Our side of the
teardown — the service account that could read your projects, your
stored credentials, your investigation history — runs on our schedule
and does not wait for you. `terraform destroy` removes the permissions
you granted; ours removes the identity they were granted to. Either
alone stops Nodrik reading anything.

## Registry

This module is not published to the Terraform Registry. Registry listing
needs a repo named `terraform-google-nodrik-onboarding`; the decision as
of this module's first version is one public repo holding all three
onboarding paths (doc, script, module), sourced from GitHub as shown
above. Registry publication is deferred, not ruled out — extracting this
directory into its own repo later is a rename plus a tag, not a rewrite.
