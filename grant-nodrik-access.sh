#!/usr/bin/env bash
#
# Grants Nodrik read-only access to your GCP project(s).
#
# THIS SCRIPT IS MEANT TO BE READ BEFORE IT IS RUN. It wraps the steps in
# docs/granting-access.md one-for-one and calls nothing but `gcloud`.
# There is no network access to Nodrik, no telemetry, no install step,
# and no binary. Everything it does, you could type.
#
# What it grants, in full:
#
#   roles/logging.viewer         read log entries, and the Admin
#                                Activity audit log
#   roles/monitoring.viewer      read metrics and alert policies
#   roles/errorreporting.viewer  read error groups
#   roles/run.viewer             read Cloud Run service and revision config
#                                (the response carries environment-variable
#                                VALUES; Nodrik keeps the names and discards
#                                the values, but the permission allows
#                                reading them)
#
# All four are read-only Google-managed roles. Nodrik cannot change
# anything in your project, and asks for no role that would let it.
#
# Optionally, per service you name with --family, one more read-only
# role. Each is a CUSTOM role, defined in your project by this script,
# holding exactly the get/list permissions the tool behind it calls and
# nothing else (the product's own test suite asserts that). Google's
# predefined viewers for these services carry verbs that are not reads
# (cloudsql.viewer can export the database, compute.viewer can read a
# VM's serial console), which is why Nodrik defines its own:
#
#   --family managed-sql   nodrikManagedSqlConfigViewer
#                          reads Cloud SQL instance settings and database
#                          flags; cannot change them, read or export data,
#                          connect, or log in
#   --family cache         nodrikCacheConfigViewer
#                          reads Memorystore (Redis, Valkey, Memcached)
#                          instance settings; cannot change them, read
#                          cached data, or connect
#   --family kubernetes    nodrikKubernetesConfigViewer
#                          reads GKE cluster settings from the GKE API —
#                          container.clusters.get and .list, and no
#                          permission on anything INSIDE the cluster: no
#                          pod, workload, ConfigMap or Secret is readable.
#                          Two things the permission does allow, stated
#                          plainly: clusters.get is what get-credentials
#                          uses, so the identity could generate a
#                          kubeconfig (and then be authorised for nothing);
#                          and on a cluster still issuing a legacy client
#                          certificate, clusters.get returns it. Nodrik's
#                          code has no Kubernetes client and never
#                          connects to your kube-apiserver.
#   --family compute       nodrikComputeConfigViewer
#                          reads Compute Engine instance, managed instance
#                          group and autoscaler settings; cannot read the
#                          serial console or screenshots. instances.get
#                          DOES return instance metadata, startup script
#                          included — the permission allows it; Nodrik's
#                          tool discards it (an allowlist of fields, with
#                          a test asserting metadata is never printed)
#   --family networking    nodrikNetworkingConfigViewer
#                          reads load balancer backend health and
#                          configuration; cannot read instance internals
#
# Without --family the script does exactly what it always did. With it,
# after the four, it defines the role (or updates it to this list) and
# binds it. Defining a role needs iam.roles.create on the project, which
# roles/resourcemanager.projectIamAdmin does NOT carry (roles/iam.roleAdmin
# does) — if that step is refused, the person who can bind is not the
# person who can define, and the script says so. revoke-nodrik-access.sh
# deletes these roles again, whether or not you pass --family.
#
# Run with --dry-run first. It prints every command and changes nothing.

set -euo pipefail

readonly ROLES=(
  roles/logging.viewer
  roles/monitoring.viewer
  roles/errorreporting.viewer
  roles/run.viewer
)

# One entry per optional family: the role id, then the permissions the
# product's tool calls — every one a get or a list. KEEP IN STEP with
# FAMILY_GRANTS in the product repo (packages/control/src/grants.ts):
# that table is what the pre-flight and the verifier check, and a role
# defined here with a different list would verify against the wrong
# thing. The permission strings are read from Google's method reference
# pages; none is from memory.
# Product identity. The role ids and titles below are rendered from
# these two, so a rename is a change here and nowhere else in this file.
# They must stay in step with product_slug / product_name in
# terraform/variables.tf, FAMILY_ROLE_IDS in revoke-nodrik-access.sh, and
# PRODUCT_SLUG / PRODUCT_NAME in the product repo's grants.ts — the
# verifier matches on the role id, so a slug that differs from the
# product's makes a grant apply and then fail verification.
readonly PRODUCT_SLUG="nodrik"
readonly PRODUCT_NAME="Nodrik"

