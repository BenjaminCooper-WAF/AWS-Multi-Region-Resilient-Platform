# AWS-Multi-Region-Resilient-Platform

![AWS](https://img.shields.io/badge/AWS-CLOUD-F3702A?style=for-the-badge&logo=amazonaws&logoColor=white)
![Terraform](https://img.shields.io/badge/TERRAFORM-%E2%89%A51.9-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Multi Region](https://img.shields.io/badge/MULTI--REGION-Tokyo%20%2B%20S%C3%A3o%20Paulo-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/LICENSE-see%20LICENSE.md-blue?style=for-the-badge)
![VPC](https://img.shields.io/badge/VPC-8C4FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![EC2](https://img.shields.io/badge/EC2-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![RDS MySQL](https://img.shields.io/badge/RDS%20MYSQL-527FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![ALB](https://img.shields.io/badge/ELASTIC%20LOAD%20BALANCING-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![WAF](https://img.shields.io/badge/AWS%20WAF-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)
![CloudFront](https://img.shields.io/badge/CLOUDFRONT-8C4FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![Lambda](https://img.shields.io/badge/LAMBDA-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![S3](https://img.shields.io/badge/S3-569A31?style=for-the-badge&logo=amazonaws&logoColor=white)
![CloudWatch](https://img.shields.io/badge/CLOUDWATCH-FF4F8B?style=for-the-badge&logo=amazonaws&logoColor=white)
![SNS](https://img.shields.io/badge/SNS-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)
![Transit Gateway](https://img.shields.io/badge/TRANSIT%20GATEWAY-8C4FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![ACM](https://img.shields.io/badge/CERTIFICATE%20MANAGER-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![Route53](https://img.shields.io/badge/ROUTE%2053-8C4FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![IAM](https://img.shields.io/badge/IAM-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)
![Secrets Manager](https://img.shields.io/badge/SECRETS%20MANAGER-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)

# Mission Objective

The biggest project in the series. It's a Terraform build of an app stack that spans two AWS regions (three, technically, because of one CloudFront quirk): a load balancer with a real cert and domain in front of it, a WAF, a CDN, a private network link to a second region, and an alarm setup that writes an actual incident report instead of just pinging someone.

It's three separate Terraform projects, not one. If you try to treat it as a single `apply`, you'll get stuck — read [Step 2](#step-2--understand-the-three-project-split) first.

Primary region is Tokyo (`ap-northeast-1`), secondary is São Paulo (`sa-east-1`). The WAF that attaches to CloudFront has to sit in `us-east-1` regardless of where you put everything else — that's just an AWS requirement for CloudFront-linked WAF resources, not a design choice I made.

# Follow These Steps In Order

1. [Prerequisites](#step-1--prerequisites)
2. [Understand the three-project split](#step-2--understand-the-three-project-split)
3. [Configure your variables and backend](#step-3--configure-your-variables-and-backend)
4. [Validate all three projects](#step-4--validate-all-three-projects)
5. [Build & deploy the root project (Tokyo)](#step-5--build--deploy-the-root-project-tokyo)
6. [Confirm zero drift and test the app](#step-6--confirm-zero-drift-and-test-the-app)
7. [Deploy the São Paulo project](#step-7--deploy-the-são-paulo-project)
8. [Deploy the CloudFront project](#step-8--deploy-the-cloudfront-project)
9. [Collect your deliverables](#step-9--collect-your-deliverables)
10. [Tear it all down](#step-10--tear-it-all-down)

Also see: [Known Errors](#known-errors) · [Author](#author)

# Step 1 — Prerequisites

- Terraform 1.9+
- AWS CLI configured for the account you're deploying into. `aws sts get-caller-identity` should return your account, not an error.
- A domain with a Route 53 hosted zone, or at least DNS access good enough to add validation records
- Some familiarity with AWS networking, IAM, and Terraform state
- Time. This one takes a while to apply.

# Step 2 — Understand the three-project split

- **Root** (this directory) builds Tokyo: network, database, load balancer, WAF, monitoring, incident automation.
- **`liberdade/`** builds São Paulo, separately. Own VPC, own small app stack, own state. It also accepts the Transit Gateway peering request that root creates.
- **`Cloudfront/`** builds the CDN layer in front of the Tokyo load balancer, also separately. It doesn't manage the load balancer as a resource — it looks it up by name after root has already created it.

Each one gets `init` and `apply` run in its own directory. Root has to go first, since the other two depend on things only it creates (the load balancer for CloudFront, the peering request for São Paulo). Tearing down goes in reverse: CloudFront, then São Paulo, then root.

# Step 3 — Configure your variables and backend

1. Point remote state at your own account. Each project's backend file (root's `1-backend.tf`, `Cloudfront/1-backend.tf`, `liberdade/liberdade-backend.tf`) has a bucket name baked in, following the pattern `terraform-state-<account-id>-<region>`. Create matching buckets in `ap-northeast-1` and `sa-east-1`, or edit the `bucket` field to point at ones you already own.
2. Override the defaults in `4-variables.tf` (and `Cloudfront/4-variables.tf`, `liberdade/liberdade-variables.tf`):
   - `domain_name` / `app_subdomain` — your domain
   - `sns_email_endpoint` — where incident alerts should go
   - `cloudfront_acm_cert_arn` — a cert ARN in `us-east-1` that you own
3. Put these in a `terraform.tfvars` per project, or pass `-var` at apply time, rather than editing the defaults directly. Otherwise a `git pull` later will overwrite your values.

# Step 4 — Validate all three projects

Run this in each of the three directories before touching AWS:

```bash
terraform init
terraform fmt -check
terraform validate
```

If any of these fail, fix it before moving on.

# Step 5 — Build & deploy the root project (Tokyo)

This ends up as one `terraform apply`, but here's what it's actually building, in order.

### 5.1 — Data Sources & Account Facts

The config looks up a few things instead of hardcoding them: your public IP (for the SSH restriction later), the AZs available in the region, your account ID, and the region name. `data.aws_caller_identity.current`, `data.aws_availability_zones.available`, `data.http.my_public_ip`, `data.aws_region.current` in `4-variables.tf`.

### 5.2 — Primary Region Network

VPC, public and private subnets, an Internet Gateway, a NAT Gateway, route tables for both sides. Same pattern as the earlier projects in this series, just bigger.

```bash
terraform apply -target=aws_vpc.ShibuyaCrossing_vpc -target=aws_subnet.public_ShibuyaCrossing -target=aws_subnet.private_ShibuyaCrossing -target=aws_internet_gateway.ShibuyaCrossing_igw -target=aws_nat_gateway.nat
```

![VPC created in the AWS console](Images/aws_console_vpc.jpg "ShibuyaCrossing VPC details")

### 5.3 — Private VPC Endpoints

Without these, a private-subnet server still has to route out through the NAT Gateway to reach AWS services. These give it a direct private path instead — one endpoint each for Secrets Manager, Systems Manager and its two messaging services, CloudWatch Logs, and KMS, gated by a security group that only allows HTTPS.

### 5.4 — Layered Security Groups

- Load balancer: HTTP/HTTPS from the internet. The only thing here that's actually public.
- EC2: only from the load balancer's security group.
- Database: only MySQL from the EC2 security group.

Worth checking in the console that EC2 and RDS have no `0.0.0.0/0` inbound rules — only the ALB should.

### 5.5 — TLS Certificate

ACM issues a cert for the base domain and the app subdomain, validated over DNS. `manage_route53_in_terraform` controls whether Terraform manages the validation record itself or just looks up an existing hosted zone and adds what it needs — the second is the default.

### 5.6 — Load Balancer, Target Group, Listener

ALB in the public subnets, target group, HTTPS listener using the cert from 5.5.

![Application Load Balancer details in the AWS console](Images/aws_console_alb.jpg "ShibuyaCrossing-alb details")

### 5.7 — Web Application Firewall

A Web ACL attaches to the load balancer directly. Logs can go to CloudWatch, S3, or a streaming pipeline depending on `waf_log_destination`.

![WAF web ACL protection pack in the AWS console](Images/aws_console_waf.jpg "ShibuyaCrossing_waf01")

### 5.8 — Private Database & Credentials

Private RDS MySQL instance in the private subnets. Full connection details go into a Secrets Manager secret as one JSON object; the non-sensitive parts (endpoint, port, database name) go to Parameter Store separately.

![RDS instance summary in the AWS console](Images/aws_console_rds_summary.jpg "lab3-mysql summary")

![RDS connection endpoint in the AWS console](Images/aws_console_rds_endpoint.jpg "lab3-mysql connection endpoint")

### 5.9 — Application Server & IAM

EC2 instance on the latest Amazon Linux, behind the load balancer, with an IAM role scoped to: read the one database secret, read the specific Parameter Store values, write to one CloudWatch log group, and use Session Manager instead of an open port 22.

`user_data.sh` installs the app under a restricted system user and runs it as a service that restarts on crash.

### 5.10 — Monitoring: Logs, Alarms, Dashboard

A log group for the app's logs, a metric filter watching for database connection errors, and an alarm on that metric. A second alarm watches the load balancer's error rate. A dashboard ties the important signals together.

![CloudWatch dashboard in the AWS console](Images/aws_console_cloudwatch_dashboard.jpg "lab3-dashboard01")

### 5.11 — Automated Incident Reporting

The alarm's SNS topic has two subscribers:

- An email address (`sns_email_endpoint`) for a person. You have to confirm the SNS subscription from your inbox the first time you apply, or the emails just won't show up.
- A Lambda function that writes an incident report when the alarm fires. Scoped IAM role, code signing enabled.
- A runbook in Systems Manager, in case a human needs to do the same thing manually.

![Lambda incident-reporter function overview in the AWS console](Images/aws_console_lambda.jpg "lab3-ir-reporter01")

### 5.12 — Storage for Logs & Reports

Three S3 buckets, none in the live request path: ALB access logs, WAF logs, and the Lambda's incident reports. Encryption, versioning, and public access blocking on all three.

![S3 buckets in the AWS console](Images/aws_console_s3.jpg "ShibuyaCrossing S3 buckets")

### 5.13 — Transit Gateway to São Paulo

A Transit Gateway in Tokyo for a private path between this VPC and São Paulo's. Root creates the peering attachment request here; São Paulo accepts it in [Step 7](#step-7--deploy-the-são-paulo-project).

![Transit Gateway details in the AWS console](Images/aws_console_transit_gateway.jpg "ShibuyaCrossing-tgw")

### Now actually deploy it

If you applied incrementally with `-target` above, run one more plain apply to catch anything left:

```bash
terraform apply
```

Otherwise this one command builds everything in 5.1–5.13 in order. Most of the wait is the database and cert validation, not Terraform itself.

![terraform init and validate succeeding](Images/terraform_init_validate_success.png "terraform init / validate")

![terraform validate succeeding](Images/terraform_validate_success_1.png "terraform fmt / validate")

![terraform plan output listing all outputs](Images/terraform_plan_outputs_1.png "terraform plan")

# Step 6 — Confirm zero drift and test the app

1. Run a plan again — it should show no changes:
   ```bash
   terraform plan
   ```
   ![terraform plan output, second run confirming no drift](Images/terraform_plan_outputs_2.png "terraform plan - zero drift")
2. Get the app URLs:
   ```bash
   terraform output application_urls
   ```
3. Test through the load balancer. Hitting the raw ALB DNS name directly will show a cert mismatch until your domain is actually pointed at it — that's expected. Once `app_subdomain` resolves, test through the real domain.

# Step 7 — Deploy the São Paulo project

1. Get the peering attachment ID from root:
   ```bash
   terraform output -raw tgw_peering_attachment
   ```
2. Set `tgw_peering_attachment_id` to that value in `liberdade/` (tfvars or `-var`).
3. Deploy:
   ```bash
   cd liberdade
   terraform init
   terraform apply -var="tgw_peering_attachment_id=<value from step 1>"
   ```

# Step 8 — Deploy the CloudFront project

Only after root actually exists — this project finds the Tokyo load balancer by name rather than creating it.

```bash
cd Cloudfront
terraform init
terraform apply
```

# Step 9 — Collect your deliverables

Once everything's up, this is what it looks like in the console.

![terraform apply complete, outputs part 1](Images/terraform_apply_complete_outputs_1.png "terraform apply complete")

![terraform apply complete, outputs part 2](Images/terraform_apply_complete_outputs_2.png "terraform apply complete, continued")

![ShibuyaCrossing VPC](Images/aws_console_vpc.jpg "VPC")

![ShibuyaCrossing ALB](Images/aws_console_alb.jpg "ALB")

![ShibuyaCrossing WAF](Images/aws_console_waf.jpg "WAF")

![lab3-mysql RDS instance](Images/aws_console_rds_summary.jpg "RDS")

![lab3-mysql RDS connection endpoint](Images/aws_console_rds_endpoint.jpg "RDS endpoint")

![lab3-ir-reporter01 Lambda function](Images/aws_console_lambda.jpg "Lambda")

![ShibuyaCrossing-tgw Transit Gateway](Images/aws_console_transit_gateway.jpg "Transit Gateway")

![ShibuyaCrossing S3 buckets](Images/aws_console_s3.jpg "S3")

![lab3-dashboard01 CloudWatch dashboard](Images/aws_console_cloudwatch_dashboard.jpg "CloudWatch Dashboard")

# Step 10 — Tear it all down

1. Reverse order: CloudFront, then São Paulo (`liberdade/`), then root.
2. `terraform destroy` in each directory, in that order.
3. Confirm when it asks.
4. Check the console too, don't just trust the CLI.

![terraform destroy complete, all resources destroyed](Images/terraform_destroy_complete.jpg "terraform destroy complete")

# Known Errors

- An EC2 SSH private key got committed into this repo's first commit at some point in its history. I checked whether it was still active in AWS, removed it from version control, rotated the key, and checked every branch (not just the one I was on) since early commits tend to be shared across branches.
- If a deploy gets interrupted partway through, check AWS directly before re-running — something may have finished creating without Terraform's state knowing about it yet.

# Author

Benjamin Cooper
