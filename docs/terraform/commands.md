# Terraform Command Reference

The Terraform workflow commands used to build and manage the Cumulus stack, in order. Run these in Git Bash on Windows (or any bash shell on Linux/macOS), from inside the `terraform/` directory, after sourcing the Cumulus `openrc` file (see `docs/commands.md` for that step, it still applies, since the OpenStack provider reads its credentials from the same `OS_*` environment variables).

## Install Terraform

```bash
winget install HashiCorp.Terraform
```

Installs the Terraform CLI itself. Confirm it worked with:

```bash
terraform version
```

## 1. Authenticate

```bash
source project-openrc.sh
```

Same as the manual-CLI workflow. The OpenStack Terraform provider reads its credentials from the `OS_*` environment variables this sets, not from anything in the `.tf` files.

## 2. Initialize

```bash
terraform init
```

Downloads the OpenStack provider plugin declared in `main.tf` and sets up the local `.terraform` state directory. You only need to re-run this if the provider requirements change.

## 3. Validate

```bash
terraform validate
```

Checks the `.tf` files for syntax errors and internal consistency (for example, referencing a resource that doesn't exist) without contacting Cumulus at all. Cheap to run often.

## 4. Plan

```bash
terraform plan
```

Shows what Terraform would create, change, or destroy, without actually doing it. Always worth reading through before running `apply`.

## 5. Apply

```bash
terraform apply
```

Builds the actual infrastructure on Cumulus: keypair usage, router, network, subnet, server, security group, and floating IP, in the correct dependency order. Prompts for confirmation (`yes`) before making changes.

## 6. Read the output

```bash
terraform output server_public_ip
```

Prints the floating IP address the server is reachable on, without needing to open the OpenStack dashboard.

## 7. Destroy

```bash
terraform destroy
```

Tears down everything Terraform created, in reverse dependency order. Prompts for confirmation before doing it. Useful for freeing up Cumulus quota between work sessions.
