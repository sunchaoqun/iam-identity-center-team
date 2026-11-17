#!/usr/bin/env bash
# Deploy the near real-time session audit forwarder (EventBridge audit mode).
#  1. ensures an organization CloudTrail trail exists (CloudTrail -> EventBridge needs a logging trail)
#  2. waits until the TEAM Amplify build has created team-audit-bus (+ its org policy)
#  3. deploys a service-managed StackSet with the forwarding rule to every member account/region
# Run AFTER ./deploy.sh. Usage: ./deploy-forwarder.sh
set -e
. "./parameters.sh"
FORWARDER_REGIONS=${FORWARDER_REGIONS:-"$REGION us-east-1"}
CREATE_ORG_TRAIL=${CREATE_ORG_TRAIL:-true}
STACKSET_NAME=TEAM-SESSION-FORWARDER
CENTRAL_BUS_ARN="arn:aws:events:${REGION}:${TEAM_ACCOUNT}:event-bus/team-audit-bus"

MGMT=$(aws sts get-caller-identity --profile "$ORG_MASTER_PROFILE" --query Account --output text)
ORG_ID=$(aws organizations describe-organization --profile "$ORG_MASTER_PROFILE" --query Organization.Id --output text)
ROOT_ID=$(aws organizations list-roots --profile "$ORG_MASTER_PROFILE" --query "Roots[0].Id" --output text)
echo "management=$MGMT org=$ORG_ID root=$ROOT_ID"

# ---------- 1. organization trail ----------
ORG_TRAILS=$(aws cloudtrail describe-trails --region "$REGION" --profile "$ORG_MASTER_PROFILE" \
  --query "trailList[?IsOrganizationTrail==\`true\`].TrailARN" --output text)
if [ -n "$ORG_TRAILS" ]; then
  echo "[OK] organization trail present: $ORG_TRAILS"
elif [ "$CREATE_ORG_TRAIL" = "true" ]; then
  TRAIL=team-org-trail
  BUCKET="team-org-trail-${MGMT}-${REGION}"
  TRAIL_ARN="arn:aws:cloudtrail:${REGION}:${MGMT}:trail/${TRAIL}"
  echo "creating organization trail $TRAIL -> s3://$BUCKET"
  aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com --profile "$ORG_MASTER_PROFILE" || true
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --profile "$ORG_MASTER_PROFILE" --region "$REGION" || true
  else
    aws s3api create-bucket --bucket "$BUCKET" --profile "$ORG_MASTER_PROFILE" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" || true
  fi
  aws s3api put-public-access-block --bucket "$BUCKET" --profile "$ORG_MASTER_PROFILE" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  cat > /tmp/team-trail-policy.json <<EOF
{"Version":"2012-10-17","Statement":[
 {"Sid":"AWSCloudTrailAclCheck","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},
  "Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::${BUCKET}",
  "Condition":{"StringEquals":{"aws:SourceArn":"${TRAIL_ARN}"}}},
 {"Sid":"AWSCloudTrailWrite","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},
  "Action":"s3:PutObject","Resource":["arn:aws:s3:::${BUCKET}/AWSLogs/${MGMT}/*","arn:aws:s3:::${BUCKET}/AWSLogs/${ORG_ID}/*"],
  "Condition":{"StringEquals":{"s3:x-amz-acl":"bucket-owner-full-control","aws:SourceArn":"${TRAIL_ARN}"}}}]}
EOF
  aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/team-trail-policy.json --profile "$ORG_MASTER_PROFILE"
  aws cloudtrail create-trail --name "$TRAIL" --s3-bucket-name "$BUCKET" \
    --is-organization-trail --is-multi-region-trail --enable-log-file-validation \
    --region "$REGION" --profile "$ORG_MASTER_PROFILE"
  aws cloudtrail start-logging --name "$TRAIL" --region "$REGION" --profile "$ORG_MASTER_PROFILE"
  echo "[OK] organization trail created (propagation to member accounts can take a few minutes)"
else
  echo "[FAIL] no organization trail. Create one, or set CREATE_ORG_TRAIL=true"; exit 1
fi

# ---------- 2. wait for central bus from Amplify build ----------
echo "waiting for team-audit-bus (created by the Amplify build, ~20 min after deploy.sh)..."
for i in $(seq 1 60); do
  POL=$(aws events describe-event-bus --name team-audit-bus --region "$REGION" --profile "$TEAM_ACCOUNT_PROFILE" \
        --query Policy --output text 2>/dev/null || true)
  if echo "$POL" | grep -q "$ORG_ID"; then echo "[OK] team-audit-bus ready with org policy"; break; fi
  [ "$i" = 60 ] && { echo "[FAIL] team-audit-bus not ready after 60 min - check Amplify build logs"; exit 1; }
  sleep 60
done

# ---------- 3. StackSet to all member accounts ----------
export AWS_PROFILE=$ORG_MASTER_PROFILE
aws cloudformation activate-organizations-access --region "$REGION" || true
if ! aws cloudformation describe-stack-set --stack-set-name $STACKSET_NAME --region "$REGION" >/dev/null 2>&1; then
  aws cloudformation create-stack-set --region "$REGION" --stack-set-name $STACKSET_NAME \
    --template-body file://session-forwarder.yml \
    --parameters ParameterKey=CentralBusArn,ParameterValue=$CENTRAL_BUS_ARN \
    --permission-model SERVICE_MANAGED \
    --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
    --capabilities CAPABILITY_IAM
  aws cloudformation create-stack-instances --region "$REGION" --stack-set-name $STACKSET_NAME \
    --deployment-targets OrganizationalUnitIds=$ROOT_ID --regions $FORWARDER_REGIONS \
    --operation-preferences FailureToleranceCount=5,MaxConcurrentCount=10
else
  aws cloudformation update-stack-set --region "$REGION" --stack-set-name $STACKSET_NAME \
    --template-body file://session-forwarder.yml \
    --parameters ParameterKey=CentralBusArn,ParameterValue=$CENTRAL_BUS_ARN --capabilities CAPABILITY_IAM
fi
echo "done. check: aws cloudformation list-stack-instances --stack-set-name $STACKSET_NAME --region $REGION --profile $ORG_MASTER_PROFILE"
