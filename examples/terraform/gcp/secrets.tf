resource "random_password" "secret_key" {
  length  = 50
  special = false
}

resource "google_secret_manager_secret" "secret_key" {
  secret_id = "${var.name}-secret-key"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret_key" {
  secret      = google_secret_manager_secret.secret_key.id
  secret_data = random_password.secret_key.result
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.name}-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}
