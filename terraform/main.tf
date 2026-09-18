# Applies exactly the grants in ../docs/granting-access.md and
# ../grant-nodrik-access.sh — no more. Read those first; this module is
# the third rendering of the same steps (ADR-0003 in the product repo),
# not a different decision about what Nodrik gets. `var.families` is the
# script's `--family`: optional, empty by default, one more read-only
# custom role per service you name (ADR-0055 in the product repo).
#
# What this module does NOT do, deliberately:
#   - it never touches the tenant topic's IAM policy. Granting the
#     customer's Cloud Monitoring service agent publish rights on that
#     topic happens on Nodrik's side, against Nodrik's own hub project,
#     once you send us the project number (see the "project_numbers"
#     output) — a customer's Terraform run has no access to grant that
#     even if it tried.
#   - it never sets a provider block or a backend. This is a module, not
#     a root config: your own root module supplies the google provider,
#     exactly as examples/single-project does.

locals {
  # The complete access list. Four Google-managed, read-only roles —
  # matching grant-nodrik-access.sh's ROLES array precisely.
  roles = [
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/errorreporting.viewer",
    "roles/run.viewer",
  ]

  # One binding per (project, role) pair, keyed so a change to one
  # project or one role never forces a diff on any other.
  project_role_bindings = {
    for pair in setproduct(var.project_ids, local.roles) :
    "${pair[0]}/${pair[1]}" => {
      project_id = pair[0]
      role       = pair[1]
    }
  }

  # The OPTIONAL family roles — the same table as grant-nodrik-access.sh's
  # family_permissions and FAMILY_GRANTS in the product repo
  # (packages/control/src/grants.ts), which the product's pre-flight and
  # verifier check against. Every permission is a get or a list; that is
  # the whole reason these are custom roles rather than Google's
  # predefined viewers (cloudsql.viewer can export the database,
  # compute.viewer can read a VM's serial console, container.clusterViewer
  # can connect to the cluster). Keep the three in step.
  family_roles = {
    "managed-sql" = {
      role_id     = "${var.product_slug}ManagedSqlConfigViewer"
      title       = "${var.product_name} Cloud SQL configuration viewer"
      permissions = ["cloudsql.instances.get", "cloudsql.instances.list"]
    }
    "cache" = {
      role_id = "${var.product_slug}CacheConfigViewer"
      title   = "${var.product_name} Memorystore configuration viewer"
      permissions = [
        "redis.instances.get", "redis.instances.list",
        "memorystore.instances.get", "memorystore.instances.list",
        "memcache.instances.get", "memcache.instances.list",
      ]
    }
    # The GKE API only — container.clusters.get and .list. We never
    # connect to your cluster, so no permission that reaches it is here.
    "kubernetes" = {
      role_id     = "${var.product_slug}KubernetesConfigViewer"
      title       = "${var.product_name} GKE configuration viewer"
      permissions = ["container.clusters.get", "container.clusters.list"]
    }
    "compute" = {
      role_id = "${var.product_slug}ComputeConfigViewer"
      title   = "${var.product_name} Compute Engine configuration viewer"
      permissions = [
        "compute.instances.get", "compute.instances.list",
        "compute.instanceGroupManagers.list", "compute.autoscalers.list",
        "compute.zoneOperations.list",
      ]
    }
    "networking" = {
      role_id = "${var.product_slug}NetworkingConfigViewer"
      title   = "${var.product_name} load balancing configuration viewer"
      permissions = [
        "compute.backendServices.get", "compute.backendServices.list",
        "compute.regionBackendServices.get", "compute.regionBackendServices.list",
        "compute.urlMaps.list", "compute.regionUrlMaps.list",
        "compute.healthChecks.get", "compute.regionHealthChecks.get",
      ]
    }
  }

  # Rendered here rather than as a variable default, because Terraform
  # will not let one variable's default reference another.
  channel_display_name = coalesce(
    var.channel_display_name,
    "${var.product_name} (@${var.agent_name})",
  )

  # One role definition and one binding per (project, family) the
  # customer named. Nothing is created for a family not in var.families.
  project_family_roles = {
    for pair in setproduct(var.project_ids, var.families) :
    "${pair[0]}/${pair[1]}" => {
      project_id = pair[0]
      family     = pair[1]
    }
  }
}

# Additive per-member bindings, not authoritative role bindings — the
# same shape as `gcloud projects add-iam-policy-binding`. This never
# removes another principal already holding one of these four roles,
# which an authoritative `google_project_iam_binding` would.
resource "google_project_iam_member" "nodrik_viewer" {
  for_each = local.project_role_bindings

  project = each.value.project_id
  role    = each.value.role
  member  = "serviceAccount:${var.tenant_service_account}"

  # `--condition=None` in the script and the doc means "no IAM
  # condition" — the default for this resource when condition is unset.
}

# The optional family roles (docs/granting-access.md § Optional): the
# definition first, then an additive binding that references it so the
# plan orders them. `terraform destroy` removes both — the module is the
# exact reverse of itself, and a role definition is the one artefact of
# ours a grant would otherwise leave in the project.
resource "google_project_iam_custom_role" "nodrik" {
  for_each = local.project_family_roles

  project     = each.value.project_id
  role_id     = local.family_roles[each.value.family].role_id
  title       = local.family_roles[each.value.family].title
  description = "Read-only: what ${var.product_name}'s ${each.value.family} configuration tool calls, and nothing else. Managed by the ${var.product_slug}-onboarding Terraform module — ${var.product_url}"
  permissions = local.family_roles[each.value.family].permissions
  stage       = "GA"
}

resource "google_project_iam_member" "nodrik_family" {
  for_each = local.project_family_roles

  project = each.value.project_id
  role    = google_project_iam_custom_role.nodrik[each.key].name
  member  = "serviceAccount:${var.tenant_service_account}"
}

# Step 2 of the doc/script: one Pub/Sub-type notification channel per
# project, pointing at the tenant topic. Terraform's own idempotency is
# the equivalent of the script's "does one already exist" check — a
# second `apply` updates this resource in place rather than creating a
# second channel, so there is nothing extra to guard here.
resource "google_monitoring_notification_channel" "nodrik" {
  for_each = var.project_ids

  project      = each.value
  display_name = local.channel_display_name
  type         = "pubsub"

  labels = {
    topic = var.tenant_topic
  }

  # revoke-nodrik-access.sh always deletes with --force: a channel
  # cannot be deleted while an alert policy still references it, and the
  # policies referencing it are the customer's own — left alone, only
  # unlinked. `terraform destroy` needs the same permission to be the
  # exact reverse of `apply` rather than leaving the one thing removal
  # exists to remove.
  force_delete = true
}

# Read-only; needed only to hand you the same project numbers the script
# prints at the end of its run, which you still send to us by hand (see
# the module README's "one thing left" section).
data "google_project" "target" {
  for_each   = var.project_ids
  project_id = each.value
}
