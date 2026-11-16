#!/usr/bin/env bash
# Deploy the EventBridge session forwarder to all member accounts via a
# service-managed StackSet (run from the organization management account).
# Usage: ./deploy-forwarder.sh   (reads parameters.sh)
set -xe

. "./parameters.sh"

FORWARDER_REGIONS=${FORWARDER_REGIONS:-"$REGION us-east-1"}
STACKSET_NAME=TEAM-SESSION-FORWARDER
CENTRAL_BUS_ARN="arn:aws:events:${REGION}:${TEAM_ACCOUNT}:event-bus/team-audit-bus"

export AWS_PROFILE=$ORG_MASTER_PROFILE

ROOT_ID=$(aws organizations list-roots --query "Roots[0].Id" --output text)

# Enable trusted access for StackSets (no-op if already enabled)
aws cloudformation activate-organizations-access || true

if ! aws cloudformation describe-stack-set --stack-set-name $STACKSET_NAME --region $REGION >/dev/null 2>&1; then
  aws cloudformation create-stack-set --region $REGION \
    --stack-set-name $STACKSET_NAME \
    --template-body file://session-forwarder.yml \
    --parameters ParameterKey=CentralBusArn,ParameterValue=$CENTRAL_BUS_ARN \
    --permission-model SERVICE_MANAGED \
    --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
    --capabilities CAPABILITY_IAM

  aws cloudformation create-stack-instances --region $REGION \
    --stack-set-name $STACKSET_NAME \
    --deployment-targets OrganizationalUnitIds=$ROOT_ID \
    --regions $FORWARDER_REGIONS \
    --operation-preferences FailureToleranceCount=5,MaxConcurrentCount=10
else
  aws cloudformation update-stack-set --region $REGION \
    --stack-set-name $STACKSET_NAME \
    --template-body file://session-forwarder.yml \
    --parameters ParameterKey=CentralBusArn,ParameterValue=$CENTRAL_BUS_ARN \
    --capabilities CAPABILITY_IAM
fi
