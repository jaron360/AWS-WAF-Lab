<h1 align="center">🛡️ AWS WAF Lab</h1>

<p align="center">
  <strong>Watch real internet traffic hit a load balancer — and see exactly what AWS WAF allows and blocks.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white" alt="Terraform">
  <img src="https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazonwebservices&logoColor=FF9900" alt="AWS">
  <img src="https://img.shields.io/badge/Security-AWS_WAFv2-DD344C?logo=amazonwebservices&logoColor=white" alt="AWS WAF">
  <img src="https://img.shields.io/badge/Terraform-%E2%89%A5%201.5.7-844FBA" alt="Terraform version">
</p>

---

A small, production-shaped web tier on AWS built for one purpose: **observe live internet
traffic reaching a load balancer and analyze how AWS WAF responds to it.** Deploy it with
Terraform, throw traffic at it (benign and malicious), then read the WAF logs to see what
got through and what got blocked.

### What gets deployed

| | Component | Description |
|---|---|---|
| 🌐 | **VPC** | Spans 2 Availability Zones — 2 public subnets (ALB) + 2 private subnets (web servers) |
| 🖥️ | **2 EC2 instances** | One per private subnet; each serves a tiny page showing its instance ID and AZ |
| ⚖️ | **Application Load Balancer** | Internet-facing, forwards traffic to both instances |
| 🛡️ | **AWS WAFv2 web ACL** | Attached to the ALB — AWS managed rules + per-IP rate limiting, logging to CloudWatch |
| 🔧 | **Helper scripts** | Generate traffic and read the WAF logs back |

```
              Internet
                 │
                 ▼
        ┌─────────────────┐     WAFv2 web ACL
        │       ALB       │◀───  (managed rules + rate limit)
        │  public subnets │      logs → CloudWatch (aws-waf-logs-*)
        └───────┬─────────┘
        ┌───────┴────────┐
        ▼                ▼
   ┌─────────┐      ┌─────────┐
   │ web[0]  │      │ web[1]  │     private subnets,
   │  AZ a   │      │  AZ b   │     HTTP only from the ALB
   └─────────┘      └─────────┘
        │                │
        └──── NAT GW ─────┘ ──▶ outbound for package installs
```

## Repository layout

| File | Purpose |
|---|---|
| `versions.tf` | Terraform + AWS provider constraints, provider config, default tags |
| `variables.tf` | Input variables with validation |
| `main.tf` | Data sources (AZs, latest AL2023 AMI), subnet math, common tags |
| `network.tf` | VPC module: public/private subnets, NAT gateway |
| `compute.tf` | Security groups + the 2 web instances and their bootstrap |
| `alb.tf` | ALB, target group, listener, target attachments |
| `waf.tf` | WAFv2 web ACL, ALB association, CloudWatch logging |
| `outputs.tf` | ALB URL, instance IDs/AZs, WAF ARN + log group |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and edit |
| `scripts/generate-traffic.sh` | Send benign + attack-pattern requests to the ALB |
| `scripts/view-waf-logs.sh` | Query the WAF logs in CloudWatch Logs Insights |

---

## Prerequisites

You need four things: an AWS account, the Terraform CLI, the AWS CLI (with credentials
configured), and `jq`. Steps below cover macOS, Linux, and Windows.

### 1. An AWS account with credentials

- An AWS account you can create resources in.
- An IAM user or role with permissions for EC2, VPC, ELB, WAFv2, IAM, and CloudWatch
  Logs (`AdministratorAccess` is simplest for a personal lab).

### 2. Install Terraform (>= 1.5.7)

**macOS (Homebrew):**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Linux (Debian/Ubuntu):**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Windows (winget or Chocolatey):**
```powershell
winget install HashiCorp.Terraform
# or:  choco install terraform
```

**Any OS (manual):** download the binary from
[developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install),
unzip it, and put it on your `PATH`.

Verify:
```bash
terraform version      # should print v1.5.7 or newer
```

### 3. Install the AWS CLI (v2)

