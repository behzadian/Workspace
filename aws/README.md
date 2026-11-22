# PayamaX AWS Terraform Deployment

Deploys `pgdb` (Amazon RDS PostgreSQL), `kckc` (Keycloak on ECS Fargate), `pax_api` (ECS Fargate), and `pax_admin` (ECS Fargate).

## Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.11.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials (`aws configure`)
- A GitHub Personal Access Token (PAT) with `read:packages` scope to pull `ghcr.io/payamax/*` images

## Quick Start

1. **Configure variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your passwords, tokens, and URLs