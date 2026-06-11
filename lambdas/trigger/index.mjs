import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sqs = new SQSClient({});

export const handler = async (event) => {
  console.log('SecureGate Lambda 1 — trigger fired');

  let body;
  try {
    body = JSON.parse(event.body || JSON.stringify(event));
  } catch (e) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON' }) };
  }

  const { imageUri, prNumber, commitSha, repo } = body;

  if (!commitSha || !repo) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Missing commitSha or repo' }) };
  }

  // SHA cache check — skip duplicate scans
  console.log(`Checking SHA cache for commit: ${commitSha}`);
  const existing = await dynamo.send(new GetCommand({
    TableName: process.env.DYNAMODB_TABLE,
    Key: { scanId: commitSha }
  }));

  if (existing.Item && existing.Item.status === 'complete') {
    console.log('Cache hit — returning existing result');
    return {
      statusCode: 200,
      body: JSON.stringify({
        scanId: commitSha,
        status: 'cached',
        message: 'Scan already completed for this commit'
      })
    };
  }

  // Read severity threshold from config table
  console.log('Reading severity threshold from config table');
  const config = await dynamo.send(new GetCommand({
    TableName: process.env.CONFIG_TABLE,
    Key: { configKey: 'pentest_skip_threshold' }
  }));
  const threshold = config.Item ? parseInt(config.Item.value) : 3;
  console.log(`Severity threshold: ${threshold}`);

  // Write pending record to DynamoDB
  console.log('Writing pending scan record to DynamoDB');
  await dynamo.send(new PutCommand({
    TableName: process.env.DYNAMODB_TABLE,
    Item: {
      scanId: commitSha,
      imageUri: imageUri || 'unknown',
      prNumber: String(prNumber || '0'),
      repo,
      status: 'pending',
      threshold,
      timestamp: new Date().toISOString(),
      expiresAt: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days TTL
    }
  }));

  // Queue SAST job
  console.log('Queuing SAST job on SQS');
  await sqs.send(new SendMessageCommand({
    QueueUrl: process.env.SAST_QUEUE_URL,
    MessageBody: JSON.stringify({
      scanId: commitSha,
      imageUri,
      prNumber: String(prNumber || '0'),
      repo
    })
  }));

  console.log(`Scan queued successfully for commit ${commitSha}`);

  return {
    statusCode: 200,
    body: JSON.stringify({
      scanId: commitSha,
      status: 'queued',
      message: 'Scan queued successfully'
    })
  };
};
