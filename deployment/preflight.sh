#!/usr/bin/env bash
# Preflight checks for TEAM deployment. Fails fast on the issues hit in practice.
set -e
. "./parameters.sh"
CACHE_TTL=${CACHE_TTL:-604800}
CLOUDTRAIL_AUDIT_LOGS=${CLOUDTRAIL_AUDIT_LOGS:-eventbridge}
ok(){ echo "  [OK]   $1"; }; bad(){ echo "  [FAIL] $1"; FAIL=1; }; warn(){ echo "  [WARN] $1"; }
FAIL=0
echo "== TEAM preflight =="

# 1. parameters contain no stray backslashes (copy/paste from chat/markdown)
if grep -q '\\_' parameters.sh; then bad "parameters.sh contains '\\_' (copy/paste artifact) - fix variable names"; else ok "parameters.sh syntax"; fi

# 2. CACHE_TTL numeric
[[ "$CACHE_TTL" =~ ^[0-9]+$ ]] && ok "CACHE_TTL=$CACHE_TTL" || bad "CACHE_TTL must be a number"

# 3. audit mode
case "$CLOUDTRAIL_AUDIT_LOGS" in
  eventbridge) ok "audit mode: eventbridge (no CloudTrail Lake)";;
  arn:*) ok "audit mode: existing CloudTrail Lake store";;
  read|write|read_write|none) warn "audit mode '$CLOUDTRAIL_AUDIT_LOGS' CREATES a CloudTrail Lake store. CloudTrail Lake no longer accepts new customers since 2026-05-31; use 'eventbridge' unless this org already uses Lake.";;
  *) bad "CLOUDTRAIL_AUDIT_LOGS invalid: $CLOUDTRAIL_AUDIT_LOGS";;
esac

# 4. credentials valid
for P in "$ORG_MASTER_PROFILE" "$TEAM_ACCOUNT_PROFILE"; do
  A=$(aws sts get-caller-identity --profile "$P" --query Account --output text 2>/dev/null) \
    && ok "profile $P -> $A" \
    || bad "profile $P not usable (run: aws sso login --profile $P)"
done
T=$(aws sts get-caller-identity --profile "$TEAM_ACCOUNT_PROFILE" --query Account --output text 2>/dev/null || true)
[ -n "$T" ] && [ "$T" != "$TEAM_ACCOUNT" ] && bad "TEAM_ACCOUNT_PROFILE points to $T, expected $TEAM_ACCOUNT"

# 5. Identity Center region
IDC=$(aws sso-admin list-instances --region "$REGION" --profile "$ORG_MASTER_PROFILE" --query "Instances[0].InstanceArn" --output text 2>/dev/null || true)
[ -n "$IDC" ] && [ "$IDC" != "None" ] && ok "Identity Center found in $REGION" || bad "No Identity Center instance in $REGION (REGION must equal Identity Center Region)"

# 6. secret exists in TEAM account and has the right keys
if [ -n "$SECRET_NAME" ]; then
  S=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$REGION" --profile "$TEAM_ACCOUNT_PROFILE" --query SecretString --output text 2>/dev/null || true)
  if [ -z "$S" ]; then bad "secret $SECRET_NAME not found in TEAM account $TEAM_ACCOUNT / $REGION (it must be in the TEAM account, not management)"
  else
    echo "$S" | grep -q '"url"' && echo "$S" | grep -q '"AccessToken"' && ok "secret $SECRET_NAME has url + AccessToken" || bad "secret must contain keys exactly 'url' and 'AccessToken'"
  fi
fi

[ "$FAIL" = 0 ] && echo "== preflight passed ==" || { echo "== preflight FAILED - fix the items above =="; exit 1; }
