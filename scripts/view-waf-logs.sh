#!/usr/bin/env bash
#
# Query the WAF logs in CloudWatch Logs Insights and print recent requests:
# timestamp, client IP, country, HTTP method + URI, the WAF action (ALLOW/BLOCK),
# and which rule terminated the request.
#
# Usage:
#   ./view-waf-logs.sh                 # last 30 minutes
#   ./view-waf-logs.sh 120             # last 120 minutes
#   BLOCKED_ONLY=1 ./view-waf-logs.sh  # only blocked requests
#
# Requires: awscli v2, jq. Region/name are read from `terraform output`/vars,
# with env overrides REGION and LOG_GROUP.

set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINUTES="${1:-30}"

REGION="${REGION:-$(terraform -chdir="$TF_DIR" output -raw region 2>/dev/null || echo us-east-1)}"

# Resolve the WAF log group from terraform output, falling back to the default name.
if [[ -z "${LOG_GROUP:-}" ]]; then
  LOG_GROUP="$(terraform -chdir="$TF_DIR" output -raw waf_log_group 2>/dev/null || echo aws-waf-logs-homelab-web)"
fi

echo "Log group: $LOG_GROUP   region: $REGION   window: last ${MINUTES}m"

FILTER=""
if [[ "${BLOCKED_ONLY:-0}" == "1" ]]; then
  FILTER="| filter action = \"BLOCK\""
fi

QUERY=$(cat <<EOF
fields @timestamp, httpRequest.clientIp, httpRequest.country, httpRequest.httpMethod, httpRequest.uri, action, terminatingRuleId
${FILTER}
| sort @timestamp desc
| limit 100
EOF
)

START=$(( $(date +%s) - MINUTES * 60 ))
END=$(date +%s)

QID=$(aws logs start-query \
  --region "$REGION" \
  --log-group-name "$LOG_GROUP" \
  --start-time "$START" \
  --end-time "$END" \
  --query-string "$QUERY" \
  --query 'queryId' --output text)

echo "Query $QID running..."
while true; do
  STATUS=$(aws logs get-query-results --region "$REGION" --query-id "$QID" --query 'status' --output text)
  [[ "$STATUS" == "Complete" ]] && break
  [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" ]] && { echo "Query $STATUS"; exit 1; }
  sleep 2
done

aws logs get-query-results --region "$REGION" --query-id "$QID" --output json \
| jq -r '
  .results[]
  | map({(.field): .value}) | add
  | [ .["@timestamp"], .["httpRequest.clientIp"], .["httpRequest.country"],
      .["httpRequest.httpMethod"], .action, .terminatingRuleId, .["httpRequest.uri"] ]
  | @tsv
' | column -t -s $'\t' || echo "(no results yet — logs can take 1-2 minutes to appear)"