readonly FAMILY_NAMES=(managed-sql cache kubernetes compute networking)
family_role_id() {
  case "$1" in
    managed-sql) printf '%sManagedSqlConfigViewer' "$PRODUCT_SLUG" ;;
    cache)       printf '%sCacheConfigViewer' "$PRODUCT_SLUG" ;;
    kubernetes)  printf '%sKubernetesConfigViewer' "$PRODUCT_SLUG" ;;
    compute)     printf '%sComputeConfigViewer' "$PRODUCT_SLUG" ;;
    networking)  printf '%sNetworkingConfigViewer' "$PRODUCT_SLUG" ;;
    *)           return 1 ;;
  esac
}
family_role_title() {
  case "$1" in
    managed-sql) printf '%s Cloud SQL configuration viewer' "$PRODUCT_NAME" ;;
    cache)       printf '%s Memorystore configuration viewer' "$PRODUCT_NAME" ;;
    kubernetes)  printf '%s GKE configuration viewer' "$PRODUCT_NAME" ;;
    compute)     printf '%s Compute Engine configuration viewer' "$PRODUCT_NAME" ;;
    networking)  printf '%s load balancing configuration viewer' "$PRODUCT_NAME" ;;
  esac
}
family_permissions() {
  case "$1" in
    managed-sql) printf 'cloudsql.instances.get,cloudsql.instances.list' ;;
    cache)       printf 'redis.instances.get,redis.instances.list,memorystore.instances.get,memorystore.instances.list,memcache.instances.get,memcache.instances.list' ;;
    kubernetes)  printf 'container.clusters.get,container.clusters.list' ;;
    compute)     printf 'compute.instances.get,compute.instances.list,compute.instanceGroupManagers.list,compute.autoscalers.list,compute.zoneOperations.list' ;;
    networking)  printf 'compute.backendServices.get,compute.backendServices.list,compute.regionBackendServices.get,compute.regionBackendServices.list,compute.urlMaps.list,compute.regionUrlMaps.list,compute.healthChecks.get,compute.regionHealthChecks.get' ;;
  esac
}

readonly CHANNEL_NAME="Nodrik (@nodrik)"
readonly DOMAIN_POLICY_DOCS="https://cloud.google.com/resource-manager/docs/organization-policy/restricting-domains"

TENANT_SA=""
TOPIC=""
PROJECTS=()
FAMILIES=()
DRY_RUN=false
ASSUME_YES=false

die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

# "granted" is a lie in dry-run mode. Takes both tenses rather than
# trying to conjugate: $1 is what happened, $2 is what would happen.
did() { if [[ "$DRY_RUN" == true ]]; then note "would $2"; else note "$1"; fi; }

# Every gcloud call here is read-only or an IAM grant, and none of them may
# prompt. `--quiet` takes the default answer and stdin is closed, so the
# script can never sit waiting for a human — and, more importantly, can
# never accept gcloud's offer to enable an API on your project. An earlier
# version checked your org policy and gcloud offered to turn on the Org
# Policy API to do it: a write, on your project, from a script that
# promises to change nothing.
gcloud() { command gcloud "$@" --quiet </dev/null; }

# Quote an argument the way you would have to type it, so everything
# printed below is copy-pasteable. Without this, an argument containing
# spaces prints as `--display-name Nodrik (@nodrik)`, which is a syntax
# error if you paste it.
shell_quote() {
  local arg out=""
  for arg in "$@"; do
    if [[ "$arg" =~ ^[A-Za-z0-9_./:=@-]+$ ]]; then
      out+="$arg "
    else
      out+="'${arg}' "
    fi
  done
  printf '%s' "${out% }"
}

# `run` is the only thing that mutates anything. Every change goes through
# it, so --dry-run is trustworthy by construction rather than by us having
# remembered to check a flag in each place.
#
# It swallows command output but NEVER the printed command. An earlier
# version let call sites add `>/dev/null`, which silenced the echo too and
# hid the IAM grants from the one mode that exists to show them.
run() {
  printf '  $ %s\n' "$(shell_quote "$@")"
  if [[ "$DRY_RUN" == true ]]; then return 0; fi
  "$@" >/dev/null
}

usage() {
  cat <<'USAGE'
Usage:
  grant-nodrik-access.sh --tenant-sa <SA_EMAIL> --topic <TOPIC> \
                         --project <PROJECT_ID> [--project <PROJECT_ID> ...]
                         [--family <NAME> ...] [--dry-run] [--yes]

  --tenant-sa   The service account we gave you, e.g.
                tenant-acme@tg-shard-N.iam.gserviceaccount.com
  --topic       Your alert intake topic, e.g.
                projects/tg-hub-N/topics/tenant-acme-alerts
  --project     A project Nodrik should investigate. Repeat for several.
  --family      Optional. One more read-only role for one service's
                settings: managed-sql, cache, kubernetes, compute or
                networking. Repeat for several. See the header.
  --dry-run     Print every command without running it. Do this first.
  --yes         Skip the confirmation prompt (for reruns).

Both values come from Nodrik during onboarding. If you do not have them,
stop — this script cannot be used without them.
USAGE
}

