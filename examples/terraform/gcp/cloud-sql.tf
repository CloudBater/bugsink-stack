resource "google_sql_database_instance" "bugsink" {
  name             = "${var.name}-pg"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/default"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = false
      backup_retention_settings {
        retained_backups = 7
      }
    }

    disk_autoresize = true
    disk_size       = 10
    disk_type       = "PD_SSD"
  }

  deletion_protection = true
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_sql_user" "bugsink" {
  name     = "bugsink"
  instance = google_sql_database_instance.bugsink.name
  password = random_password.db.result
}

resource "google_sql_database" "bugsink" {
  name     = "bugsink"
  instance = google_sql_database_instance.bugsink.name
}
