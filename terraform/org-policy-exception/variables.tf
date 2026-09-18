# Every input here maps onto a value this module needs to build ONE
# thing: a tag-scoped exception to constraints/iam.allowedPolicyMemberDomains,
# narrowed to a single project. Read ../org-policy-exception/README.md
# before setting any of these — this module edits organisation policy,
# and needs roles/orgpolicy.policyAdmin (or an equivalent custom role) on
# whichever node var.parent names, to apply.

variable "parent" {
  description = <<-EOT
    Where the exception POLICY OBJECT is set — the administrative node
    this module edits org policy on. Exactly one of:

      organizations/<numeric organisation id>
      folders/<numeric folder id>
      projects/<project id>

    No default: a module that edits organisation policy must never pick
    this implicitly. This is not a detail — the rule content this module
    generates is DIFFERENT at organisation level than at folder or
    project level (see main.tf and the README's "How the rule content
    varies by level" section), because only the organisation node has no
    parent to inherit an existing restriction FROM.

    See the README's "Choosing a level" section for why Nodrik
    recommends project or folder over organisation: either asks whoever
    applies this for `orgpolicy.policy.set` on ONE node rather than the
    whole organisation, and a mistake here can only reach resources
    under that one node, never anything outside it. Organisation is the
    escape hatch for an org that centralises policy management, not the
    default choice.
  EOT
  type        = string

  validation {
    condition = (
      can(regex("^organizations/[0-9]+$", var.parent)) ||
      can(regex("^folders/[0-9]+$", var.parent)) ||
      can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.parent))
    )
    error_message = "parent must be exactly one of: organizations/<numeric id>, folders/<numeric id>, or projects/<project id>."
  }
}

variable "organization_id" {
  description = <<-EOT
    Your numeric Google Cloud organisation id, e.g. 123456789012 — get it
    with `gcloud organizations list`. Required regardless of var.parent:
    the tag key this module creates is always created at the
    ORGANISATION, never at var.parent directly. That is not this
    module's choice — Google's own guidance for tag-scoped organisation
    policies ("Setting an organization policy with tags") creates the
    tag key at the organisation and calls the numeric id it uses in the
    condition expression "the parent organization of your tag key",
    independent of which level the policy itself applies at. A tag key
    also cannot be created directly under a folder, which rules out
    deriving this from var.parent when it names a folder.

    A mistyped id here would not fail loudly: at best it targets an
    organisation that does not exist and plan fails; at worst, if the
    typo happens to resolve to a REAL organisation you have access to,
    it creates a tag key THERE instead of yours. The validation below
    can only confirm the id is numeric, and — when var.parent itself
    names an organisation — that the two agree; it cannot know which
    organisation is actually yours.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id must be the numeric organisation id from `gcloud organizations list` (e.g. 123456789012) — not a domain name, and not prefixed with \"organizations/\"."
  }

  validation {
    condition     = !can(regex("^organizations/", var.parent)) || var.parent == "organizations/${var.organization_id}"
    error_message = "when parent is organizations/<id>, organization_id must be that same id — the tag key's organisation and the policy's organisation cannot disagree."
  }
}

variable "project_id" {
  description = <<-EOT
    The one GCP project being connected to Nodrik — the resource that
    gets tagged, and therefore the resource the exception's conditional
    rule actually exempts. Independent of var.parent: parent says WHERE
    the policy object lives; project_id says WHICH resource carries the
    tag the policy's condition matches on. When var.parent is
    projects/<id>, this is typically — though the module does not
    require it — that same project.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project id: lowercase letters, digits and hyphens, 6-30 characters, starting with a letter and not ending with a hyphen."
  }
}

variable "existing_allowed_values" {
  description = <<-EOT
    Your CURRENT domain-restricted-sharing allowlist at var.parent,
    exactly as it reads today. Get it with:

      gcloud org-policies describe iam.allowedPolicyMemberDomains \
        --organization=ORGANIZATION_ID --effective \
        --format='value(spec.rules[0].values.allowedValues)'

    (substitute --folder or the default project-scoped invocation if
    var.parent names a folder or project instead).

    REQUIRED, and must be non-empty, only when var.parent is
    organizations/<id>. Setting an organisation-level policy for a list
    constraint REPLACES its entire rule set — that is how the
    Organization Policy Service works, not a choice this module makes
    (see the README's "How the rule content varies by level" section) —
    so at that level this module restates your existing allowlist as an
    unconditional fallback rule, and needs to be told what it is. A
    default here would risk silently dropping your own organisation from
    its own allowlist the first time this module ran, so there is none;
    an empty value at organisation level fails plan rather than doing
    that (see the `lifecycle.precondition` blocks in main.tf).

    MUST BE LEFT EMPTY when var.parent is folders/<id> or projects/<id>.
    At those levels the policy sets `inherit_from_parent = true` and
    adds only the conditional exception rule — nothing is being
    replaced, so there is nothing to restate, and a value here would be
    silently ignored rather than applied. The same precondition blocks
    refuse plan rather than let that happen quietly.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for value in var.existing_allowed_values :
      can(regex("^(is:)?(C[0-9A-Za-z]+|principalSet://.+)$", value))
    ])
    error_message = "each value in existing_allowed_values must look like a Google Workspace customer id (C…, optionally \"is:\"-prefixed) or an organisation principal set (…principalSet://…) — the same shapes `gcloud org-policies describe --effective` returns."
  }
}

variable "tag_key_short_name" {
  description = <<-EOT
    Short name for the organisation-level tag key this module creates.
    The default is deliberately plain — change it only if "nodrik"
    already names something else in your tag namespace.
  EOT
  type        = string
  default     = "nodrik"
}

variable "tag_value_short_name" {
  description = <<-EOT
    Short name for the tag value bound to var.project_id. Change it only
    if you want a different value under the same key for your own
    purposes — the module does not depend on this string beyond using it
    consistently between the binding and the policy condition.
  EOT
  type        = string
  default     = "allowed"
}
