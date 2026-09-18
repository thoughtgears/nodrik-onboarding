# Route 1 from ../../docs/domain-restricted-sharing.md: a tag-scoped
# exception to constraints/iam.allowedPolicyMemberDomains (domain-
# restricted sharing), narrowed to the one project being connected
# rather than the whole organisation. Four resources:
#
#   1. an org-level tag key                 (google_tags_tag_key)
#   2. one tag value under it                (google_tags_tag_value)
#   3. that value bound to var.project_id    (google_tags_tag_binding)
#   4. the policy itself, whose exception     (google_org_policy_policy)
#      rule only fires on a resource carrying that tag
#
# This is deliberately its own module, never folded into ../ (the four
# read-only VIEWER roles applied in the customer's own project). That
# module needs no organisation-level access at all; this one needs
# roles/orgpolicy.policyAdmin (or an equivalent custom role) on whichever
# node var.parent names — a far larger ask at organisation level, and a
# reviewer approving one should never be handed the other by accident.
# Read this module's README before running it: it edits organisation
# policy, and it has not been exercised against an organisation that
# enforces the constraint — see the README's "Status" section.
#
# What this module does NOT do:
#   - it never sets a provider block or a backend, same as ../.
#   - it never widens the restriction beyond var.project_id. Everything
#     outside the tagged project keeps exactly the allowlist that already
#     applied to it, unchanged — see "How the rule content varies by
#     level" below and in the README.
#   - it never touches the four viewer-role grants — that is ../, a
#     separate `module` block in your root configuration.

locals {
  # The namespaced tag key name org-policy conditions reference, e.g.
  # "123456789012/nodrik" — matches Google's own documented shape for
  # resource.matchTag()'s first argument (the tag key's OWN parent
  # organisation id, independent of var.parent — see variables.tf).
  tag_key_namespaced = "${var.organization_id}/${var.tag_key_short_name}"

  # Whether the exception policy is being set at the organisation itself,
  # versus a folder or project beneath it. This is the one switch that
  # decides the rule shape below — see "How the rule content varies by
  # level".
  is_organization = can(regex("^organizations/", var.parent))
}

# Always at the ORGANISATION, never at var.parent directly — a tag key
# cannot be created under a folder, and Google's own guidance for
# tag-scoped organisation policies ("Setting an organization policy with
# tags") creates the tag key at the organisation regardless of which
# level the policy itself applies at. See variables.tf's organization_id
# for the reasoning in full.
resource "google_tags_tag_key" "nodrik" {
  parent      = "organizations/${var.organization_id}"
  short_name  = var.tag_key_short_name
  description = "Marks a project as exempted from domain-restricted sharing for Nodrik's tenant service account. Managed by the nodrik-onboarding Terraform module (terraform/org-policy-exception)."
}

resource "google_tags_tag_value" "allowed" {
  parent      = google_tags_tag_key.nodrik.id
  short_name  = var.tag_value_short_name
  description = "Bound to the one project connecting Nodrik. Removing this binding removes the exception for that project without touching the policy rule itself."
}

# Read-only; needed to bind the tag by resource name, which the Tag
# Bindings API expects in //cloudresourcemanager.googleapis.com/projects/
# <NUMBER> form — the project id alone is not accepted here.
data "google_project" "target" {
  project_id = var.project_id
}

# A project is a global resource, so no `location` is needed on the
# binding — that field is only required for regional or zonal resources
# (Google's own google_tags_tag_binding documentation).
resource "google_tags_tag_binding" "project" {
  parent    = "//cloudresourcemanager.googleapis.com/projects/${data.google_project.target.number}"
  tag_value = google_tags_tag_value.allowed.id
}

