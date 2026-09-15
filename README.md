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

* A production-shaped, three-region-aware application stack built entirely in Terraform: a load balancer with a real TLS certificate and a real domain name, a Web Application Firewall, a CDN layer, a second AWS region connected by a private network link, and an automated system that writes up an incident report the moment something goes wrong — rather than just sending a bare notification.
* This is the largest project in the series, and it's split across **three separate Terraform projects**, not one. Treating them like a single project is the single most common way to get stuck — read [Step 2](#step-2--understand-the-three-project-split) before touching anything.
* **Primary region:** Tokyo (`ap-northeast-1`). **Secondary region:** São Paulo (`sa-east-1`). **One piece (the CDN's WAF) has to live in `us-east-1`** specifically, because CloudFront-attached resources of that type only exist in that one region, regardless of where everything else is built.

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

Before you touch any Terraform, make sure you have:

- [ ] Terraform installed (version 1.9 or higher)
- [ ] AWS CLI installed and configured with credentials for the target account (`aws sts get-caller-identity` should return your account, not an error)
- [ ] A registered domain name with a Route 53 hosted zone (or DNS you can add validation records to)
- [ ] Basic understanding of AWS networking, IAM, and Terraform state
- [ ] Patience & lots of coffee — this one takes a while to apply

# Step 2 — Understand the three-project split

This is the single most important structural thing to understand before touching any of this:

* **The root project** (this directory) manages Tokyo — the network, database, load balancer, WAF, monitoring, and incident automation.
* **A second, completely separate project** (`liberdade/`) manages São Paulo — its own VPC, its own small application stack, and the *accepting* side of the Transit Gateway peering request from Step 5.13. It has its own separate remote state, entirely independent from the root project's.
* **A third, completely separate project** (`Cloudfront/`) manages the CloudFront CDN layer sitting in front of the Tokyo load balancer. It also has its own separate state, and rather than referencing the load balancer as a direct Terraform resource, it looks it up by name after the fact — as far as this project is concerned, the load balancer is just a fact about the world it discovers, not something it created itself.

Because of this structure:

* Each of the three has to be initialized and applied **separately, in its own directory** — there's no single command that builds all three at once.
* **Order matters and is one-directional**: root has to be applied first, since both other projects depend on something only root can create (the load balancer, for the CDN project; the peering request itself, for the São Paulo project).
* Tearing everything down happens in the **exact reverse order** — CDN and São Paulo first, then root last.

# Step 3 — Configure your variables and backend

Do this before you run anything:

1. **Point the remote state at your own account.** Each project's `*-backend.tf` (root's `1-backend.tf`, `Cloudfront/1-backend.tf`, `liberdade/liberdade-backend.tf`) has an S3 bucket name baked in (`terraform-state-<account-id>-<region>`). Create that bucket in your own account for each region (`ap-northeast-1` and `sa-east-1`), or edit the `bucket` field to point at buckets you already own.
2. **Override the personal defaults in `4-variables.tf`** (and the matching vars in `Cloudfront/4-variables.tf` / `liberdade/liberdade-variables.tf`) — don't deploy with someone else's email or domain baked in:
   - `domain_name` / `app_subdomain` — your own registered domain and subdomain.
   - `sns_email_endpoint` — the email address that should receive incident alerts.
   - `cloudfront_acm_cert_arn` — an ACM certificate ARN in `us-east-1` that you own (CloudFront only accepts certs from that region).
3. Set these as a `terraform.tfvars` file in each project directory (or pass `-var` flags at apply time) rather than editing the defaults directly, so your values don't collide with a future `git pull`.

# Step 4 — Validate all three projects

Run this in **each** of the three directories (root, `Cloudfront/`, `liberdade/`) before touching AWS at all:

```bash
terraform init
terraform fmt -check
terraform validate
```

Fix anything that fails here first — none of the later steps will work if a project doesn't validate.

# Step 5 — Build & deploy the root project (Tokyo)

The root project is applied as a single `terraform apply`, but it's built out of the following pieces. Use this as a checklist to understand — and, if you want to build incrementally with `terraform apply -target=...`, to verify — what's going up and why, in the order it depends on itself.

### 5.1 — Data Sources & Account Facts
Rather than hardcoding values that could go stale, this project asks AWS (and one outside service) directly for a handful of facts it needs before building anything — your current public IP address (for restricting SSH later), which availability zones exist in the primary region, the AWS account ID you're deploying into, and the current region's own name. *(`data.aws_caller_identity.current`, `data.aws_availability_zones.available`, `data.http.my_public_ip`, `data.aws_region.current` in `4-variables.tf`.)*

