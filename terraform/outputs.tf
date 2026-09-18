output "notification_channel_ids" {
  description = <<-EOT
    The created notification channel's resource name per project, e.g.
    projects/<id>/notificationChannels/<n>. Attach this channel to the
    alert policies you want investigated.
  EOT
  value = {
    for project_id, channel in google_monitoring_notification_channel.nodrik :
    project_id => channel.name
  }
}

output "granted_roles" {
  description = <<-EOT
    The exact roles this module grants to tenant_service_account: the
    four viewer roles, plus one custom role per family in var.families
    (by its project-scoped name). This is the complete access list —
    nothing else is ever requested.
  EOT
  value = concat(
    local.roles,
    sort([for binding in google_project_iam_member.nodrik_family : binding.role]),
  )
}

output "family_roles" {
  description = <<-EOT
    The custom roles this module defined, per project and family, with
    their permission lists — every one a get or a list. Empty when
    var.families is empty. For your own verification.
  EOT
  value = {
    for key, role in google_project_iam_custom_role.nodrik :
    key => { name = role.name, permissions = role.permissions }
  }
}

output "project_numbers" {
  description = <<-EOT
    Project number per project id. Send these to Nodrik — alerts cannot
    reach the tenant topic until we grant your projects' Cloud Monitoring
    service agent publish rights on it, which is the one step this
    module cannot do on your behalf (see main.tf).
  EOT
  value = {
    for project_id, project in data.google_project.target :
    project_id => project.number
  }
}