explain_role_admin() {
  cat <<'MSG'

  Defining a custom role needs iam.roles.create on the project, which
  roles/resourcemanager.projectIamAdmin does NOT carry (roles/iam.roleAdmin
  and roles/owner do). The account that could bind the four roles is
  frequently not one that can define a fifth. Nothing is half-done: the
  four roles and the channel are in place, and re-running this script
  with --family as someone who holds roles/iam.roleAdmin picks up here.
MSG
}

explain_domain_policy() {
  cat <<MSG

  This is almost certainly iam.allowedPolicyMemberDomains — domain-restricted
  sharing, which blocks IAM grants to service accounts outside your org. It
  is a deliberate setting, not a mistake, and it needs an exception for
  Nodrik's organization before onboarding can continue. Ask us for the org id.

    $DOMAIN_POLICY_DOCS

  Nothing is left half-done: re-run this script once the exception is in
  place and it will pick up where it stopped.
MSG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant-sa) TENANT_SA="${2:-}"; shift 2 ;;
    --topic)     TOPIC="${2:-}"; shift 2 ;;
    --project)   PROJECTS+=("${2:-}"); shift 2 ;;
    --family)    FAMILIES+=("${2:-}"); shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --yes)       ASSUME_YES=true; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage; die "unknown argument: $1" ;;
  esac
done

