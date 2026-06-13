# SecureGate

Automated cloud security scanning platform that integrates SAST and API pentesting directly into the GitHub PR workflow. Every pull request is automatically scanned — results appear as a PR comment and a GitHub status check within approximately 4 minutes.

---

## How It Works

1. Developer opens a pull request in their repository
2. The customer's `security-scan.yml` workflow fires, builds their code into a Docker image, and pushes it to ECR
3. The reusable workflow calls SecureGate's API Gateway, which triggers Lambda 1 (trigger)
4. Lambda 1 writes a `pending` record to DynamoDB and queues a SAST job on SQS
5. The SAST Fargate worker pulls the job, scans the source code, and writes results back to DynamoDB
6. A DynamoDB Stream fires the Severity Check Lambda — if HIGH findings meet the threshold, it fast-blocks without running pentest; otherwise it queues a pentest job
7. The Pentest Fargate worker spins up an ephemeral target container, fires real HTTP requests against it, and writes results to DynamoDB and an HTML report to S3
8. A second DynamoDB Stream fires the Results Lambda (Lambda 2), which posts a PR comment and sets a GitHub status check to pass or fail

---

## Architecture

```
GitHub Actions (customer repo)
        ↓  reusable-scan.yml
API Gateway → Lambda 1 (trigger)
                    ↓
             DynamoDB (pending)
                    ↓
             SQS SAST queue
                    ↓
           Fargate SAST worker
                    ↓
         DynamoDB (sast_complete)
                    ↓
       Severity Check Lambda (DynamoDB Stream)
          ↓ HIGH < threshold          ↓ HIGH >= threshold
  SQS pentest queue              fast_block status
          ↓
  Fargate pentest worker → Fargate target (ephemeral)
          ↓
    DynamoDB (complete) + S3 HTML report
          ↓
    Lambda 2 / Results (DynamoDB Stream)
          ↓
  GitHub PR comment + status check
```

All Fargate tasks run in a private VPC subnet with no internet egress. The ephemeral target container is destroyed after every scan.

---

## Repository Structure

```
SecureGateway/
├── .github/
│   └── workflows/
│       ├── deploy.yml           # Platform deployment (SecureGate team only)
│       └── reusable-scan.yml    # Reusable workflow for customer repos
│
├── containers/
│   ├── sast-worker/             # SAST scanner (Node.js/Express, Fargate)
│   │   ├── server.js
│   │   ├── scanner.js
│   │   ├── package.json
│   │   ├── test-vulnerable.js
│   │   └── Readme.md
│   └── pentest-worker/          # Pentest tool (Node.js/Express, Fargate)
│       ├── server.js
│       ├── tester.js
│       ├── package.json
│       ├── test-target.js
│       └── Readme.Md
│
├── lambdas/
│   ├── trigger/                 # Lambda 1 — receives API call, queues SAST
│   │   ├── index.mjs
│   │   └── package.json
│   ├── severity-check/          # Evaluates SAST results, blocks or queues pentest
│   │   ├── index.mjs
│   │   └── package.json
│   └── results/                 # Lambda 2 — posts GitHub PR comment and status
│       ├── index.mjs
│       └── package.json
│
└── terraform/                   # All AWS infrastructure (Prachit)
    ├── main.tf
    ├── variables.tf
    ├── vpc.tf
    ├── ecs.tf
    ├── sqs.tf
    ├── dynamodb.tf
    ├── s3.tf
    ├── ecr.tf
    ├── iam.tf
    ├── lambda.tf
    ├── apigateway.tf
    ├── secrets.tf
    ├── sns.tf
    └── outputs.tf
```

---

## Platform Setup (SecureGate Team — One Time)

This section is for the SecureGate team deploying the AWS infrastructure. Customers do not run this.

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.3.0
- AWS Academy Learner Lab access
- AWS CLI installed and configured
- Docker (for building container images)

### GitHub Secrets Required

Add these to the SecureGate repo under **Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | From Learner Lab — AWS Details panel |
| `AWS_SECRET_ACCESS_KEY` | From Learner Lab — AWS Details panel |
| `AWS_SESSION_TOKEN` | From Learner Lab — AWS Details panel |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account number |
| `GH_SECRET` | GitHub Personal Access Token (PAT) with `repo` and `statuses:write` scopes |

> **Note:** Learner Lab credentials expire when your session ends. Update all three AWS secrets before re-triggering a deploy.

### Deploying via GitHub Actions

Push to `main` to trigger the full deploy pipeline automatically. The workflow:

