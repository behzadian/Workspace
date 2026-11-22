variable "aws_region" {
  type        = string
  description = "AWS region where resources will be deployed"
  default     = "eu-central-1"
}

variable "pax_tag" {
  type        = string
  description = "Container image tag (PAX_TAG)"
  default     = "main"
}

# ------------------------------------------------------------------------------
# GitHub Container Registry (GHCR) Credentials
# ------------------------------------------------------------------------------
variable "ghcr_username" {
  type        = string
  description = "GitHub username for pulling ghcr.io/payamax/* images"
}

variable "ghcr_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token (read:packages) for pulling ghcr.io/payamax/* images"
}

# ------------------------------------------------------------------------------
# PostgreSQL RDS Variables (from pgdb)
# ------------------------------------------------------------------------------
variable "postgres_engine_version" {
  type        = string
  description = "Amazon RDS PostgreSQL major version"
  default     = "18.4"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance size"
  default     = "db.t4g.micro"
}

variable "pg_pax_dml_api_pwd" {
  type        = string
  sensitive   = true
  description = "API DML database user password (PAX_PG_PAX_DML_API_PWD)"
}

variable "pg_pax_ddl_fw_pwd" {
  type        = string
  sensitive   = true
  description = "Framework DDL database user password (PAX_PG_PAX_DDL_FW_PWD)"
}

variable "pg_kc_owner_pwd" {
  type        = string
  sensitive   = true
  description = "Keycloak database owner password (PAX_PG_KC_OWNER_PWD)"
}

# ------------------------------------------------------------------------------
# Application & Keycloak Variables (from pax_api, pax_admin, kckc)
# ------------------------------------------------------------------------------
variable "kc_admin_pwd" {
  type        = string
  sensitive   = true
  description = "Keycloak admin password (KC_ADMIN_PWD)"
}

variable "pax_kc_realm" {
  type        = string
  description = "Keycloak realm name (PAX_KC_REALM)"
  default     = "pax"
}

variable "pax_auth_realm_url" {
  type        = string
  description = "Auth realm URL for pax_api (PAX_AUTH_REALM_URL)"
  default     = "https://auth.pax.no1.ir"
}

variable "pax_admin_url" {
  type        = string
  description = "Admin URL for pax_api (PAX_ADMIN_URL)"
  default     = "https://admin.pax.no1.ir"
}

variable "pax_api_url" {
  type        = string
  description = "API URL for pax_admin (PAX_API_URL)"
  default     = "https://api.pax.no1.ir"
}