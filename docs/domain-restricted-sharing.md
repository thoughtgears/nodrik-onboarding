# Domain-restricted sharing: choosing a route, and applying it

If granting Nodrik's four roles failed with `FAILED_PRECONDITION`, or the
product itself showed a "blocked" screen naming this constraint, your
organisation enforces
[`constraints/iam.allowedPolicyMemberDomains`](https://cloud.google.com/resource-manager/docs/organization-policy/restricting-domains)
— usually called **domain-restricted sharing**. It refuses any IAM role
binding to a principal outside your own Cloud Identity customer. Nodrik's
tenant service account lives in **our** Google Cloud project, not yours
— one dedicated account per customer, the same design that keeps one
Nodrik customer's identity from ever reaching another's — so every one
of the four read-only bindings is refused until you allow it.

**This is a deliberate security setting, not a misconfiguration**, and
neither route below asks you to turn it off. Both add a narrow
exception; the difference between them is how narrow.

## Choosing a route

|                        | Route 1: tag-scoped exception                                                                      | Route 2: add Nodrik to the allowlist                                                 |
| ---------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Scope**              | The one project you tag. Nothing else in your organisation changes.                                  | Every project in your organisation that inherits this policy — present and future.     |
| **What it touches**    | Four resources: a tag key, a tag value, a tag binding, and a conditional rule on the org policy.      | One value added to the org policy's allowlist. Nothing else.                          |
| **Level**              | Organisation, folder, or project — your choice. **Project or folder recommended**: see [Choosing a level](#choosing-a-level) below. | Always the organisation. One allowlist value only makes sense as one org-wide policy. |
| **Permission needed**  | `roles/orgpolicy.policyAdmin` (or the `orgpolicy.policy.set` permission) on **whichever level you choose** — a single project needs only project-level access, not organisation-level. | `roles/orgpolicy.policyAdmin` on the **organisation** — not optional the way it is for Route 1, because there is nowhere narrower to set a single org-wide allowlist. |
| **New projects later** | Each one needs its own tag binding — a deliberate, visible, repeatable step.                          | Automatically covered, with no further action — which is convenient, and also means you may not notice Nodrik's access extending to a project you did not mean to include. |
| **To undo**            | Remove one tag binding. The policy rule stays defined but inert for every project that was never tagged. | Edit the org policy again and remove the customer id.                                  |
| **Terraform module**   | [`../terraform/org-policy-exception`](../terraform/org-policy-exception) — optional, not required.   | None — a single value does not warrant a module; see the `gcloud` steps below.         |
| **Tooling maturity**   | Newer, more moving parts, **not yet exercised against a live enforcing organisation, at any level** — see the module's [Status](../terraform/org-policy-exception/README.md#status) section. | Simpler, and the fallback if Route 1 does not work for you. |

**Lead with Route 1 at project or folder level if you can.** Applied
there, it is the smaller ask on both axes that matter: the admin
applying it needs `orgpolicy.policy.set` on that one node rather than
the organisation, and a mistake in the policy this writes can only
reach resources under that node. Route 2 has no equivalent narrowing —
a single org-wide allowlist value only makes sense set at the
organisation, so it always needs organisation-level access. That is
also true of Route 1 if you choose to apply it at organisation level
instead of project or folder — see
[Choosing a level](#choosing-a-level) below.

Permission aside, blast radius and maintenance shape are the other real
trade-off: Route 1 stays narrow forever, at the cost of one tag binding
per future project; Route 2 is one edit, done once, and then applies
itself to every project your organisation ever creates under this
policy, including ones nobody thought to check against a supplier
allowlist. If your organisation already reviews org policy changes as
security-relevant (most that enforce domain-restricted sharing do),
Route 1 gives that review something narrow and legible to approve. If
you connect many projects to Nodrik over time, or expect to, and your
organisation centralises org-policy administration behind one team
anyway, Route 2's one-time cost — or Route 1 applied at organisation
level — may be the more honest trade; either is also the option with
no unexercised Terraform module behind it, since Route 1's module is
only optional for Route 1 in the first place.

## Choosing a level

Only Route 1 has this choice — Route 2 is always one value on the
organisation's own policy, because a single allowlist value has nowhere
narrower to live.

Route 1's policy object can be set at your organisation, a folder, or a
single project. **Default to the project you are connecting** — the
same one you would pass to Nodrik's grant script or Terraform module
anyway. That needs `orgpolicy.policy.set` (via
`roles/orgpolicy.policyAdmin` or an equivalent custom role) on that one
project only, and a mistake in the policy this writes can only reach
resources under that project — never anything else in your
organisation. A folder works the same way, one level up, if you would
rather cover several projects already inside it without a separate tag
binding for each.

Organisation is the wider option, not the default: pick it only if your
organisation centralises org-policy administration behind one team that
would rather apply this once, or plans to reuse the same tag across many
projects it does not want to fold into one folder. It also comes with a
real extra step Route 1 does not otherwise need: because setting a
policy at the organisation replaces the whole effective policy there,
you must also read your organisation's current allowlist first (see
"Before either route" below) and pass it along so it stays preserved
for every project this exception does not name.

Full mechanics of how the rule content itself differs by level — what
gets replaced, what does not, and why — are in the Terraform module's
[Choosing a level](../terraform/org-policy-exception/README.md#choosing-a-level)
and [How the rule content varies by level](../terraform/org-policy-exception/README.md#how-the-rule-content-varies-by-level)
sections, whether or not you use the module: the `gcloud` steps under
"Route 1" below follow the same shape.

## What needs to be allowed

One service account, dedicated to your workspace, shaped like:

```text
tenant-<your-workspace>@tg-shard-<n>.iam.gserviceaccount.com
```

The exact address is shown in the console and printed by
[`../grant-nodrik-access.sh`](../grant-nodrik-access.sh) and the
[`../terraform`](../terraform) module. It is being granted four
**viewer** roles and nothing else — see
[`../README.md`](../README.md#what-nodrik-gets) for the complete list.
No path here ever requests a write role.

Nodrik's Cloud Identity customer id, used by **Route 2** below, is
`C015nrtrj`. Route 1 does not use it anywhere: its exception lifts the
restriction entirely for the tagged resource rather than naming a
specific principal — see "What `allow_all = true` actually means" in
the [module's README](../terraform/org-policy-exception/README.md#how-the-rule-content-varies-by-level).

## Before either route: read your current policy

Route 2 always needs this. Route 1 needs it only if you apply it at
**organisation** level — at folder or project level, Route 1 never
touches your existing allowlist at all (see
[Choosing a level](#choosing-a-level) above), so you can skip straight
to "Route 1" below.

Setting this org policy at the organisation **replaces its entire rule
set** — the Organization Policy Service has no "add one value"
operation, and neither `gcloud org-policies set-policy` nor Terraform's
`google_org_policy_policy` resource can do a partial update at that
level. Read what is currently allowed before writing anything:

```bash
gcloud org-policies describe iam.allowedPolicyMemberDomains \
  --organization=ORGANIZATION_ID --effective \
  --format='value(spec.rules[0].values.allowedValues)'
```

Keep that output. Skipping this step, when you need it, is how a
well-meant exception ends up narrower than intended — dropping your own
organisation's access rather than only adding Nodrik's.

## Route 1: a tag-scoped exception (preferred, narrower)

**Apply this at project or folder level if you can** — see
[Choosing a level](#choosing-a-level) above. Organisation level works
too, but asks for more access, and more of "Before either route" above,
than most customers need. Full detail, a Terraform module, and an
honest account of what has and has not been verified are in
[`../terraform/org-policy-exception/README.md`](../terraform/org-policy-exception/README.md)
— read it before applying either the module or the equivalent `gcloud`
steps reproduced there. In outline: tag the one project, then add a rule
to the org policy that only relaxes the restriction on resources
carrying that tag.

## Route 2: add Nodrik to the allowlist (simpler, org-wide)

One value, added to the allowlist you already read above. No module —
a module around a single value would be ceremony, not help.

Write `allowlist.yaml`, with your existing values from "Before either
route" above plus Nodrik's:

```yaml
name: organizations/ORGANIZATION_ID/policies/iam.allowedPolicyMemberDomains
spec:
  rules:
    - values:
        allowedValues:
          - is:YOUR_EXISTING_VALUE # repeat one line per existing value
          - is:C015nrtrj # Nodrik
```

Apply it:

```bash
gcloud org-policies set-policy allowlist.yaml
```

**Success looks like:**

```bash
gcloud org-policies describe iam.allowedPolicyMemberDomains \
  --organization=ORGANIZATION_ID --effective
```

showing `is:C015nrtrj` in `allowedValues`, and re-running the grant —
the script, the doc, or the Terraform module in [`../terraform`](../terraform)
— no longer failing with `FAILED_PRECONDITION`.

**To undo:** edit `allowlist.yaml` to drop the `is:C015nrtrj` line and
`set-policy` again.

## After either route

Re-run whichever grant path you started with:
[`granting-access.md`](granting-access.md),
[`../grant-nodrik-access.sh`](../grant-nodrik-access.sh), or
[`../terraform`](../terraform) — the resources and commands are
idempotent, so it picks up exactly where it stopped. Nothing was applied
before the exception was in place, so there is nothing to undo on
Nodrik's side of that failed attempt.

**Give it a few minutes before you conclude the exception did not
work.** Google's own documentation for this exact constraint states
that after `gcloud org-policies set-policy`, "the policy requires up to
15 minutes to take effect" — so confirming the new rule with
`--effective` right after applying it does not guarantee the change has
finished propagating everywhere it needs to. A related, separately
observed pattern makes the failure mode worth naming explicitly: on
Google's other CEL-conditional tag-exception org policy we have used
(`iam.disableServiceAccountKeyCreation`), the Resource Manager
`--effective` view updates instantly, but the service that actually
enforces the constraint reads from a separate cache that lags roughly
30 seconds to 7 minutes behind — **we have not verified that this
specific 30-second-to-7-minute figure applies to
`iam.allowedPolicyMemberDomains`**, only that Google's own page states a
comparable "up to 15 minutes" figure for this constraint directly. Either
way, the practical effect is the same: apply the exception, confirm it
with `--effective`, immediately re-run the grant, and get the same
domain error — which reads exactly like "the exception doesn't work"
when it most likely just has not propagated yet. Retry for several
minutes before concluding otherwise.

If a project still fails after several minutes with the exception in
place and the grant re-run, the cause is something else — send us the
project id and organisation id at `support@nodrik.dev`.

## What we verified, and what we assumed

Against Google's current documentation for
`constraints/iam.allowedPolicyMemberDomains` (`cloud.google.com/resource-manager/docs/organization-policy/restricting-domains`,
fetched 2026-09-15, re-checked 2026-09-16) — full detail in the module
README's
["What we verified"](../terraform/org-policy-exception/README.md#what-we-verified)
section:

- **Verified**: the constraint is list-type and does not support
  `denyAll`/denied values; the `allowedValues` formats (`is:C…` /
  `is:principalSet://…`); that Google's own tag-conditional worked
  examples for this exact constraint show both an `allowAll: true` rule
  and a `values.allowedValues` rule (Route 1 uses the former, Route 2's
  shape is the latter); that a conditional rule needs an unconditional
  fallback rule in the same policy or the policy cannot be saved (true
  only when the policy is set at the organisation — see
  [Choosing a level](#choosing-a-level) above); that
  `roles/orgpolicy.policyAdmin` is the role Google itself names for
  this, though its documentation only discusses it at organisation
  level; and that the same page states, twice, that after
  `gcloud org-policies set-policy` **"the policy requires up to 15
  minutes to take effect."**
- **Assumed**: the exact IAM permission(s) for creating and binding tags
  (a separate permissions page we did not independently confirm role by
  role); that `orgpolicy.policy.set` granted at a folder or project
  behaves the way GCP's general IAM inheritance model says it should,
  since Google's own page for this constraint never discusses anything
  narrower than the organisation; that the propagation delay described
  in ["After either route"](#after-either-route) — the 30-second-to-7-minute
  figure we have separately observed on a different tag-conditional
  constraint — is the same mechanism as the "up to 15 minutes" figure
  Google states for this one, rather than merely a similar-looking
  coincidence; and everything about how either route behaves against an
  organisation actually enforcing the constraint, at any level — **we
  have not run either route against one**. Our own organisation has this
  constraint at `ALLOW`, so it has never been exercised end to end.
  Route 2 is the simpler command and the one we would reach for first if
  Route 1 surprised us.