1. Runs `terraform apply` to provision all infrastructure
2. Deploys the three Lambda functions with their current code
3. Builds and pushes the SAST and pentest Docker images to ECR
4. Stores the GitHub token in Secrets Manager

### Manual Terraform Deploy (alternative)

```bash
# Set credentials from Learner Lab → AWS Details
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_DEFAULT_REGION=us-east-1

cd terraform
terraform init
terraform plan      # review ~40 resources
terraform apply     # type yes to confirm
```

### Step 6 — Note the outputs

After apply, Terraform prints values needed for customer onboarding:

```
api_gateway_url       = "https://abc123.execute-api.us-east-1.amazonaws.com/prod"
api_key_id            = "abc123"   # retrieve value: aws apigateway get-api-key --api-key <id> --include-value
ecr_client_scans_uri  = "547846986520.dkr.ecr.us-east-1.amazonaws.com/securegateway/client-scans"
```

### Tear Down

```bash
terraform destroy
```

Always destroy before your Learner Lab session ends to avoid resource conflicts on the next session.

---

## ⚠️ Known Pending Issues

### 1. SNS alert email is a placeholder
`terraform/sns.tf` still has `endpoint = "prachit@example.com"`. This must be replaced with a real email address before deploy. CloudWatch alarms fire to this topic — with a fake email, no one receives alerts.

### 2. No Dockerfiles in the repository
`containers/sast-worker/` and `containers/pentest-worker/` both lack a `Dockerfile`. The `deploy.yml` workflow runs `docker build` against these folders and will fail without them. Dockerfiles need to be committed.

Example `Dockerfile` for both workers:
```dockerfile
FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

### 3. DynamoDB Stream filter mismatch (Severity Check Lambda)
`terraform/lambda.tf` filters the DynamoDB Stream for `status = "complete"` to trigger the Severity Check Lambda. But the SAST worker writes `status = "sast_complete"` when it finishes. The filter must be changed to `"sast_complete"` or the Severity Check Lambda will never fire.

### 4. Field name inconsistency: `repo` vs `repoFullName`
The reusable workflow (`reusable-scan.yml`) sends `repoFullName` in the API payload. Lambda 1 (`trigger/index.mjs`) reads the field as `repo`. These need to be aligned — either rename the field in the workflow or add a fallback in Lambda 1: `const repo = body.repo || body.repoFullName`.

### 5. Results Lambda polls wrong status field
`reusable-scan.yml` polls DynamoDB for `status` to know when the scan finishes. The Results Lambda writes `overall_status` as the completion field. The polling loop will spin until timeout because `status` never becomes `"complete"` — only `overall_status` does.

### 6. `reusable-scan.yml` checks for `RESULT = "FAIL"` but Results Lambda writes `"failed"`
The final step in the reusable workflow exits non-zero when `overall_status = "FAIL"`. The Results Lambda sets `overall_status` to either `"complete"` or `"failed"` (lowercase). This means the workflow will always report PASSED even when the scan actually failed.

### 7. AWS session token not passed in reusable workflow
`reusable-scan.yml` uses `aws-actions/configure-aws-credentials` with only `aws-access-key` and `aws-secret-key` — no session token. AWS Academy Learner Lab credentials require a session token. Without it, the DynamoDB polling steps will get `InvalidClientTokenId` errors.

### 8. `terraform/main.tf` uses local state — no S3 backend
State is stored locally, which means it is lost between Learner Lab sessions. The `deploy.yml` workflow works around this with `terraform import` + `terraform destroy` + `terraform apply` on every run, but this is slow and fragile. A proper S3 backend (bucket `securegateway-tfstate-<account-id>`) would make state persistent across sessions.

### 9. `deploy.yml` imports then immediately destroys — Lambda function names will fail
The import step in `deploy.yml` imports Lambda functions under the names `securegateway-lambda-trigger`, `securegateway-lambda-severity-check`, and `securegateway-lambda-results`, but Terraform creates them as `securegateway-trigger`, `securegateway-severity-check`, and `securegateway-results`. Import will succeed on first run then conflict on subsequent runs.

---

## Customer Integration

This section is for development teams integrating SecureGate into their repository.

### Prerequisites

- A GitHub repository with a Node.js API
- Secrets provided by the SecureGate team

### Step 1 — Add secrets to your repository

Go to your repository → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value (provided by SecureGate team) |
|---|---|
| `SECUREGATEWAY_API_GATEWAY_URL` | API Gateway base URL |
| `SECUREGATEWAY_API_KEY` | API key for the platform |
| `SECUREGATEWAY_ECR_REPO` | ECR repository URI for your images |
| `AWS_ACCESS_KEY_ID` | AWS credentials for ECR push |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for ECR push |

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
      api-gateway-url: ${{ secrets.SECUREGATEWAY_API_GATEWAY_URL }}
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
```

