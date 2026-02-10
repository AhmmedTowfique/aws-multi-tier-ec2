# Multi-Stack DevOps Infrastructure Automation (AWS + Terraform + Ansible)

A fully automated multi-service voting application deployed on AWS, combining multiple technology stacks with Infrastructure-as-Code tooling and secure deployment practices.

---

## Project Overview

This project provisions, configures, and deploys a microservice-based voting application on AWS EC2 using a complete DevOps toolchain. The application consists of three independently containerized services — built with Python (Flask), Node.js (Express), and C# (.NET) — all orchestrated through Docker Compose and deployed to cloud infrastructure managed entirely through code.

The application was first built and tested locally using Docker Compose, then deployed to AWS — following a real-world development workflow of local validation before cloud deployment. Infrastructure was provisioned with Terraform, servers were configured with Ansible, and containers were deployed securely through a Bastion Host — without any manual setup on the target machines.

---

## Architecture

```
Internet
   │
   ▼
[ Bastion Host ] ── public subnet
   │
   ▼ (SSH tunnel)
[ App Servers ]  ── private subnet
   ├── Flask (Python) - Voting Service
   ├── Express (Node.js) - Result Service
   └── .NET (C#) - Worker Service
```

- **VPC** with public and private subnets
- **Bastion Host** in the public subnet for secure SSH access
- **EC2 instances** in private subnets running the application services
- **Security Groups** controlling traffic between tiers
- **Ansible** connects through the Bastion Host to configure and deploy to private instances

---

## Tech Stack

| Category | Tools |
|---|---|
| Cloud Provider | AWS (VPC, EC2, Subnets, Security Groups) |
| Infrastructure as Code | Terraform |
| Configuration Management | Ansible |
| Containerization | Docker, Docker Compose |
| Application Services | Python (Flask), Node.js (Express), C# (.NET) |
| Access Pattern | Bastion Host (jump server) |

---

## What I Built

**Infrastructure (Terraform)**
- Provisioned a custom VPC with public and private subnets
- Created EC2 instances with appropriate IAM and networking
- Defined security groups to restrict traffic between the Bastion Host, application servers, and the internet
- Managed the full lifecycle with `terraform init`, `plan`, `apply`, and `destroy`

**Configuration & Deployment (Ansible)**
- Wrote Ansible playbooks to install Docker and deploy containers on private EC2 instances
- Configured SSH access through the Bastion Host using ProxyJump
- Automated the entire deployment — no manual SSH into target machines required

**Application (Docker)**
- Containerized three microservices using Dockerfiles
- Used Docker Compose to define and run the multi-container application locally
- Each service runs independently and communicates over a shared Docker network

---

## Key Learnings

- How to design a **secure network topology** on AWS with public/private subnet separation
- Using a **Bastion Host** as a controlled entry point into private infrastructure
- Writing **Terraform configurations** to manage cloud resources declaratively
- Using **Ansible over SSH tunnels** to automate remote server setup without direct access
- Containerizing applications across **multiple languages and frameworks**
- Understanding the end-to-end flow from **infrastructure provisioning → configuration → deployment**

---

## How to Run

### Prerequisites
- AWS account with CLI configured
- Terraform installed
- Ansible installed
- Docker & Docker Compose installed

### Steps

1. **Provision infrastructure**
   ```bash
   cd terraform/
   terraform init
   terraform plan
   terraform apply
   ```

2. **Configure and deploy with Ansible**
   ```bash
   cd ansible/
   ansible-playbook -i inventory playbook.yml
   ```

3. **Run locally with Docker Compose**
   ```bash
   docker-compose up --build
   ```

---

## Note

The voting application is based on [Docker's example voting app](https://github.com/dockersamples/example-voting-app). My focus in this project was on the **infrastructure automation, secure network design, and deployment pipeline** — not the application code itself.

## Project Status

This was a bootcamp project focused on building a strong foundation in cloud automation and DevOps practices. It represents my hands-on experience with real-world infrastructure tooling in a secure, multi-tier AWS environment.

---

## Future Improvements

- Add a CI/CD pipeline (e.g. GitHub Actions) for automated deployments
- Introduce monitoring with CloudWatch or Prometheus/Grafana
- Migrate to ECS or Kubernetes for container orchestration
- Add Terraform remote state with S3 backend and state locking via DynamoDB