[[ -n "$TENANT_SA" ]] || { usage; die "--tenant-sa is required"; }
[[ -n "$TOPIC" ]] || { usage; die "--topic is required"; }
[[ ${#PROJECTS[@]} -gt 0 ]] || { usage; die "at least one --project is required"; }
for family in "${FAMILIES[@]}"; do
  family_role_id "$family" >/dev/null \
    || die "--family must be one of: ${FAMILY_NAMES[*]} (got: $family)"
done

[[ "$TENANT_SA" == *@*.iam.gserviceaccount.com ]] \
  || die "--tenant-sa does not look like a service account: $TENANT_SA"
[[ "$TOPIC" == projects/*/topics/* ]] \
  || die "--topic must be a full path (projects/PROJECT/topics/NAME), got: $TOPIC"

command -v gcloud >/dev/null || die "gcloud is not installed"

# The notification-channel commands live in the beta surface. If it is
# missing, gcloud prompts to install it mid-run; check up front so the
# decision is yours, made before anything has happened.
command gcloud beta --help >/dev/null 2>&1 \
  || die "the gcloud 'beta' component is required — run: gcloud components install beta"

step "What this will do"
note "Service account : $TENANT_SA"
note "Alert topic     : $TOPIC"
note "Projects        : ${PROJECTS[*]}"
note ""
note "On each project, grant that service account these four roles:"
for role in "${ROLES[@]}"; do note "  $role"; done
note ""
note "…and create one Pub/Sub notification channel named \"$CHANNEL_NAME\"."
if [[ ${#FAMILIES[@]} -gt 0 ]]; then
  note ""
  note "Optionally, per service you named with --family, one more read-only role,"
  note "defined in the project with exactly these permissions and then bound:"
  for family in "${FAMILIES[@]}"; do
    note "  $(family_role_id "$family")  ($family)"
    note "    $(family_permissions "$family" | tr ',' ' ')"
  done
fi
note "Nothing else. No write access is requested and none is granted."

if [[ "$DRY_RUN" == true ]]; then
  note ""
  note "DRY RUN — commands are printed, nothing is changed."
elif [[ "$ASSUME_YES" != true ]]; then
  printf '\nProceed? [y/N] '
  read -r reply
  [[ "$reply" == [yY]* ]] || die "aborted"
fi

# Collected for the final handshake. Alerts cannot flow until Nodrik grants
# your project's monitoring agent publish rights on the topic, and it needs
# these numbers to do it.
PROJECT_NUMBERS=()

for project in "${PROJECTS[@]}"; do
  step "Project: $project"

  gcloud projects describe "$project" --format='value(projectId)' >/dev/null 2>&1 \
    || die "cannot read project '$project' — check the id and that you are authenticated"

  # We deliberately do NOT pre-check the org policy that most often blocks
  # this (see the gcloud wrapper above). Try the grant; explain the failure.
  #
  # add-iam-policy-binding is idempotent, so re-running after fixing a
  # policy — or to add a project — is safe and does nothing twice.
  errfile=$(mktemp)
  for role in "${ROLES[@]}"; do
    if ! run gcloud projects add-iam-policy-binding "$project" \
      --member "serviceAccount:$TENANT_SA" \
      --role "$role" \
      --condition=None 2>"$errfile"; then
      err=$(cat "$errfile"); rm -f "$errfile"
      printf '\n%s\n' "$err" >&2
      if [[ "$err" == *FAILED_PRECONDITION* || "$err" == *allowedPolicyMemberDomains* ]]; then
        explain_domain_policy >&2
      fi
      die "granting $role on $project failed — see above"
    fi
  done
  rm -f "$errfile"
  did "granted ${#ROLES[@]} read-only roles" "grant ${#ROLES[@]} read-only roles"

  # The optional family roles, after the four. Each is a CUSTOM role, so
  # it has to exist before it can be bound: `roles describe` says
  # whether it does, `roles create` defines it, and `roles update`
  # brings an older definition up to this list — Nodrik's definition is
  # authoritative for Nodrik's role, and re-running with the same list
  # is a no-op. A deleted role's id is reserved for seven days;
  # `roles undelete` brings it back rather than failing on the id.
  #
  # Defining a role is the one step here that needs iam.roles.create,
  # which the person holding setIamPolicy does not necessarily hold —
  # so its refusal is explained rather than left as a raw error.
  for family in "${FAMILIES[@]}"; do
    role_id=$(family_role_id "$family")
    permissions=$(family_permissions "$family")
    errfile=$(mktemp)
    if gcloud iam roles describe "$role_id" --project "$project" --format='value(deleted)' >"$errfile" 2>/dev/null; then
      if [[ "$(cat "$errfile")" == "True" ]]; then
        run gcloud iam roles undelete "$role_id" --project "$project"
      fi
      if ! run gcloud iam roles update "$role_id" --project "$project" \
        --permissions "$permissions" --stage GA 2>"$errfile"; then
        printf '\n%s\n' "$(cat "$errfile")" >&2
        explain_role_admin >&2
        die "updating role $role_id on $project failed — see above"
      fi
      did "role $role_id is defined (updated to this list if it differed)" "define or update role $role_id"
    else
      if ! run gcloud iam roles create "$role_id" --project "$project" \
        --title "$(family_role_title "$family")" \
        --description "Read-only: what Nodrik's $family configuration tool calls, and nothing else. revoke-nodrik-access.sh deletes it." \
        --permissions "$permissions" --stage GA 2>"$errfile"; then
        printf '\n%s\n' "$(cat "$errfile")" >&2
        explain_role_admin >&2
        die "creating role $role_id on $project failed — see above"
      fi
      did "defined role $role_id" "define role $role_id"
    fi
    rm -f "$errfile"

    if ! run gcloud projects add-iam-policy-binding "$project" \
      --member "serviceAccount:$TENANT_SA" \
      --role "projects/$project/roles/$role_id" \
      --condition=None 2>/dev/null; then
      die "binding $role_id on $project failed"
    fi
    did "bound $role_id ($family)" "bind $role_id ($family)"
  done

  # Channel creation is NOT idempotent — creating twice gives two channels
  # and two notifications per alert, so this check is load-bearing.
  #
  # Matching happens in bash, NOT via `gcloud --filter`. Filtering this
  # resource silently returns nothing (even `--filter=type=pubsub` matches
  # zero pubsub channels), and a check that quietly matches nothing is
  # worse than no check: it reports success and creates a duplicate every
  # run. Found by running this script twice, 2026-08-06.
  #
  # We match on the TOPIC, not the display name: two channels pointing at
  # the same topic is what actually doubles the notifications.
  existing=""
  while IFS=$'\t' read -r channel_name channel_topic; do
    if [[ "$channel_topic" == "$TOPIC" ]]; then existing="$channel_name"; break; fi
  done < <(gcloud beta monitoring channels list \
    --project "$project" \
    --format='value(name,labels.topic)' 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    note "notification channel already exists — leaving it alone"
    note "  $existing"
  else
    run gcloud beta monitoring channels create \
      --project "$project" \
      --display-name "$CHANNEL_NAME" \
      --type pubsub \
      --channel-labels "topic=$TOPIC"
    did "created the notification channel" "create the notification channel"
  fi

  PROJECT_NUMBERS+=("$project=$(gcloud projects describe "$project" --format='value(projectNumber)')")
done

step "Done — one thing left, and it is on our side"
cat <<EOF

  Alerts cannot reach Nodrik until we grant your project's monitoring
  agent permission to publish to the topic. Send us these numbers:

EOF
for entry in "${PROJECT_NUMBERS[@]}"; do printf '    %s\n' "$entry"; done
cat <<EOF

  Then attach the "$CHANNEL_NAME" channel to whichever alert policies you
  want investigated — all of them is a reasonable choice. One incident
  becomes one investigation in one Slack thread; storms fold together
  rather than spamming the channel.

  To remove Nodrik entirely: run revoke-nodrik-access.sh, which reverses
  the four role bindings, removes any optional family role and deletes
  its definition, and deletes the notification channel. Nothing else
  exists on your side.

EOF