List every API endpoint you want pentested. The SAST scan runs on all source files regardless of this config.

### Step 4 — Open a pull request

Open any PR — SecureGate runs automatically. Within 4 minutes you will see a PR comment with a severity summary and a link to the full HTML report, and a GitHub status check blocking merge on HIGH severity findings.

---

## Severity Threshold

By default, merge is blocked when **3 or more HIGH severity** findings are detected across SAST. This is configurable without redeployment:

```bash
aws dynamodb put-item \
  --table-name securegateway-config \
  --item '{"configKey": {"S": "pentest_skip_threshold"}, "value": {"N": "5"}}'
```

Adjust the number to match your team's risk tolerance.

---

## What Gets Scanned

**SAST — static analysis (~40 seconds)**

Scans all JavaScript source files for:

- Hardcoded secrets and API keys
- SQL injection risks
- NoSQL injection risks
- XSS vulnerabilities
- Path traversal issues
- Insecure functions (`eval`, `exec`)
- Hardcoded IP addresses
- Weak randomness
- Sensitive data in logs
- Weak cryptography (MD5, SHA1)

**Pentest — dynamic analysis (~3 minutes)**

Fires real HTTP requests against a live running instance of your API:

- Authentication bypass
- SQL injection
- NoSQL injection
- Rate limiting
- Security headers
- Sensitive data exposure

---

## Environment Variables

### Lambda 1 — trigger

| Variable | Source | Description |
|---|---|---|
| `SAST_QUEUE_URL` | Terraform | SQS SAST queue URL |
| `PENTEST_QUEUE_URL` | Terraform | SQS pentest queue URL |
| `DYNAMODB_TABLE` | Terraform | Scans table name (`securegateway-scans`) |
| `CONFIG_TABLE` | Terraform | Config table name (`securegateway-config`) |

### Severity Check Lambda

| Variable | Source | Description |
|---|---|---|
| `PENTEST_QUEUE_URL` | Terraform | SQS pentest queue URL |
| `DYNAMODB_TABLE` | Terraform | Scans table name |
| `CONFIG_TABLE` | Terraform | Config table name |

### Lambda 2 — results

| Variable | Source | Description |
|---|---|---|
| `DYNAMODB_TABLE` | Terraform | Scans table name |
| `S3_BUCKET` | Terraform | Reports bucket name |
| `GITHUB_SECRET_ARN` | Terraform | Secrets Manager ARN for GitHub token |

### Fargate Workers (SAST and Pentest)

| Variable | Source | Description |
|---|---|---|
| `QUEUE_URL` | Terraform | SQS queue URL for this worker |
| `DYNAMODB_TABLE` | Terraform | Scans table name |
| `S3_BUCKET` | Terraform | Reports bucket name |
| `AWS_REGION` | Terraform | `us-east-1` |

---

## Failure Handling

| Failure | What happens |
|---|---|
| Docker build fails | Workflow stops; AWS is never invoked; cost $0 |
| Fargate task crashes | SQS retries up to 3 times automatically |
| 3 consecutive Fargate failures | Message moved to DLQ; CloudWatch alarm fires to SNS topic |
| Lambda invocation fails | Message moved to Lambda DLQ; CloudWatch alarm fires |
| GitHub API down | DynamoDB Streams retries Lambda 2 for up to 24 hours |
| Duplicate PR push (same commit SHA) | Lambda 1 cache check returns early — scan runs only once per commit |

---

## Cost

| Scale | Scans/month | Estimated cost |
|---|---|---|
| Class project | 50 | ~$1.50/month |
| Small team | 500 | ~$2.30/month |
| Medium org | 5,000 | ~$12/month |
| Large org | 50,000 | ~$106/month |

Fargate is the dominant cost driver. Lambda, SQS, and API Gateway are effectively free at the scales shown above.

---

## Team

CS6620 Cloud Computing — Spring 2026

| Name | Contribution |
|---|---|
| Prachit Tupe | Infrastructure (Terraform), GitHub Actions deploy workflow |
| Parishi Shah | Lambda functions, Fargate container workers, GitHub integration |
