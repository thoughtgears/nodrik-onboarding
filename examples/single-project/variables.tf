variable "project_id" {
  description = "The GCP project Nodrik should investigate."
  type        = string
}

variable "tenant_service_account" {
  description = "The service account Nodrik gave you during onboarding."
  type        = string
}

variable "tenant_topic" {
  description = "Your alert intake topic, as the full resource path Nodrik gave you."
  type        = string
}
