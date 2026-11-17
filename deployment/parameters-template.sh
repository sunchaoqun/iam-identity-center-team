# Copyright 2022 Amazon Web Services, Inc
# Licensed under the Apache License, Version 2.0

# ===== Required =====
IDC_LOGIN_URL=https://d-xxxxxxxxxx.awsapps.com/start   # IAM Identity Center > Settings > IPv4-only portal URL
REGION=us-west-2                                        # MUST equal the Identity Center primary Region
TEAM_ACCOUNT=123456789012                               # dedicated TEAM / delegated-admin member account
ORG_MASTER_PROFILE=org-mgmt                             # AWS CLI profile for the management account
TEAM_ACCOUNT_PROFILE=team-acct                          # AWS CLI profile for the TEAM account
TEAM_ADMIN_GROUP="team_admin"
TEAM_AUDITOR_GROUP="team_auditor"

# Session activity audit source:
#   eventbridge  -> near real-time EventBridge + DynamoDB pipeline (recommended; no CloudTrail Lake needed)
#   arn:aws:cloudtrail:...:eventdatastore/... -> existing CloudTrail Lake event data store
#   read | write | read_write | none -> create a NEW CloudTrail Lake store (fails for accounts new to CloudTrail Lake)
CLOUDTRAIL_AUDIT_LOGS=eventbridge

# Secrets Manager secret in TEAM_ACCOUNT/REGION with keys "url" and "AccessToken"
# (GitHub: classic token with scopes repo + admin:repo_hook). Leave empty to use CodeCommit.
SECRET_NAME=TEAM-IDC-APP

# OU account-list cache TTL (seconds). Must be a number.
CACHE_TTL=604800

# ===== EventBridge audit mode =====
# Regions where member-account forwarding rules are deployed (include us-east-1 for IAM/global events)
FORWARDER_REGIONS="us-west-2 us-east-1"
# Create an organization trail automatically if none exists (required for CloudTrail -> EventBridge)
CREATE_ORG_TRAIL=true

# ===== Optional =====
# TAGS="project=iam-identity-center-team environment=prod"
# UI_DOMAIN=portal.example.com
