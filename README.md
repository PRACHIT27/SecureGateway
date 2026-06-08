# SecureGate

Automated cloud security scanning platform that integrates SAST and API pentesting directly into the GitHub PR workflow. Every pull request is automatically scanned — results appear as PR comments and status checks within 4 minutes.

---

## How It Works

1. Developer opens a pull request
2. GitHub Actions builds their code into a Docker image and pushes it to ECR
3. SecureGate runs two scans in parallel — static analysis on the source code and live HTTP security tests against the running API
4. Results appear as a PR comment with a full report link and a GitHub status check that blocks merge on critical findings

---

## Architecture

```
GitHub Actions (customer repo)
      ↓
API Gateway → Lambda 1 (trigger)
      ↓                    ↓
SQS SAST queue      SQS pentest queue
      ↓                    ↓
Fargate SAST        Fargate pentest → Fargate target (ephemeral)
      ↓                    ↓
         DynamoDB + S3
              ↓
       Severity Check Lambda
              ↓
         Lambda 2 (results)
              ↓
    GitHub PR comment + status check
```

All Fargate tasks run on a private VPC subnet with no internet egress. The ephemeral target container is destroyed after every scan.

---

## Repository Structure

```
securegateway/
├── terraform/               # Infrastructure as code (Prachit)
│   ├── main.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── ecs.tf
│   ├── sqs.tf
│   ├── dynamodb.tf
│   ├── s3.tf
│   ├── ecr.tf
│   ├── iam.tf
│   └── apigateway.tf
│
├── lambdas/                 # Application logic (Parishi)
│   ├── trigger/
│   ├── severity-check/
│   └── results/
│
├── containers/              # Fargate workers (Parishi)
│   ├── sast-worker/
│   └── pentest-worker/
│
└── .github/
    └── workflows/
        └── reusable-scan.yml   # Reusable workflow for customers
```

---

## Platform Setup (One Time)

This is done once by the SecureGate team to deploy the platform infrastructure.

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- AWS Academy Learner Lab access
- AWS CLI installed and configured

### Step 1 — Configure AWS credentials

Open your AWS Academy Learner Lab, click **AWS Details**, copy the credentials and paste them into your terminal:

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_SESSION_TOKEN=your_session_token
export AWS_DEFAULT_REGION=us-east-1
```

> **Note:** Learner Lab credentials expire when your session ends. Re-export fresh credentials before running Terraform each time.

### Step 2 — Clone the repository

```bash
git clone https://github.com/your-org/securegateway.git
cd securegateway/terraform
```

### Step 3 — Initialise Terraform

```bash
terraform init
```

### Step 4 — Review what will be created

```bash
terraform plan
```

You should see approximately 35 resources to be created including the VPC, ECS cluster, SQS queues, DynamoDB tables, S3 bucket, ECR repositories, IAM roles, and API Gateway.

### Step 5 — Deploy the infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 3-5 minutes.

### Step 6 — Note the outputs

After apply completes, Terraform prints the values you will need for customer onboarding:

```
api_gateway_url     = "https://abc123.execute-api.us-east-1.amazonaws.com/prod"
api_key             = "your-api-key-value"
ecr_repo_uri        = "123456789.dkr.ecr.us-east-1.amazonaws.com/securegateway"
aws_access_key_id   = "AKIA..."
aws_secret_key      = "..."
```

Save these — you will give them to each customer during onboarding.

### Step 7 — Tear down (when done)

```bash
terraform destroy
```

> Always destroy before your Learner Lab session ends to avoid resource issues on the next session.

---

## Customer Integration

This is what a developer team does to integrate SecureGate into their repository.

### Prerequisites

- A GitHub repository with a Node.js API
- Secrets provided by the SecureGate team (see Step 1 below)

### Step 1 — Add secrets to your GitHub repository

Go to your repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following secrets (values provided by SecureGate team):

| Secret name | Description |
|---|---|
| `SECUREGATEWAY_API_KEY` | API key for the SecureGate platform |
| `SECUREGATEWAY_ECR_REPO` | ECR repository URI to push your image to |
| `AWS_ACCESS_KEY_ID` | AWS credentials for ECR access |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for ECR access |

### Step 2 — Add the workflow file

Create `.github/workflows/security-scan.yml` in your repository:

```yaml
name: SecureGate Security Scan

on: [pull_request]

permissions:
  pull-requests: write
  statuses: write

jobs:
  scan:
    uses: your-org/securegateway/.github/workflows/reusable-scan.yml@main
    with:
      ecr-repo: ${{ vars.SECUREGATEWAY_ECR_REPO }}
    secrets:
      api-key: ${{ secrets.SECUREGATEWAY_API_KEY }}
      aws-access-key: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### Step 3 — Add the config file

Create `.securegateway.yml` in the root of your repository:

```yaml
api:
  port: 3000
  start: "npm start"
  healthcheck: /health
  endpoints:
    - path: /api/users
      method: GET
    - path: /api/login
      method: POST
    - path: /api/products
      method: GET
    - path: /api/products/:id
      method: PUT
```

List every endpoint you want pentested. The SAST scan runs on all source files regardless of this config.

### Step 4 — Open a pull request

That is the entire setup. Open a PR and SecureGate runs automatically. Within 4 minutes you will see:

- A PR comment with a severity summary and a link to the full HTML report
- GitHub status checks — `sast-scan` and `pentest-scan` — blocking merge if HIGH severity findings are found

---

## Severity Threshold

By default merge is blocked when **3 or more HIGH severity** findings are detected. This threshold is configurable without redeployment:

```bash
aws dynamodb put-item \
  --table-name securegateway-config \
  --item '{"configKey": {"S": "pentest_skip_threshold"}, "value": {"N": "5"}}'
```

Change the number to whatever threshold fits your team's risk tolerance.

---

## What Gets Scanned

**SAST (static analysis — ~40 seconds)**
Scans all JavaScript source files for:
- Hardcoded secrets and API keys
- SQL injection risks
- NoSQL injection risks
- XSS vulnerabilities
- Path traversal issues
- Insecure functions (eval, exec)
- Hardcoded IP addresses
- Weak randomness
- Sensitive data in logs
- Weak cryptography (MD5, SHA1)

**Pentest (dynamic analysis — ~3 minutes)**
Fires real HTTP requests against a live running instance of your API:
- Authentication bypass
- SQL injection
- NoSQL injection
- Rate limiting
- Security headers
- Sensitive data exposure

---

## Failure Handling

| Failure | What happens |
|---|---|
| Docker build fails | Workflow stops, AWS never invoked, cost $0 |
| Fargate task crashes | SQS retries automatically up to 3 times |
| 3 consecutive failures | Message moved to dead letter queue, CloudWatch alarm fires to your email |
| GitHub API down | DynamoDB Streams retries Lambda 2 for up to 24 hours |

---

## Cost

| Scale | Scans/month | Estimated cost |
|---|---|---|
| Class project | 50 | ~$1.50/month |
| Small team | 500 | ~$2.30/month |
| Medium org | 5,000 | ~$12/month |
| Large org | 50,000 | ~$106/month |

Fargate is the dominant cost. Lambda, SQS, and API Gateway are effectively free at all scales shown above.

---

## Team

CS6620 Cloud Computing — Spring 2026

| Name | Contribution |
|---|---|
| Prachit Tupe | Infrastructure (Terraform), GitHub Actions workflow |
| Parishi Shah | Lambda functions, Fargate containers, GitHub integration |
