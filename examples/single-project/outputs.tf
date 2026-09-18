output "notification_channel_ids" {
  value = module.nodrik.notification_channel_ids
}

output "granted_roles" {
  value = module.nodrik.granted_roles
}

output "project_numbers" {
  description = "Send these to Nodrik — see terraform/README.md."
  value       = module.nodrik.project_numbers
}
