variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "asia-northeast3"
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "location-trends"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "collector_image" {
  description = "Cloud Run collector container image. Build and push src/collector image to Artifact Registry first."
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "scheduler_cron" {
  description = "Cloud Scheduler cron expression"
  type        = string
  default     = "*/10 * * * *"
}

variable "raw_retention_days" {
  description = "Raw Cloud Storage object retention days"
  type        = number
  default     = 365
}

variable "force_destroy" {
  description = "Allow destroying buckets and datasets with contents. Use false in production."
  type        = bool
  default     = false
}
