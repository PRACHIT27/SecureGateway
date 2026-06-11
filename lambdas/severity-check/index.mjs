import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { unmarshall } from "@aws-sdk/util-dynamodb";

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sqs = new SQSClient({});

export const handler = async (event) => {
  console.log('Severity Check Lambda fired');

  for (const record of event.Records) {
    if (record.eventName !== 'MODIFY') continue;

    const newImage = unmarshall(record.dynamodb.NewImage);
    const { scanId, status, highCount, repo, prNumber, threshold } = newImage;

    if (status !== 'sast_complete') continue;

    console.log(`Processing severity check for scan ${scanId}`);
    console.log(`HIGH findings: ${highCount}, threshold: ${threshold}`);

    const high = highCount || 0;
    const limit = threshold || 3;

    if (high >= limit) {
      // Fast block — skip pentest
      console.log(`Fast block — ${high} HIGH findings exceeds threshold of ${limit}`);

      await dynamo.send(new UpdateCommand({
        TableName: process.env.DYNAMODB_TABLE,
        Key: { scanId },
        UpdateExpression: 'SET #s = :s, fastBlock = :fb',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: {
          ':s': 'fast_block',
          ':fb': true
        }
      }));

    } else {
      // Queue pentest
      console.log(`Queuing pentest for scan ${scanId}`);

      await sqs.send(new SendMessageCommand({
        QueueUrl: process.env.PENTEST_QUEUE_URL,
        MessageBody: JSON.stringify({ scanId, repo, prNumber })
      }));

      await dynamo.send(new UpdateCommand({
        TableName: process.env.DYNAMODB_TABLE,
        Key: { scanId },
        UpdateExpression: 'SET #s = :s',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: { ':s': 'pentest_queued' }
      }));
    }
  }
};
