terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name_prefix = "${var.name_prefix}-${var.environment}"
  labels = {
    app         = var.name_prefix
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "dataflow.googleapis.com",
    "cloudbuild.googleapis.com",
    "places.googleapis.com"
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "collector" {
  account_id   = "${local.name_prefix}-collector-sa"
  display_name = "Location Collector Cloud Run Service Account"
}

resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-${local.name_prefix}-raw"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy
  labels                      = local.labels

  lifecycle_rule {
    condition {
      age = var.raw_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "raw" {
  dataset_id                 = "location_raw"
  location                   = var.region
  delete_contents_on_destroy = var.force_destroy
  labels                     = local.labels
}

resource "google_bigquery_dataset" "stg" {
  dataset_id                 = "location_stg"
  location                   = var.region
  delete_contents_on_destroy = var.force_destroy
  labels                     = local.labels
}

resource "google_bigquery_dataset" "mart" {
  dataset_id                 = "location_mart"
  location                   = var.region
  delete_contents_on_destroy = var.force_destroy
  labels                     = local.labels
}

resource "google_secret_manager_secret" "google_maps_api_key" {
  secret_id = "google-maps-api-key"
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "seoul_api_key" {
  secret_id = "seoul-api-key"
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "collector_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "collector_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "collector_storage_object_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_project_iam_member" "collector_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.collector.email}"
}

resource "google_cloud_run_v2_service" "collector" {
  name     = "${local.name_prefix}-collector"
  location = var.region
  labels   = local.labels

  template {
    service_account = google_service_account.collector.email
    timeout         = "300s"

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = var.collector_image

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "BQ_RAW_DATASET"
        value = google_bigquery_dataset.raw.dataset_id
      }

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.raw.name
      }

      env {
        name = "GOOGLE_MAPS_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.google_maps_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "SEOUL_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.seoul_api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.collector_bq_data_editor,
    google_project_iam_member.collector_bq_job_user,
    google_project_iam_member.collector_storage_object_creator,
    google_project_iam_member.collector_secret_accessor
  ]
}

resource "google_cloud_scheduler_job" "collector" {
  name        = "${local.name_prefix}-collect-10min"
  description = "Collect Google Places and realtime population data every 10 minutes"
  schedule    = var.scheduler_cron
  time_zone   = "Asia/Seoul"
  region      = var.region

  http_target {
    http_method = "GET"
    uri         = "${google_cloud_run_v2_service.collector.uri}/collect"

    oidc_token {
      service_account_email = google_service_account.collector.email
    }
  }

  depends_on = [google_project_service.apis]
}
