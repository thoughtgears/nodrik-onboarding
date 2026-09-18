output "tag_key_namespaced_name" {
  description = "The tag key this module created, e.g. \"123456789012/nodrik\". For your own verification, and for binding the same tag to another resource by hand later without re-running this module."
  value       = google_tags_tag_key.nodrik.namespaced_name
}

output "tag_value_namespaced_name" {
  description = "The tag value bound to var.project_id, e.g. \"123456789012/nodrik/allowed\"."
  value       = google_tags_tag_value.allowed.namespaced_name
}

output "policy_name" {
  description = "The full resource name of the policy object this module manages, e.g. \"organizations/123456789012/policies/iam.allowedPolicyMemberDomains\" or \"projects/my-project/policies/iam.allowedPolicyMemberDomains\", depending on var.parent. Fetch it with `gcloud org-policies describe iam.allowedPolicyMemberDomains --organization=<id> --effective` (or --folder / the project-scoped form) to confirm what is actually enforced."
  value       = google_org_policy_policy.domain_restricted_sharing_exception.name
}

output "level" {
  description = "Which level var.parent named — \"organization\" or \"folder-or-project\" — echoed back so you can confirm plan targeted the level you intended before applying."
  value       = local.is_organization ? "organization" : "folder-or-project"
}
