# Terraform module: organisation policy exception (optional)

**This module edits an org policy object, not a project's IAM policy —
at a level you choose.** It sets a tag-scoped exception to
`constraints/iam.allowedPolicyMemberDomains` (domain-restricted sharing)
so Nodrik's tenant service account — which lives in our project, not
yours — can be granted the four viewer roles on the one project you
name, without weakening the restriction anywhere else your policy
already covers. It needs `roles/orgpolicy.policyAdmin` (Google's
"Organization Policy Administrator" predefined role — or an equivalent
custom role granting `orgpolicy.policy.set`) on **whichever node
`var.parent` names**: the organisation, a folder, or a single project.
See [Choosing a level](#choosing-a-level) below — we recommend project
or folder over organisation, because both the permission ask and the
blast radius of a mistake shrink to that one node.

Even at the narrowest (project) level this is a different ask from
[`../`](../) — the module that applies the four viewer roles themselves
needs no organisation-policy access at all, at any level, because it
only ever touches project IAM bindings. That is why this is its own
module and will never be folded into that one: a reviewer approving the
narrow grant should never be handed the org-policy one by accident, even
when both now happen to name the same project.

You only need this at all if your organisation enforces
[domain-restricted sharing](https://cloud.google.com/resource-manager/docs/organization-policy/restricting-domains)
and you hit `FAILED_PRECONDITION` granting the four roles. Most
organisations do not enforce it, and if yours does not, none of this
applies to you — skip straight to [`../`](../).

**You can do this by hand instead — see "By hand" below.** This module
is a mechanical rendering of the same four resources, for the reasons
[`../README.md`](../README.md) gives for the sibling module: four
resources are easy to get one wrong by hand, and this one edits
organisation policy where a mistake is more consequential than a
project-scoped IAM grant.

## Status

**This has not been run against an organisation that enforces the
constraint.** Our own organisation has it at `ALLOW`, so it could not be
exercised. The commands and resources follow Google's documented
behaviour. Route 2 (the allowlist) is the known-good fallback if Route 1
does not work for you.

Spelled out rather than left at that one paragraph: `terraform apply`
has not been run against a real `iam.allowedPolicyMemberDomains` policy,
at any level, and the failure modes described elsewhere in this README
are reasoned from Google's documentation, not observed. "Documented" and
"tested by us" are not the same claim, and this README does not make the
second one anywhere.
[Route 2](../../docs/domain-restricted-sharing.md#route-2-add-nodrik-to-the-allowlist-simpler-org-wide)
— the allowlist — is one policy value, not four resources, and simpler
to unwind by hand if something about your organisation's existing
policy does not match what this module assumes.

## What it applies

1. an org-level tag key (`organizations/<organization_id>/<tag_key_short_name>`,
   default short name `nodrik`) — always at the organisation, regardless
   of `var.parent`; see `organization_id`'s description in `variables.tf`
   for why
2. one tag value under it (default short name `allowed`)
3. that value bound to `var.project_id` — and only that project
4. a policy for `constraints/iam.allowedPolicyMemberDomains`, set at
   `var.parent`, with a rule that lifts the restriction entirely for
   whatever carries the tag — and, at organisation level only, a second
   rule restating everything that already applied everywhere else. The
   exact shape differs by level; see
   [How the rule content varies by level](#how-the-rule-content-varies-by-level).

That is the complete list. This module never grants an IAM role itself
— [`../`](../) does that, against the project, once this exception
makes the grant possible.

## Choosing a level

`var.parent` is exactly one of `organizations/<id>`, `folders/<id>`, or
`projects/<id>` — the administrative node this module sets the policy
object on. There is no default: a module that edits organisation policy
must never pick this implicitly.

**We recommend project or folder over organisation.**
Either one asks whoever applies this module for `orgpolicy.policy.set`
(via `roles/orgpolicy.policyAdmin` or an equivalent custom role) on the
one node you name — not the whole organisation — and a mistake in the
policy this module writes can only reach resources under that node,
never anything outside it. In practice that usually means
`var.parent = "projects/${var.project_id}"`: the same project you are
already naming as the one being tagged and connected to Nodrik, so the
person approving this needs no organisation-wide access at all to do so.

Organisation is the escape hatch for an organisation that centralises
org-policy administration behind one team and would rather apply this
once than repeat it per project — not the default choice. Choosing it
also brings a real extra obligation: `var.existing_allowed_values` becomes
required (see [How the rule content varies by level](#how-the-rule-content-varies-by-level)
and [How this actually changes your policy](#how-this-actually-changes-your-policy)
below), because replacing the policy at the root of the hierarchy means
replacing the whole effective policy, not adding to it.

Whichever level you choose, `organization_id` is still required — the
tag key itself is always created at the organisation (see "What it
applies" above), independently of where the policy object lives.

## How the rule content varies by level

The Organization Policy Service has no "add one more rule" operation —
every apply **replaces the entire rule set** for the constraint at the
node named by `var.parent`. That single fact produces two different rule
sets, not a stylistic choice:

**Organisation** (`var.parent = organizations/<id>`): the root of the
hierarchy — there is no parent policy to inherit from, so replacing the
rule set at this node means replacing the *whole* effective policy. Two
rules, both required:

1. conditional on the tag → `allow_all = true` (lift the restriction
   entirely, but only for the one tagged resource)
2. unconditional fallback → `allowed_values = var.existing_allowed_values`
   (restate exactly what was already enforced everywhere else)

Rule 2 is not optional. Omitting it does not fall back to "whatever was
there before" — it replaces the policy with rule 1 alone, which lifts
domain-restricted sharing for every resource in the organisation that is
untagged and matches no rule, not just the one meant to be exempted.
`var.existing_allowed_values` exists, and has no default, for exactly
this reason — see [How this actually changes your policy](#how-this-actually-changes-your-policy).

**Folder or project** (`var.parent = folders/<id>` or `projects/<id>`):
`inherit_from_parent = true`, and one rule only:

1. conditional on the tag → `allow_all = true`

Nothing is being replaced here — `inherit_from_parent = true` means
every resource under this node that is *not* tagged keeps inheriting
whatever the organisation (or an intermediate folder) already enforces,
unchanged. There is no equivalent to rule 2 above because there is
nothing local to restate. This is also why `var.existing_allowed_values`
must be left empty at this level: a value here would have nothing to
attach to and would be silently ignored by the API. Two `lifecycle`
preconditions in `main.tf` enforce this both ways — `plan` fails rather
than let either mistake through.

**What `allow_all = true` actually means:** on the tagged resource, *any*
principal can be granted a role there — not only Nodrik's tenant service
account. The tag is what scopes this exception, not a principal
allowlist (unlike Route 2, which names Nodrik's Cloud Identity customer
id specifically and applies it organisation-wide — see
[`../../docs/domain-restricted-sharing.md`](../../docs/domain-restricted-sharing.md)).
Bind the tag only to the one project you mean to expose this way, and do
not reuse `var.tag_key_short_name`/`var.tag_value_short_name` for
anything else.

**Existing policy object:** if one already exists at `var.parent` —
likely at organisation level, since that is the level Google enforces
the constraint on by default; less likely at folder or project level,
where an explicit override is uncommon unless you set one yourself —
Terraform will not silently adopt it; `apply` fails with the API's
`ALREADY_EXISTS` rather than updating it. Import it first; see
[Before your first `plan`](#before-your-first-plan) below.

## How this actually changes your policy

This section is specifically about **organisation level** — at folder or
project level there is nothing being replaced (see
[How the rule content varies by level](#how-the-rule-content-varies-by-level)
above), so none of what follows applies there.

Setting an organisation-level policy for a list constraint **replaces
the entire rule set** for that constraint at the organisation. There is
no partial update.

That has one direct consequence for you: **this module needs to know
your organisation's current allowlist before it can write a new one
that includes it.** That is `var.existing_allowed_values`, and it has no
default on purpose — a default would either invent a value (wrong) or
start empty (which would replace your policy with one that allows
nothing but Nodrik, on the tagged project, and nothing at all
everywhere else — the opposite of "narrow exception"). Read your current
value first:

```bash
gcloud org-policies describe iam.allowedPolicyMemberDomains \
  --organization=ORGANIZATION_ID --effective \
  --format='value(spec.rules[0].values.allowedValues)'
```

and pass what it prints as `existing_allowed_values`. The module's own
`validation` and `lifecycle.precondition` blocks reject an empty list at
organisation level rather than silently narrowing your organisation's
own access to nothing.

## Before your first `plan`

If your organisation was created on or after 3 May 2024, Google enforces
`iam.allowedPolicyMemberDomains` by default with your domain as the only
allowed value — and if you are reading this, some Policy object for this
constraint almost certainly already exists somewhere in your hierarchy,
whether Google created it by default at the organisation or an admin set
one explicitly at the level you are targeting. Terraform will not adopt
an existing resource on `apply`; it will fail claiming the policy
already exists. Import it first, using the same value as `var.parent`:

```bash
terraform import google_org_policy_policy.domain_restricted_sharing_exception \
  "PARENT/policies/iam.allowedPolicyMemberDomains"
```

— substituting `organizations/ORGANIZATION_ID`, `folders/FOLDER_ID`, or
`projects/PROJECT_ID` for `PARENT` to match `var.parent`. Then run `plan`
and read the diff carefully before `apply`. At organisation level it
should show your existing allowlist preserved in rule 2 and the new
conditional rule 1 added, and nothing else changing. At folder or
project level, an existing policy object is less common (see "How the
rule content varies by level" above), but if one exists, `plan` should
show `inherit_from_parent` set to `true` and the conditional rule added,
with anything else already on that policy left alone. **We have not
exercised this import step ourselves** (see "Status" above); if `plan`
after importing shows anything other than the changes just described,
stop and read the diff rather than applying it.

## Usage

The recommended, narrower form — the policy applied at the one project
being connected:

```hcl
module "nodrik_org_policy_exception" {
  source = "github.com/thoughtgears/nodrik-onboarding//terraform/org-policy-exception?ref=v0.3.0"

  parent          = "projects/my-production-project"
  organization_id = "123456789012"
  project_id      = "my-production-project"
}
```

At organisation level, `existing_allowed_values` is also required (see
[How the rule content varies by level](#how-the-rule-content-varies-by-level)):

```hcl
module "nodrik_org_policy_exception" {
  source = "github.com/thoughtgears/nodrik-onboarding//terraform/org-policy-exception?ref=v0.3.0"

  parent                  = "organizations/123456789012"
  organization_id         = "123456789012"
  project_id              = "my-production-project"
  existing_allowed_values = ["is:C0xxxxxxx"] # from the `describe --effective` command above
}
```

**Pin `ref` to a tag rather than tracking a branch**, exactly as
[`../README.md`](../README.md#usage) says for the sibling module —
`v0.3.0` is the first release this module ships in;
[`../../CHANGELOG.md`](../../CHANGELOG.md) says what changed at each tag.

There is no `examples/` root module for this one. Given "Status" above,
we did not want a copy-paste example implying a working reference run —
the usage blocks above are complete on their own.

## Inputs

| Name                      | Type           | Required                                 | Description                                                                                                                                                                 |
| ------------------------- | -------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `parent`                  | `string`       | yes                                        | Where the policy object is set: `organizations/<id>`, `folders/<id>`, or `projects/<id>`. No default — see [Choosing a level](#choosing-a-level).                          |
| `organization_id`         | `string`       | yes                                        | Your numeric organisation id (`gcloud organizations list`), needed regardless of `parent` because the tag key is always created at the organisation. Validated as numeric, and checked against `parent` when `parent` itself names an organisation. |
| `project_id`               | `string`       | yes                                        | The one project being connected. Validated against GCP's project id shape.                                                                                                 |
| `existing_allowed_values`  | `list(string)` | **only when `parent` is `organizations/<id>`** — otherwise must be left empty (enforced by a `lifecycle.precondition`) | Your allowlist at `parent`, exactly as it reads today. No default at organisation level — see [How this actually changes your policy](#how-this-actually-changes-your-policy). |
| `tag_key_short_name`       | `string`       | no                                         | Default `nodrik`. Change only if that name already means something else in your tag namespace.                                                                             |
| `tag_value_short_name`     | `string`       | no                                         | Default `allowed`.                                                                                                                                                          |

## Outputs

| Name                        | Description                                                                                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tag_key_namespaced_name`   | The created tag key, e.g. `123456789012/nodrik`.                                                                                                                    |
| `tag_value_namespaced_name` | The tag value bound to `project_id`, e.g. `123456789012/nodrik/allowed`.                                                                                            |
| `policy_name`                | The policy object's full resource name, for `gcloud org-policies describe`.                                                                                         |
| `level`                      | Which level `parent` named — `"organization"` or `"folder-or-project"` — echoed back so you can confirm `plan` targeted the level you intended before applying it. |

## By hand

The same four resources, as `gcloud` commands — if you would rather not
grant this module `orgpolicy.policyAdmin`, or want to see exactly what
it would do before running it. The tag key and value are always created
at the organisation, regardless of which level you set the policy at:

```bash
gcloud resource-manager tags keys create nodrik \
  --parent "organizations/ORGANIZATION_ID"

gcloud resource-manager tags values create allowed \
  --parent "ORGANIZATION_ID/nodrik"

gcloud resource-manager tags bindings create \
  --tag-value "ORGANIZATION_ID/nodrik/allowed" \
  --parent "//cloudresourcemanager.googleapis.com/projects/PROJECT_ID"
```

Then, at **organisation level** — having read your current allowlist as
shown above — write `exception.yaml`:

```yaml
name: organizations/ORGANIZATION_ID/policies/iam.allowedPolicyMemberDomains
spec:
  inheritFromParent: false
  rules:
    - condition:
        expression: "resource.matchTag('ORGANIZATION_ID/nodrik', 'allowed')"
      allowAll: true
    - values:
        allowedValues:
          - is:YOUR_EXISTING_VALUE # repeat one line per existing value
```

Or, at **folder or project level** (the recommended, narrower form — see
[Choosing a level](#choosing-a-level)), the same file but scoped to that
node, with `inheritFromParent: true` and no second rule:

```yaml
name: projects/PROJECT_ID/policies/iam.allowedPolicyMemberDomains
spec:
  inheritFromParent: true
  rules:
    - condition:
        expression: "resource.matchTag('ORGANIZATION_ID/nodrik', 'allowed')"
      allowAll: true
```

(substitute `folders/FOLDER_ID` for `projects/PROJECT_ID` for a folder
instead.)

Apply whichever one matches the level you chose:

```bash
gcloud org-policies set-policy exception.yaml
```

**Success looks like:**

```bash
gcloud org-policies describe iam.allowedPolicyMemberDomains \
  --organization=ORGANIZATION_ID --effective
```

(substitute `--folder` or the default project-scoped invocation to match
the level you chose) showing the rule above, and re-running the grant
(the script, the doc, or [`../`](../)) against `PROJECT_ID` no longer
failing with `FAILED_PRECONDITION`. **If it still fails immediately after
you confirm the exception with `--effective`, wait a few minutes and try
again before concluding it did not work** — see
[the doc's propagation note](../../docs/domain-restricted-sharing.md#after-either-route).

## Removing the exception

```bash
terraform destroy
```

removes the tag binding, the tag value, the tag key, and the policy
object itself.

At **organisation level**, deleting the policy object reverts your
organisation to whatever applies with no explicit override at that
level — for an organisation created on or after 3 May 2024 with no other
customisation, that is Google's own default (your domain only), which is
the outcome you want. **We have not verified this for an organisation
whose domain-restricted-sharing policy was customised beyond the
default** (a different allowlist, a policy inherited from a folder, or
one set before this module ever ran) — in that case, deleting the policy
object might revert further than "back to how it was before this module
ran", rather than to your organisation's actual prior state. Run the
`describe --effective` command above after `destroy` and check it
against what you expect before considering the exception fully removed.

At **folder or project level**, this caveat does not apply the same way:
the policy object this module creates there only ever sets
`inherit_from_parent = true` and adds the one conditional rule — it never
replaces anything local to that node, because there is nothing local to
replace (see [How the rule content varies by level](#how-the-rule-content-varies-by-level)).
Deleting it always reverts cleanly to full inheritance from whatever the
organisation, or an intermediate folder, already enforces — the same
state as if this module had never run at that node.

This module never touches the four viewer-role grants
([`../`](../) does, on `terraform destroy` there) or Nodrik's own side
of the teardown — see [`../README.md#removing-nodrik`](../README.md#removing-nodrik)
for what removes what.

## What we verified

Against Google's current Organization Policy documentation
(`cloud.google.com/resource-manager/docs/organization-policy/restricting-domains`,
fetched 2026-09-15 and re-checked 2026-09-16 for the two points below
that are new since the level rework):

- `iam.allowedPolicyMemberDomains` is a **legacy managed, list-type**
  constraint. It does not support `denyAll` or denied values — only
  `allowedValues`, or `allowAll` to lift the restriction entirely for
  whatever the rule's condition matches. Google's own tag-conditional
  worked examples for this exact constraint show **both** shapes: one
  using `allowAll: true` keyed on a tag (to let every identity in on a
  tagged resource), and one using a conditional `values.allowedValues`
  rule naming a specific principal set. This module's conditional rule
  uses `allow_all = true` — the first shape — because Route 1's intent is
  to lift the restriction on the tagged project entirely, not to add one
  more named principal to an allowlist; that is what
  `existing_allowed_values` (the organisation-level fallback rule) and
  Route 2 are for.
- The same page states, twice — once for `--dry-run`, once for the live
  `set-policy` — that after `gcloud org-policies set-policy` **"the
  policy requires up to 15 minutes to take effect."** It does not say
  whether that gap applies equally to the `--effective` read-back or only
  to enforcement, but it is a direct, first-party statement that applying
  this policy is not instant — see
  [the doc's propagation note](../../docs/domain-restricted-sharing.md#after-either-route)
  for what this means in practice.
- A conditional rule requires at least one unconditional rule in the
  same policy, or the policy cannot be saved — stated on the same page
  and on the general "Scope organization policies with tags" guidance it
  links to. This is why the organisation-level rule set has two rules
  and the folder/project one does not need a second: at folder or
  project level, `inherit_from_parent = true` means the policy is not
  replacing the whole effective policy, so there is nothing left over
  that would otherwise be dropped.
- Required role: `roles/orgpolicy.policyAdmin`, stated directly on that
  page — Google's documentation frames it as an organisation-level
  concern throughout, since that is where it enforces the constraint by
  default; nothing on the page contradicts granting the equivalent
  `orgpolicy.policy.set` permission at a narrower node instead, which is
  standard GCP IAM behaviour for any predefined or custom role bound at
  a folder or project rather than the organisation.
- Terraform resource arguments (`google_org_policy_policy`'s
  `name`/`parent`/`spec.inherit_from_parent`/`spec.rules.condition.expression`/
  `spec.rules.allow_all`/`spec.rules.values.allowed_values`;
  `google_tags_tag_key`'s `parent`/`short_name`;
  `google_tags_tag_value`'s `parent` as the tag key's `id`;
  `google_tags_tag_binding`'s `parent` as
  `//cloudresourcemanager.googleapis.com/projects/<NUMBER>` — a project
  **number**, not id — and `tag_value` in namespaced or `tagValues/<id>`
  form) against the `hashicorp/google` provider's own resource
  documentation.

**What we assumed rather than verified:**

- The exact IAM permission(s) needed to create a tag key/value and bind
  it (`resourcemanager.tagAdmin`/`resourcemanager.tagUser` or similar).
  Google's guidance points at a separate tags-permissions page we did
  not independently confirm role-by-role; if tag creation is refused,
  the person applying this module is not necessarily the person who
  granted the four viewer roles, same gotcha as `../`'s `families`.
- Whether `terraform import` against a Policy object that Google created
  by default (rather than one an admin set explicitly) behaves exactly
  as the provider's documented import path describes — see "Before your
  first `plan`" above.
- Whether the "up to 15 minutes" figure above is the same gap that
  causes the propagation symptom described in
  [the doc's propagation note](../../docs/domain-restricted-sharing.md#after-either-route)
  — we take it as strong evidence that the gap is real for this exact
  constraint, but Google's page does not spell out the failure mode
  (apply → confirm with `--effective` → immediately retry → same domain
  error) in those terms.
- End-to-end behaviour against a live enforcing organisation, at any
  level — see "Status" above; this is the load-bearing caveat, not a
  footnote to it.

## Registry

Not published, for the same reason as [`../README.md`](../README.md#registry)
— one public repository holding every onboarding path, sourced from
GitHub.