# The policy itself, set at var.parent. THIS RESOURCE OWNS THE WHOLE
# POLICY OBJECT for constraints/iam.allowedPolicyMemberDomains at that
# node — the Organization Policy Service has no concept of "add one more
# rule"; every apply (like every `gcloud org-policies set-policy`)
# replaces the complete rule set at that node. That is the reason the
# rule content below differs by level, not a stylistic choice:
#
# How the rule content varies by level
# --------------------------------------
# ORGANISATION (var.parent = organizations/<id>): the root of the
# hierarchy — there is no parent policy to inherit FROM, so REPLACING
# the rule set at this node means replacing the WHOLE effective policy.
# Two rules, both required:
#   1. conditional on the tag  -> allow_all = true (lift the restriction
#      entirely, but only for the one tagged resource)
#   2. unconditional fallback  -> allowed_values = var.existing_allowed_values
#      (restate exactly what was already enforced everywhere else)
# Rule 2 is not optional. Omitting it does not fall back to "whatever
# was there before" — it replaces the policy with rule 1 alone, which
# lifts domain-restricted sharing for every resource in the organisation
# that is untagged and matches no rule, not just the one meant to be
# exempted. var.existing_allowed_values exists, and has no default, for
# exactly this reason.
#
# FOLDER or PROJECT (var.parent = folders/<id> or projects/<id>):
# inherit_from_parent = true, and ONE rule only:
#   1. conditional on the tag -> allow_all = true
# Nothing is being replaced here — inherit_from_parent means every
# resource under this node that is NOT tagged keeps inheriting whatever
# the organisation (or an intermediate folder) already enforces,
# unchanged. There is no equivalent to rule 2 above because there is
# nothing local to restate; var.existing_allowed_values must be left
# empty at this level (enforced below) because a value here would have
# nothing to attach to and would be silently ignored by the API.
#
# WHAT `allow_all = true` ACTUALLY MEANS: on the tagged resource, ANY
# principal can be granted a role there — not only Nodrik's tenant
# service account. The tag is what scopes this exception, not a
# principal allowlist (unlike Route 2, which names Nodrik's customer id
# specifically and applies it organisation-wide). Bind the tag only to
# the one project you mean to expose this way, and do not reuse
# var.tag_key_short_name/var.tag_value_short_name for anything else.
#
# EXISTING POLICY OBJECT: if one already exists at var.parent — likely
# at organisation level, since that is the level Google enforces the
# constraint on by default; less likely at folder or project level,
# where an explicit override is uncommon unless you set one yourself —
# Terraform will not silently adopt it; `apply` fails with the API's
# ALREADY_EXISTS rather than updating it. Import it first; see the
# README's "Before your first plan" section for how to check which case
# you are in and the import command.
resource "google_org_policy_policy" "domain_restricted_sharing_exception" {
  name   = "${var.parent}/policies/iam.allowedPolicyMemberDomains"
  parent = var.parent

  spec {
    # Only meaningful for list constraints (this one is) — false at
    # organisation level is a no-op (there is no parent to inherit from
    # there anyway); explicit at every level so the intent reads
    # directly off this resource rather than off which level you are at.
    inherit_from_parent = !local.is_organization

    # The exception rule — present at every level.
    rules {
      condition {
        expression = "resource.matchTag('${local.tag_key_namespaced}', '${var.tag_value_short_name}')"
      }
      allow_all = true
    }

    # The unconditional fallback rule — organisation level only. See
    # "How the rule content varies by level" above.
    dynamic "rules" {
      for_each = local.is_organization ? [1] : []
      content {
        values {
          allowed_values = var.existing_allowed_values
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !local.is_organization || length(var.existing_allowed_values) > 0
      error_message = "existing_allowed_values is required and must be non-empty when parent is organizations/<id>. Without it, this policy would replace your organisation's domain-restricted-sharing allowlist with nothing but the tagged resource's exception — lifting the restriction organisation-wide for every untagged resource, rather than narrowing it to one project. Read your current allowlist first (see the variable's description) and pass it here."
    }
    precondition {
      condition     = local.is_organization || length(var.existing_allowed_values) == 0
      error_message = "existing_allowed_values must be left empty when parent is folders/<id> or projects/<id>. At that level this policy sets inherit_from_parent = true and adds only the conditional exception rule — there is no unconditional rule for a value here to belong to, so it would be silently ignored rather than applied. Leaving it non-empty would make you believe something was preserved that was never written anywhere."
    }
  }
}
