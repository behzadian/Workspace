# ------------------------------------------------------------------------------
# 1. NETWORKING & INTERNAL SERVICE DISCOVERY
# ------------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_service_discovery_private_dns_namespace" "pax_ns" {
  name        = "pax.local"
  description = "Internal DNS matching Docker Compose hostnames"
  vpc         = data.aws_vpc.default.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "pax-ecs-sg"
  description = "Allow inbound app ports and internal service communication"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "pax_admin HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "pax_api and kckc HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "pax-rds-sg"
  description = "Allow PostgreSQL traffic only from ECS containers"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }
}

# ------------------------------------------------------------------------------
# 2. POSTGRESQL DATABASE (Translated from: pgdb)
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "pax_db_subnets" {
  name       = "pax-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "pgdb" {
  identifier             = "pax-svc-pg-eg"
  engine                 = "postgres"
  engine_version         = var.postgres_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.pax_pg_pg_db
  username               = var.pax_pg_pg_usr
  password               = var.pax_pg_pg_pwd
  db_subnet_group_name   = aws_db_subnet_group.pax_db_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
}

# ------------------------------------------------------------------------------
# 3. ECS CLUSTER, LOGGING, IAM & GHCR AUTHENTICATION
# ------------------------------------------------------------------------------
resource "aws_ecs_cluster" "pax_cluster" {
  name = "payamax-cluster"
}

resource "aws_cloudwatch_log_group" "pax_logs" {
  for_each          = toset(["kc", "pax-api", "pax-admin"])
  name              = "/ecs/payamax/${each.key}"
  retention_in_days = 14
}

resource "aws_secretsmanager_secret" "ghcr_creds" {
  name                    = "payamax-ghcr-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "ghcr_creds_val" {
  secret_id = aws_secretsmanager_secret.ghcr_creds.id
  secret_string = jsonencode({
    username = var.ghcr_username
    password = var.ghcr_token
  })
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "pax-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "pax-ecs-read-ghcr-secret"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.ghcr_creds.arn]
    }]
  })
}

# ------------------------------------------------------------------------------
# 4. KEYCLOAK SERVICE (Translated from: kckc / hostname: kc)
# ------------------------------------------------------------------------------
resource "aws_service_discovery_service" "kc_dns" {
  name = "kc"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.pax_ns.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "kc" {
  family                   = "pax-svc-kc-eg"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "kckc"
      image     = "ghcr.io/payamax/kcxkc-go:${var.pax_tag}"
      essential = true
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.ghcr_creds.arn
      }
      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "PAX_PG_KC_OWNER_PWD", value = var.pax_pg_kc_owner_pwd },
        { name = "PAX_KC_ADMIN_PWD", value = var.pax_kc_admin_pwd },
        { name = "KC_DB_URL_HOST", value = aws_db_instance.pgdb.address },
        { name = "KC_DB_URL_PORT", value = "5432" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pax_logs["kc"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "kc" {
  name            = "pax-kc"
  cluster         = aws_ecs_cluster.pax_cluster.id
  task_definition = aws_ecs_task_definition.kc.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kc_dns.arn
  }

  depends_on = [aws_db_instance.pgdb]
}

# ------------------------------------------------------------------------------
# 5. PAX API SERVICE (Translated from: pax_api / hostname: pax-api)
# ------------------------------------------------------------------------------
resource "aws_service_discovery_service" "pax_api_dns" {
  name = "pax-api"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.pax_ns.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "pax_api" {
  family                   = "pax-svc-pax-ap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "pax_api"
      image     = "ghcr.io/payamax/api-go:${var.pax_tag}"
      essential = true
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.ghcr_creds.arn
      }
      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "PAX_PG_HOST", value = aws_db_instance.pgdb.address },
        { name = "PAX_PG_PORT", value = "5432" },
        { name = "PAX_PG_DB", value = var.pax_pg_pg_db },
        { name = "PAX_PG_PAX_DML_API_PWD", value = var.pax_pg_pax_dml_api_pwd },
        { name = "PAX_PG_PAX_DDL_FW_PWD", value = var.pax_pg_pax_ddl_fw_pwd },
        { name = "PAX_AUTH_REALM_URL", value = var.pax_auth_realm_url },
        { name = "PAX_FILES_PUB_URL", value = var.pax_files_pub_url },
        { name = "PAX_ADMIN_URL", value = var.pax_admin_url }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && printf \"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n\" >&3 && head -n 1 <&3'"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 10
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pax_logs["pax-api"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "pax_api" {
  name            = "pax-api"
  cluster         = aws_ecs_cluster.pax_cluster.id
  task_definition = aws_ecs_task_definition.pax_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.pax_api_dns.arn
  }

  depends_on = [aws_db_instance.pgdb]
}

# ------------------------------------------------------------------------------
# 6. PAX ADMIN SERVICE (Translated from: pax_admin / hostname: pax-admin)
# ------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "pax_admin" {
  family                   = "pax-svc-pax-ad"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "pax_admin"
      image     = "ghcr.io/payamax/admin-go:${var.pax_tag}"
      essential = true
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.ghcr_creds.arn
      }
      portMappings = [
        { containerPort = 80, hostPort = 80, protocol = "tcp" }
      ]
      environment = [
        { name = "PAX_KC_URL", value = var.pax_kc_url },
        { name = "PAX_KC_REALM", value = var.pax_kc_realm },
        { name = "PAX_API_URL", value = var.pax_api_url }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pax_logs["pax-admin"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "pax_admin" {
  name            = "pax-admin"
  cluster         = aws_ecs_cluster.pax_cluster.id
  task_definition = aws_ecs_task_definition.pax_admin.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_service.pax_api]
}