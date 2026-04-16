resource "aws_db_subnet_group" "bugsink" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Allow 5432 from EKS nodes"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "rds_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.eks_node_sg_id
  security_group_id        = aws_security_group.rds.id
  description              = "Postgres from EKS nodes"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_instance" "bugsink" {
  identifier             = "${var.name}-pg"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = "gp3"
  db_name                = "bugsink"
  username               = "bugsink"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.bugsink.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.name}-pg-final"

  deletion_protection = true
}
