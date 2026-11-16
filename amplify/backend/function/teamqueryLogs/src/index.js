//  © 2023 Amazon Web Services, Inc. or its affiliates. All Rights Reserved.
//  This AWS Content is provided subject to the terms of the AWS Customer Agreement available at
//  http: // aws.amazon.com/agreement or other written agreement between Customer and either
//  Amazon Web Services, Inc. or Amazon Web Services EMEA SARL or both.
const EventDataStore = (process.env.EVENT_DATA_STORE).split("/").pop();
const REGION = process.env.REGION;
const {
    CloudTrailClient,
    paginateGetQueryResults,
  } = require("@aws-sdk/client-cloudtrail");
  const client = new CloudTrailClient({ region: REGION });


const get_query = async (queryId) => {
try {
    const output = [];
    const input = {
    EventDataStore: EventDataStore,
    QueryId: queryId,
    };
    const paginatorConfig = {
    client: new CloudTrailClient({ region: REGION }),
    };
    const paginator = paginateGetQueryResults(paginatorConfig, input);
    for await (const page of paginator) {
    // page contains a single paginated output.
    for (const data of page.QueryResultRows) {
        const logs = {};
        for (const log of data) {
        for (const [k, v] of Object.entries(log)) {
            logs[k] = v;
        }
        }
        output.push(logs);
    }
    }
    console.log(output);
    return output;
} catch (err) {
    console.log("Error", err);
}
};
  
// EventBridge + DynamoDB mode
const { DynamoDBClient, QueryCommand } = require("@aws-sdk/client-dynamodb");
const ddb = new DynamoDBClient({ region: REGION });
const SESSION_EVENTS_TABLE = process.env.SESSION_EVENTS_TABLE;

const get_ddb_logs = async (queryId) => {
  try {
    const p = JSON.parse(Buffer.from(queryId.slice(4), "base64").toString("utf8"));
    const output = [];
    let ExclusiveStartKey;
    do {
      const res = await ddb.send(new QueryCommand({
        TableName: SESSION_EVENTS_TABLE,
        KeyConditionExpression: "pk = :pk AND sk BETWEEN :s AND :e",
        ExpressionAttributeValues: {
          ":pk": { S: `${p.accountId}#${p.username}` },
          ":s": { S: p.startTime },
          ":e": { S: `${p.endTime}~` },
        },
        ExclusiveStartKey,
      }));
      for (const it of res.Items || []) {
        const roleName = it.roleName ? it.roleName.S : "";
        if (p.role && !roleName.includes(p.role)) continue;
        output.push({
          eventID: it.eventID ? it.eventID.S : "",
          eventName: it.eventName ? it.eventName.S : "",
          eventSource: it.eventSource ? it.eventSource.S : "",
          eventTime: it.eventTime ? it.eventTime.S : "",
        });
      }
      ExclusiveStartKey = res.LastEvaluatedKey;
    } while (ExclusiveStartKey);
    return output;
  } catch (err) {
    console.log("Error", err);
  }
};

exports.handler = async (event) => {
    const queryId = event["arguments"]["queryId"]
    if (queryId && queryId.startsWith("ddb:")) {
      return get_ddb_logs(queryId);
    }
    return get_query(queryId);
};
