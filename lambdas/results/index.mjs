import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { unmarshall } from "@aws-sdk/util-dynamodb";
import https from "https";

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3 = new S3Client({});
const secretsManager = new SecretsManagerClient({});

async function getGitHubToken() {
  const secret = await secretsManager.send(new GetSecretValueCommand({
    SecretId: process.env.GITHUB_SECRET_ARN
  }));
  return secret.SecretString;
}

async function postGitHubComment(token, repo, prNumber, comment) {
  const [owner, repoName] = repo.split('/');
  const body = JSON.stringify({ body: comment });

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.github.com',
      path: `/repos/${owner}/${repoName}/issues/${prNumber}/comments`,
      method: 'POST',
      headers: {
        'Authorization': `token ${token}`,
        'Content-Type': 'application/json',
        'User-Agent': 'SecureGate',
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function setGitHubStatus(token, repo, commitSha, state, description) {
  const [owner, repoName] = repo.split('/');
  const body = JSON.stringify({
    state,
    description,
    context: 'SecureGate / security-scan'
  });

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.github.com',
      path: `/repos/${owner}/${repoName}/statuses/${commitSha}`,
      method: 'POST',
      headers: {
        'Authorization': `token ${token}`,
        'Content-Type': 'application/json',
        'User-Agent': 'SecureGate',
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function formatPRComment(item, reportUrl) {
  const high = item.highCount || 0;
  const medium = item.mediumCount || 0;
  const low = item.lowCount || 0;
  const blocked = item.fastBlock || high >= (item.threshold || 3);

  return `## 🔒 SecureGate Security Scan Results

**Scan ID:** \`${item.scanId}\`
**Status:** ${blocked ? '🔴 FAILED — merge blocked' : '✅ PASSED — safe to merge'}

### SAST Results
| Severity | Count |
|----------|-------|
| 🔴 High  | ${high} |
| 🟡 Medium | ${medium} |
| 🟢 Low   | ${low} |

${reportUrl ? `[📄 View full report](${reportUrl})` : ''}

${blocked ?
    '⛔ **This PR is blocked. Fix all HIGH severity issues before merging.**' :
    '✅ **This PR passed all security checks and is safe to merge.**'
}`;
}

export const handler = async (event) => {
  console.log('Lambda 2 — results fired');

  for (const record of event.Records) {
    if (record.eventName !== 'MODIFY') continue;

    const newImage = unmarshall(record.dynamodb.NewImage);
    const { scanId, overall_status, status, repo, prNumber } = newImage;

    // Trigger on either overall_status or status field
    if (overall_status !== 'complete' && overall_status !== 'failed' &&
        status !== 'complete' && status !== 'fast_block') continue;

    console.log(`Processing results for scan ${scanId}`);

    // Get presigned S3 report URL
    let reportUrl = null;
    try {
      reportUrl = await getSignedUrl(s3, new GetObjectCommand({
        Bucket: process.env.S3_BUCKET,
        Key: `reports/${scanId}.html`
      }), { expiresIn: 604800 });
    } catch (e) {
      console.log('No S3 report found — skipping report URL');
    }

    const comment = formatPRComment(newImage, reportUrl);
    const blocked = newImage.fastBlock || (newImage.highCount || 0) >= (newImage.threshold || 3);

    // Get GitHub token from Secrets Manager
    const token = await getGitHubToken();

    // Post PR comment
    await postGitHubComment(token, repo, prNumber, comment);

    // Set GitHub status check
    await setGitHubStatus(
      token, repo, scanId,
      blocked ? 'failure' : 'success',
      blocked
        ? `${newImage.highCount || 0} HIGH findings — merge blocked`
        : 'All security checks passed'
    );

    // Update overall_status in DynamoDB
    await dynamo.send(new UpdateCommand({
      TableName: process.env.DYNAMODB_TABLE,
      Key: { scanId },
      UpdateExpression: 'SET overall_status = :os',
      ExpressionAttributeValues: {
        ':os': blocked ? 'failed' : 'complete'
      }
    }));

    console.log(`Posted PR comment and status check for scan ${scanId}`);
  }
};