### 5.2 — Primary Region Network
The same core pattern as every other project in this series, scaled up: a VPC, public and private subnets, an Internet Gateway, a NAT Gateway, and matching route tables for the public and private sides.

```bash
terraform apply -target=aws_vpc.ShibuyaCrossing_vpc -target=aws_subnet.public_ShibuyaCrossing -target=aws_subnet.private_ShibuyaCrossing -target=aws_internet_gateway.ShibuyaCrossing_igw -target=aws_nat_gateway.nat
```

**Verify:** the VPC and its subnets appear in the AWS Console.

![VPC created in the AWS console](Images/aws_console_vpc.jpg "ShibuyaCrossing VPC details")

### 5.3 — Private VPC Endpoints
Normally, even a server sitting in a private subnet still has to route out through the NAT Gateway to reach AWS's own services. VPC endpoints solve this by creating a direct, private connection from inside the VPC straight to a specific AWS service. This project sets one up for each of: Secrets Manager, Systems Manager (and its two related messaging services), CloudWatch Logs, and KMS. A dedicated security group controls access, allowing only encrypted HTTPS traffic to reach them.

### 5.4 — Layered Security Groups
* **The load balancer's security group** — inbound HTTP and HTTPS from the internet. This is the only thing in the whole architecture directly exposed to the public internet.
* **The EC2 security group** — inbound traffic only from the load balancer's security group.
* **The database security group** — inbound MySQL traffic only from the EC2 security group.

Each layer only trusts the one specific layer in front of it, never a broader IP range and never "anywhere." **Verify:** in the console, confirm the EC2 and RDS security groups have no `0.0.0.0/0` inbound rules — only the ALB's does.

### 5.5 — TLS Certificate
A certificate is requested from AWS Certificate Manager for both the base domain and the application's subdomain, using DNS-based validation. This project can either create the validation record itself or simply look up an already-existing hosted zone and add just the records it needs (controlled by `manage_route53_in_terraform`) — the default and safer option.

### 5.6 — Load Balancer, Target Group, Listener
An Application Load Balancer is created in the public subnets, along with a target group and an HTTPS listener using the certificate from Step 5.5.

**Verify:**

![Application Load Balancer details in the AWS console](Images/aws_console_alb.jpg "ShibuyaCrossing-alb details")

### 5.7 — Web Application Firewall
A Web ACL is created and attached directly to the load balancer, giving it a layer of protection against common attack patterns before traffic ever reaches the application itself. Its activity logs can be sent to CloudWatch, S3, or a streaming delivery pipeline, chosen through the `waf_log_destination` variable.

**Verify:**

![WAF web ACL protection pack in the AWS console](Images/aws_console_waf.jpg "ShibuyaCrossing_waf01")

### 5.8 — Private Database & Credentials
A private RDS MySQL instance is placed in the private subnets, with a Secrets Manager secret holding its full connection details as one JSON object, and plain (non-secret) values — endpoint, port, database name — published separately to Parameter Store.

**Verify:**

![RDS instance summary in the AWS console](Images/aws_console_rds_summary.jpg "lab3-mysql summary")

![RDS connection endpoint in the AWS console](Images/aws_console_rds_endpoint.jpg "lab3-mysql connection endpoint")

### 5.9 — Application Server & IAM
The EC2 instance is launched using the latest Amazon Linux image, placed behind the load balancer, with an IAM role scoped to: reading the one specific database secret, reading the specific Parameter Store values, writing to one specific CloudWatch log group, and using Systems Manager Session Manager for shell access without an open port 22.

The startup script (`user_data.sh`) installs the application into a dedicated, restricted system user account and runs it as a background service that restarts automatically if it crashes.

### 5.10 — Monitoring: Logs, Alarms, Dashboard
A log group receives the application's logs, a metric filter watches for database connection error patterns, and an alarm watches that metric. A second alarm watches the load balancer's own error rate directly. A dashboard pulls several of these signals together into one visual view.

**Verify:**

![CloudWatch dashboard in the AWS console](Images/aws_console_cloudwatch_dashboard.jpg "lab3-dashboard01")

### 5.11 — Automated Incident Reporting
Rather than an alarm only sending a plain notification, this project wires the alarm's SNS topic to two subscribers at once:

