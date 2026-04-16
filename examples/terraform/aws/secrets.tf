resource "random_password" "secret_key" {
  length  = 50
  special = false
}

resource "aws_secretsmanager_secret" "secret_key" {
  name = "${var.name}/secret-key"
}

resource "aws_secretsmanager_secret_version" "secret_key" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = random_password.secret_key.result
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.name}/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}
