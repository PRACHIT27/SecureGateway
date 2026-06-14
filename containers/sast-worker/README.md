# SAST Worker — SecureGate

Static Application Security Testing (SAST) container. Runs as an AWS Fargate task. Pulls scan jobs from SQS, runs the scanner against the customer's Docker image source code, writes results to DynamoDB, and uploads an HTML report to S3.

---

## How It Fits in the Pipeline

```
SQS (sast-queue)
       ↓
Fargate SAST Worker (this container)
       ↓
DynamoDB: status = "sast_complete", highCount, mediumCount, lowCount
       ↓
S3: reports/<scanId>.html
```

The SAST worker is triggered by SQS — it polls the queue continuously and processes one message at a time.

---

## Vulnerabilities Detected

| ID | Name | Severity | Description |
|----|------|----------|-------------|
| `HARDCODED_SECRET` | Hardcoded Secrets | HIGH | API keys, passwords, tokens in source code |
| `SQL_INJECTION` | SQL Injection Risk | HIGH | String concatenation in SQL queries |
| `NOSQL_INJECTION` | NoSQL Injection Risk | HIGH | Unsanitized input in NoSQL queries |
| `XSS` | Cross-Site Scripting | HIGH | Unescaped user input in HTML output |
| `PATH_TRAVERSAL` | Path Traversal | HIGH | Unvalidated file path inputs |
| `INSECURE_FUNCTION` | Insecure Function Usage | HIGH | Dangerous functions like `eval()`, `exec()` |
| `HARDCODED_IP` | Hardcoded IP Address | MEDIUM | IP addresses that should be configurable |
| `WEAK_CRYPTO` | Weak Cryptography | MEDIUM | MD5, SHA1, or deprecated crypto functions |
| `SENSITIVE_LOG` | Sensitive Data in Logs | MEDIUM | Passwords or tokens written to logs |
| `WEAK_RANDOM` | Weak Randomness | LOW | `Math.random()` used for security decisions |
| `SECURITY_TODO` | Security TODO/FIXME | LOW | Security-related comments needing attention |

---

## Environment Variables

These are injected by Terraform into the ECS task definition:

| Variable | Description |
|---|---|
| `QUEUE_URL` | SQS queue URL — the worker polls this for jobs |
| `DYNAMODB_TABLE` | DynamoDB scans table name |
| `S3_BUCKET` | S3 bucket name for HTML reports |
| `AWS_REGION` | AWS region (e.g., `us-east-1`) |
| `MAX_WAIT_SECONDS` | Max time to wait for a job before exiting (default: 600) |

---

## Local Development

```bash
# Install dependencies
npm install

# Start the HTTP server (for local testing only — Fargate runs server.js)
node server.js
```

The server starts on port 3000 (or `PORT` environment variable).

### HTTP API (for local testing)

**Health check**
```
GET /health
```

**Scan a code snippet**
```
POST /scan/code
Content-Type: application/json

{ "code": "const password = 'secret123';", "filename": "app.js" }
```

**Scan a file**
```
POST /scan/file
Content-Type: application/json

{ "filepath": "./test-vulnerable.js" }
```

**Scan a directory**
```
POST /scan/directory
Content-Type: application/json

{ "dirpath": "./src" }
```

**List all vulnerability types**
```
GET /vulnerabilities
```

### Test with the included vulnerable sample

```bash
# Terminal 1
node server.js

# Terminal 2
curl -X POST http://localhost:3000/scan/file \
  -H "Content-Type: application/json" \
  -d '{"filepath": "./test-vulnerable.js"}'
```

---

## Example Response

```json
{
  "success": true,
  "filename": "app.js",
  "scannedAt": "2026-06-13T10:30:00.000Z",
  "summary": {
    "totalVulnerabilities": 3,
    "high": 2,
    "medium": 1,
    "low": 0
  },
  "vulnerabilities": [
    {
      "id": "HARDCODED_SECRET",
      "name": "Hardcoded Secret",
      "severity": "HIGH",
      "description": "Hardcoded password",
      "message": "Hardcoded secret detected. Move secrets to environment variables.",
      "file": "app.js",
      "line": 5,
      "column": 7,
      "evidence": "const password = 'secret123';"
    }
  ]
}
```

---

## Project Structure

```
sast-worker/
├── server.js           # Express HTTP server (local testing + Fargate entry point)
├── scanner.js          # Core SAST scanning logic
├── package.json        # Dependencies
├── test-vulnerable.js  # Sample vulnerable file for local testing
└── Readme.md           # This file
```

---

## ⚠️ Known Pending Issues

**Missing Dockerfile** — The container cannot be built or deployed without a `Dockerfile`. Create one in this folder:

```dockerfile
FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

**Missing SQS worker loop** — `server.js` starts an HTTP server suitable for local testing, but in production the Fargate task needs to poll SQS, pull a scan job, run the scan, write results to DynamoDB, and upload to S3. A `worker.js` file handling this loop needs to be created and set as the Dockerfile `CMD`.

**DynamoDB status field** — When the scan completes, the worker must write `status = "sast_complete"` (not `"complete"`) to trigger the Severity Check Lambda. Confirm the worker uses exactly this string.