* **A real email address** (the `sns_email_endpoint` you set in Step 3), for a human to be notified directly. **You'll need to confirm the SNS subscription from your inbox** the first time you apply, or alerts will silently not arrive.
* **A small Lambda function**, triggered whenever the alarm fires, that writes up an incident report. It has its own tightly scoped IAM role, and its code is protected using AWS's code-signing feature.
* **A written runbook document**, stored in Systems Manager, giving a human step-by-step instructions for the same incident-response process the Lambda function automates.

**Verify:**

![Lambda incident-reporter function overview in the AWS console](Images/aws_console_lambda.jpg "lab3-ir-reporter01")

### 5.12 — Storage for Logs & Reports
Three separate S3 buckets hold generated output rather than being part of the live application path: one for the load balancer's own access logs, one for the WAF's logs, and one for the incident reports the Lambda function produces. Each has encryption, versioning, and public access blocking configured.

**Verify:**

![S3 buckets in the AWS console](Images/aws_console_s3.jpg "ShibuyaCrossing S3 buckets")

### 5.13 — Transit Gateway to São Paulo
A Transit Gateway is created in the primary region specifically to allow private, non-internet-routed traffic between this VPC and a second VPC in São Paulo. A **peering attachment request** is created from this side — the São Paulo side has to separately accept it before traffic can actually flow (that happens in [Step 7](#step-7--deploy-the-são-paulo-project)).

**Verify:**

![Transit Gateway details in the AWS console](Images/aws_console_transit_gateway.jpg "ShibuyaCrossing-tgw")

### Now actually deploy it

If you built incrementally with `-target` above, run one final untargeted apply to pick up anything left:

```bash
terraform apply
```

Otherwise, this is the single command that builds everything in 5.1–5.13 in the right order — expect it to take a while, most of the wait is the database and the certificate's validation process.

**Verify:**

![terraform init and validate succeeding](Images/terraform_init_validate_success.png "terraform init / validate")

![terraform validate succeeding](Images/terraform_validate_success_1.png "terraform fmt / validate")

![terraform plan output listing all outputs](Images/terraform_plan_outputs_1.png "terraform plan")

# Step 6 — Confirm zero drift and test the app

1. Re-run a plan — it should show nothing left to change:
   ```bash
   terraform plan
   ```
   ![terraform plan output, second run confirming no drift](Images/terraform_plan_outputs_2.png "terraform plan - zero drift")
2. Grab the app's URLs:
   ```bash
   terraform output application_urls
   ```
3. Test the application through the load balancer directly. A plain connection to the raw ALB DNS name will show a certificate mismatch warning until your real domain name is pointing at it — that's expected. Once your DNS record for `app_subdomain` is live, test through the real domain instead.

# Step 7 — Deploy the São Paulo project

1. Grab the peering attachment ID that root just created:
   ```bash
   terraform output -raw tgw_peering_attachment
   ```
2. In `liberdade/`, set `tgw_peering_attachment_id` to that value (in your `terraform.tfvars`, or as a `-var` flag).
3. Deploy it:
   ```bash
   cd liberdade
   terraform init
   terraform apply -var="tgw_peering_attachment_id=<value from step 1>"
   ```

# Step 8 — Deploy the CloudFront project

Only run this once root genuinely exists — it looks up the Tokyo load balancer by name rather than creating it.

```bash
cd Cloudfront
terraform init
terraform apply
```

# Step 9 — Collect your deliverables

Congrats, you have successfully completed your mission and you are now ready for more pain. Collect screenshots for your records.

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

Unless you can print your own money, you will need to tear down your deployment.

1. Tear down in the **exact reverse order** of deployment: CloudFront project first, then São Paulo (`liberdade/`), then root last.
2. Run `terraform destroy` in each project directory, in that order.
3. Confirm the deletion when prompted — say yes.
4. Double check the AWS Console that everything is actually terminated.
5. Triple check everything — Jeff Bezos has enough money.

**Verify:**

![terraform destroy complete, all resources destroyed](Images/terraform_destroy_complete.jpg "terraform destroy complete")

# Known Errors

* **A real secret-leak incident, already handled.** An EC2 SSH private key was accidentally committed into this repository's very first commit at some point in its history. It was handled properly end to end: checking whether the leaked key was still registered and usable in AWS before assuming the worst, removing it from version control going forward, rotating it for a fresh one, and checking *every* branch (not just the one currently being worked on) for the same leaked commit, since early history is often shared across branches.
* **If a deployment gets interrupted partway through**, check whether anything finished creating in AWS but never made it into Terraform's own bookkeeping before re-running — an interrupted `apply` can leave real resources that a fresh `plan` doesn't know about yet.

# Author

Benjamin Cooper
