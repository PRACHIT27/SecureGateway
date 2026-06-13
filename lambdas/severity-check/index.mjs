import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { unmarshall } from "@aws-sdk/util-dynamodb";

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sqs = new SQSClient({});

export const handler = async (event) => {
  console.log('Severity Check Lambda fired');

  for (const record of event.Records) {
    try {
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

        try {
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
          console.log(`Updated scan ${scanId} to fast_block status`);
        } catch (err) {
          console.error(`Failed to update DynamoDB for fast block ${scanId}:`, err);
          throw err;
        }

      } else {
        // Queue pentest and update status in parallel (Fix 2)
        console.log(`Queuing pentest for scan ${scanId}`);

        try {
          // Send message and update DynamoDB in parallel for efficiency
          await Promise.all([
            sqs.send(new SendMessageCommand({
              QueueUrl: process.env.PENTEST_QUEUE_URL,
              MessageBody: JSON.stringify({ scanId, repo, prNumber })
            })),
            dynamo.send(new UpdateCommand({
              TableName: process.env.DYNAMODB_TABLE,
              Key: { scanId },
              UpdateExpression: 'SET #s = :s',
              ExpressionAttributeNames: { '#s': 'status' },
              ExpressionAttributeValues: { ':s': 'pentest_queued' }
            }))
          ]);
          console.log(`Queued pentest and updated status for scan ${scanId}`);
        } catch (err) {
          console.error(`Failed to queue pentest for ${scanId}:`, err);
          throw err;
        }
      }
    } catch (err) {
      console.error(`Error processing record:`, err);
      // Log the error but continue processing other records
      // The record will be retried based on Lambda's event source mapping retry policy
      throw err; // Re-throw to trigger retry from event source
    }
  }
};