Follow [the official install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
or:

- **macOS:** `brew install awscli`
- **Linux:** `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install`
- **Windows:** `winget install Amazon.AWSCLI`

Verify:
```bash
aws --version          # aws-cli/2.x...
```

### 4. Install jq (used by the log-reading script)

- **macOS:** `brew install jq`
- **Linux:** `sudo apt install jq` (or `sudo dnf install jq`)
- **Windows:** `winget install jqlang.jq`

### 5. Configure AWS credentials

```bash
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region name:   us-east-1
# Default output format: json
```

Confirm it works — this should print your account and identity:
```bash
aws sts get-caller-identity
```

> If you use temporary/SSO credentials (e.g. `aws sso login` or an assumed role), make
> sure the session is active before running Terraform.

---

## Deploy

Run every command from the **project root** (the folder with the `.tf` files), not from
`scripts/`. Terraform only sees the config and state in the directory you run it from.

### 1. Get the code

```bash
git clone https://github.com/jaron360/AWS-WAF-Lab.git
cd AWS-WAF-Lab
```

### 2. Choose your settings (optional)

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` if you want to change the region, instance size, or lock the ALB
to your own IP. Defaults work as-is (region `us-east-1`, open to the internet behind WAF).
To pick a region without editing the file, append `-var="region=us-east-2"` to the
commands below.

### 3. Initialize, review, apply

```bash
terraform init      # downloads the AWS provider and VPC module
terraform plan      # previews the ~36 resources it will create
terraform apply     # type "yes" to confirm  (or: terraform apply -auto-approve)
```

`apply` takes a few minutes (the NAT gateway and ALB are the slow parts).

### 4. Open the app

Allow ~2-3 minutes after apply for the instances to boot, install httpd, and pass health
checks. Then:

```bash
terraform output -raw alb_url
open "$(terraform output -raw alb_url)"       # macOS; use xdg-open on Linux
```

Refresh a few times — the **Availability Zone** on the page alternates between the two
instances, which is the load balancer doing its job.

---

## Analyze WAF logs

This is the core exercise: send traffic, then inspect how WAF classified it.

### 1. Generate traffic

```bash
./scripts/generate-traffic.sh
```

This sends 8 benign requests (expect HTTP `200`) followed by 5 attack patterns — XSS,
SQL injection, path traversal, a Log4Shell-style header, and command injection — that
the AWS managed rules should block (expect HTTP `403`). It auto-discovers the ALB URL
from `terraform output`; you can also pass a URL explicitly:
`./scripts/generate-traffic.sh http://<alb-dns-name>`.

### 2. Read the logs back

WAF logs land in CloudWatch ~1-2 minutes after the requests. The helper script queries
them and prints a table:

```bash
./scripts/view-waf-logs.sh                 # all requests in the last 30 min
BLOCKED_ONLY=1 ./scripts/view-waf-logs.sh  # only requests WAF blocked
./scripts/view-waf-logs.sh 120             # widen the window to 120 minutes
```

Each row shows: **timestamp, client IP, country, HTTP method, WAF action
(`ALLOW`/`BLOCK`), the terminating rule, and the URI**. Benign requests are `ALLOW`; the
attack patterns are `BLOCK` with a `terminatingRuleId` naming the managed rule that
caught them (e.g. `AWSManagedCommonRules`, `AWSManagedKnownBadInputs`, `RateLimit`).

### 3. Query the logs yourself (CloudWatch Logs Insights)

The script runs a Logs Insights query for you, but you can run your own in the console:
**CloudWatch → Logs → Logs Insights**, pick the log group `aws-waf-logs-<name>`, and try:

```
fields @timestamp, httpRequest.clientIp, httpRequest.country,
       httpRequest.httpMethod, httpRequest.uri, action, terminatingRuleId
| sort @timestamp desc
| limit 100
```

Useful variations:

```
# Only blocked requests
| filter action = "BLOCK"

# Top source IPs by request count
stats count(*) as hits by httpRequest.clientIp | sort hits desc

# What each managed rule is catching
stats count(*) as hits by terminatingRuleId | sort hits desc

# Requests from a specific IP
| filter httpRequest.clientIp = "203.0.113.4"
```

### 4. Understand the log fields

Each WAF log entry is JSON. The fields you'll care about most:

| Field | Meaning |
|---|---|
| `action` | `ALLOW` or `BLOCK` — the final decision |
| `terminatingRuleId` | Which rule decided the outcome (or `Default_Action` if no rule matched) |
| `httpRequest.clientIp` | Source IP of the request |
| `httpRequest.country` | Geo of the source IP |
| `httpRequest.uri` / `args` | The path and query string requested |
| `httpRequest.headers` | Request headers (where the Log4Shell test lands) |
| `rateBasedRuleList` | Populated when the per-IP rate limit is involved |

### 5. Watch for real internet traffic

An internet-facing ALB starts receiving **unsolicited scanner traffic within minutes** —
automated probes for `/`, `.env`, `/wp-login.php`, `/.git/config`, and so on. So
`view-waf-logs.sh` will usually show real, external source IPs even before you run the
traffic generator. Filtering those out from your own test traffic (by client IP) is a
good exercise in itself.

### 6. Other views (no scripts)

- **WAF console** → Web ACLs → `<name>-waf` → **Sampled requests** for a quick visual of recent matches.
- **CloudWatch metrics**: WAF `AllowedRequests` / `BlockedRequests`, and ALB `RequestCount`, to confirm volume.

---

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `region` | `us-east-1` | Deployment region |
| `name` | `homelab-web` | Name prefix for all resources |
| `vpc_cidr` | `10.20.0.0/16` | VPC address space |
| `instance_count` | 2 | One per private subnet (2–4) |
| `instance_type` | `t3.micro` | Free-tier-eligible size |
| `allowed_http_cidrs` | `["0.0.0.0/0"]` | Who can reach the ALB on 80. Set to your `/32` to keep it private |
| `single_nat_gateway` | true | One NAT GW to save cost; false = one per AZ |
| `waf_rate_limit` | 2000 | Requests per 5 min per source IP before blocking |
| `waf_log_retention_days` | 14 | WAF log retention in CloudWatch |

---

## Security posture

What protects the workload:

- Instances are in **private subnets** with no public IP; the instance security group
  accepts port 80 **only from the ALB** security group.
- **No SSH, no port 22, no key pair** — there is no login surface exposed.
- **No IAM instance profile** — a web compromise has no AWS credentials to steal, so it
  can't pivot into the account. Blast radius stays on a throwaway box.
- **IMDSv2 required** (`http_tokens = required`, hop limit 1) — blunts SSRF-to-credential attacks.
- **Encrypted** root EBS volumes.
- **WAF** managed rules (Common + Known Bad Inputs) and per-IP rate limiting in front.
- The served app is a **static page** — no dynamic code for injection attacks to target.

Known gaps (fine for a lab, fix for anything real):

- **HTTP only, no TLS.** Traffic is cleartext. Add an ACM cert + HTTPS/443 listener and redirect 80 → 443.
- **No ongoing patching.** The AMI is current at launch but drifts over time; add `dnf-automatic` or rebuild periodically.
- **WAF is defense-in-depth, not a wall.** Managed rules can be evaded and per-IP rate limits don't stop distributed sources.
- **Wide-open egress + no ALB access logs / GuardDuty.** Tightenable; low priority here given there are no credentials on the instances.

---

## Cost

Not free. Rough on-demand estimate in us-east-1:

| Resource | Approx. cost |
|---|---|
| Application Load Balancer | ~$16/month + LCU |
| NAT Gateway | ~$32/month + data processing |
| WAF web ACL + rules | ~$6/month + request charges |
| 2× t3.micro | free-tier eligible, else a few $/each |

---

## Tear down

```bash
terraform destroy
```

Removes everything, including the NAT gateway and WAF, so the meter stops. Run this from
the **project root** when you're done.

---

## Troubleshooting

- **`terraform destroy` says "No objects need to be destroyed" but resources exist.**
  You're likely running it from the wrong directory (e.g. `scripts/`). Run Terraform from
  the project root where `terraform.tfstate` lives.
- **`VpcLimitExceeded` on apply.** The region is at its VPC quota (default 5). Remove an
  unused VPC, request a quota increase, or deploy to another region
  (`-var="region=us-east-2"`).
- **`terraform output` returns nothing / scripts can't find the URL.** The apply hasn't
  completed successfully yet, or you're not in the project root. Re-run `terraform apply`,
  then pass the URL explicitly: `./scripts/generate-traffic.sh http://<alb-dns-name>`.
- **App returns 502/503 right after apply.** Give the instances 2-3 minutes to install
  httpd and pass health checks.
- **No WAF logs appear.** Allow 1-2 minutes for delivery, and confirm the region matches
  where you deployed (`view-waf-logs.sh` reads it from `terraform output`).
