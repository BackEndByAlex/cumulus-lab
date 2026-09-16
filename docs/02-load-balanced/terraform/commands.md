# Terraform (02-load-balanced) — Command Reference

See [structure.md](structure.md) for a walkthrough of what each `.tf` file actually does. This page covers the workflow commands used to build and manage this stack, run from `02-load-balanced/terraform/`.

Terraform itself only needs installing once per machine (see [01-single-server/terraform/commands.md](../../01-single-server/terraform/commands.md) for that step) — it isn't repeated here.

## 1. Authenticate

```bash
source project-openrc.sh
```

Same as `01-single-server`. The OpenStack provider reads its credentials from the `OS_*` environment variables this sets.

## 2. Provide your public IP

This exercise's security groups restrict SSH to the student's own home IP (`var.my_public_ip` in `variables.tf`), unlike `01-single-server`'s original design which left SSH open to everyone. Find your current public IP:

```bash
curl ifconfig.me
```

Then create `terraform.tfvars` in `02-load-balanced/terraform/` (gitignored, since it's an environment-specific value):

```hcl
my_public_ip = "203.0.113.7/32"
```

Without this file, `terraform plan` or `terraform apply` will stop and prompt for `my_public_ip` interactively instead of silently defaulting to something wrong.

## 3. Initialize

```bash
terraform init
```

Downloads the OpenStack provider plugin declared in `main.tf` and sets up the local `.terraform` state directory.

## 4. Validate

```bash
terraform validate
```

Checks the `.tf` files for syntax errors and internal consistency without contacting Cumulus.

## 5. Plan

```bash
terraform plan
```

Shows what Terraform would create: the network, subnet, router, two security groups (`ex2_lb_sg`, `ex2_backend_sg`) and their rules, three ports, three servers (two backends + the load balancer), and the load balancer's floating IP.

## 6. Apply

```bash
terraform apply
```

Builds everything, in dependency order. This created 18 resources cleanly in the session this was verified. Prompts for confirmation (`yes`) before making changes.

## 7. Read the outputs

```bash
terraform output loadbalancer_public_ip
terraform output backend_private_ips
```

- `loadbalancer_public_ip` — the floating IP the whole site is reachable on (this is what you SSH to and `curl`).
- `backend_private_ips` — the two backends' private IPs, needed to fill in `02-load-balanced/ansible/inventory.ini` under `[backends]` (the load balancer's floating IP goes under `[loadbalancer]`). See [../ansible.md](../ansible.md).

## 8. Destroy

```bash
terraform destroy
```

Tears down everything created above, in reverse dependency order. Prompts for confirmation before doing it.
