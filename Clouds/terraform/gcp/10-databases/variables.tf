variable "db_admin_user" {
  type = string
}

variable "db_admin_password" {
  type      = string
  sensitive = true
}

variable "db_devuser_password" {
  description = "Not used by this root (the loader creates DevUser); declared so the shared TF_VAR_* set is accepted."
  type        = string
  sensitive   = true
  default     = ""
}
