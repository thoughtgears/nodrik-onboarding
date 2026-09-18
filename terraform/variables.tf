# Every input here maps directly onto a value the doc and the script also
# ask for — see ../docs/granting-access.md. Nothing is inferred and
# nothing has a default that grants access on your behalf.

variable "tenant_service_account" {
  description = <<-EOT
    The service account Nodrik gave you during onboarding, e.g.
    tenant-acme-prod@tg-shard-N.iam.gserviceaccount.com. This is the
    ONLY principal these resources ever grant anything to.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.iam\\.gserviceaccount\\.com$", var.tenant_service_account))
    error_message = "tenant_service_account must look like a service account, e.g. tenant-acme-prod@tg-shard-N.iam.gserviceaccount.com."
  }
}

variable "tenant_topic" {
  description = <<-EOT
    Your alert intake topic, as the full resource path Nodrik gave you,
    e.g. projects/tg-hub-N/topics/tenant-acme-prod-alerts. Only the
    notification channel's label points at this — nothing in this module
    grants access to the topic itself, on either side.
  EOT
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/topics/[^/]+$", var.tenant_topic))
    error_message = "tenant_topic must be a full path (projects/PROJECT/topics/TOPIC), e.g. projects/tg-hub-N/topics/tenant-acme-prod-alerts."
  }
}

variable "project_ids" {
  description = <<-EOT
    The GCP projects Nodrik should be able to investigate. One set of
    grants (the four roles) and one notification channel are created per
    project — the same shape as running grant-nodrik-access.sh once per
    project id.
  EOT
  type        = set(string)

  validation {
    condition     = length(var.project_ids) > 0
    error_message = "project_ids must contain at least one project id."
  }
}

# ---------------------------------------------------------------------
# Product identity. These four are the ONLY place the product's name
# appears in this module. Everything the customer sees in their own IAM
# console — custom role ids, titles and descriptions, and the
# notification channel's name — renders from them, so a rename is a
# change to these defaults and nothing else.
#
# They are deliberately separate from the project ids inside
# tenant_service_account and tenant_topic. A GCP project id is immutable,
# so it never carries the brand; these are mutable, so they always do.
# ---------------------------------------------------------------------

variable "product_name" {
  description = <<-EOT
    Display form of the product name, as someone reading their own IAM
    policy should see it. Appears in every custom role title and
    description this module creates in your project.
  EOT
  type        = string
  default     = "Nodrik"

  validation {
    condition     = length(trimspace(var.product_name)) > 0
    error_message = "product_name must not be empty."
  }
}

variable "product_slug" {
  description = <<-EOT
    Identifier form of the product name. Prefixes the custom role ids
    ("nodrik" gives nodrikManagedSqlConfigViewer) and names the
    onboarding repository cited in each role's description. Lower-case
    letters and digits only: a custom role id must be a valid
    identifier, and cannot be changed once the role exists.
  EOT
  type        = string
  default     = "nodrik"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,20}$", var.product_slug))
    error_message = "product_slug must start with a lower-case letter and contain only lower-case letters and digits (2-21 characters)."
  }
}

variable "product_url" {
  description = <<-EOT
    Where someone who finds these roles in their IAM policy months from
    now can read what they are. Appears in every role description.
  EOT
  type        = string
  default     = "https://nodrik.dev"
}

variable "agent_name" {
  description = <<-EOT
    The agent's handle. Used only to render the default notification
    channel name; set channel_display_name directly to override.
  EOT
  type        = string
  default     = "nodrik"
}

variable "channel_display_name" {
  description = <<-EOT
    Display name for the Cloud Monitoring notification channel. Leave
    null to render "<product_name> (@<agent_name>)", so that a rename
    carries here automatically. Terraform cannot reference one variable
    from another's default, which is why this is null rather than a
    literal and is resolved in locals.
  EOT
  type        = string
  default     = null
}

variable "families" {
  description = <<-EOT
    Optional. The services whose SETTINGS Nodrik may read as well as
    their telemetry — one custom, read-only role per family, defined in
    each project and bound to tenant_service_account. Empty (the default)
    applies exactly the four roles above and nothing else. Each family
    maps to one role holding exactly the get/list permissions the
    product's tool calls (see local.family_roles in main.tf):
      managed-sql -> nodrikManagedSqlConfigViewer  (Cloud SQL settings and flags)
      cache       -> nodrikCacheConfigViewer       (Memorystore settings)
      kubernetes  -> nodrikKubernetesConfigViewer  (GKE cluster settings from the GKE API — never the cluster)
      compute     -> nodrikComputeConfigViewer     (Compute Engine instance and group settings)
      networking  -> nodrikNetworkingConfigViewer  (load balancer backend health and configuration)
    Defining a role needs iam.roles.create on the project.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for family in var.families :
      contains(["managed-sql", "cache", "kubernetes", "compute", "networking"], family)
    ])
    error_message = "families must be a subset of: managed-sql, cache, kubernetes, compute, networking."
  }
}
