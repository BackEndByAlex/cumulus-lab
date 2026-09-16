# Documentation Index

Docs are organized by exercise, plus a `general/` folder for things that apply across exercises (WSL setup, secrets, linting).

- **`01-single-server/`** — docs for the single-server exercise (manual CLI, Terraform, Ansible)
- **`general/`** — docs that apply across both exercises
- **`02-load-balanced/`** — docs for the load-balanced exercise (Terraform, Ansible, troubleshooting), now at parity with `01-single-server`.

## 01-single-server

### Manual setup (openstack CLI)

- [01-single-server/manual-cli/openstack-cli.md](01-single-server/manual-cli/openstack-cli.md) — the full, working `openstack` command sequence, in order: authenticate, SSH keypair, networking (router/network/subnet), server creation, security group, floating IP, connect.
- [01-single-server/manual-cli/troubleshooting.md](01-single-server/manual-cli/troubleshooting.md) — real problems from the manual setup: wrong external network name, missing auth-url, the Windows CRLF SSH key corruption bug (the most valuable finding in this repo), server-unreachable-after-keypair-regen, and stale host key warnings after recreating a server.

### Terraform

- [01-single-server/terraform/structure.md](01-single-server/terraform/structure.md) — a walkthrough of every `.tf` file in `01-single-server/terraform/` (`main.tf`, `variables.tf`, `network.tf`, `router.tf`, `security_group.tf`, `server.tf`, `floating_ip.tf`, `volume.tf`), explaining what each resource block does and why.
- [01-single-server/terraform/commands.md](01-single-server/terraform/commands.md) — the Terraform workflow commands in order: install, authenticate, init, validate, plan, apply, read output, destroy.
- [01-single-server/terraform/troubleshooting.md](01-single-server/terraform/troubleshooting.md) — real problems building the Terraform stack: auth errors after switching terminals, floating IP association 404s, an invalid/renamed resource type, a wrong availability zone, an HCL parse error after moving into WSL, and a missing-password error post-WSL-move.

### Ansible

- [01-single-server/ansible.md](01-single-server/ansible.md) — creating the inventory and `group_vars`, verifying connectivity, keeping the inventory in sync with Terraform (`update-inventory.sh`), and troubleshooting (host key verification failures, and a playbook-succeeds-but-site-unreachable case caused by the security group layer).

## 02-load-balanced

### Terraform

- [02-load-balanced/terraform/structure.md](02-load-balanced/terraform/structure.md) — a walkthrough of every `.tf` file in `02-load-balanced/terraform/` (`main.tf`, `variables.tf`, `network.tf`, `router.tf`, `security_group.tf`, `ports.tf`, `server.tf`, `floating_ip.tf`), explaining the two-security-group split (`ex2_lb_sg`, `ex2_backend_sg`) and why, and the `var.my_public_ip` / `terraform.tfvars` requirement.
- [02-load-balanced/terraform/commands.md](02-load-balanced/terraform/commands.md) — the Terraform workflow commands in order: authenticate, provide your public IP via `terraform.tfvars`, init, validate, plan, apply, read the outputs, destroy.

### Ansible

- [02-load-balanced/ansible.md](02-load-balanced/ansible.md) — the two-group inventory (`[backends]`, `[loadbalancer]`), the SSH ProxyJump concept for reaching the private backends, the reused `webserver` role and the new `loadbalancer` role (nginx `upstream` block templated over `groups['backends']`), and how the round-robin load-balancing was actually verified end-to-end.
- [02-load-balanced/troubleshooting.md](02-load-balanced/troubleshooting.md) — real problems from building this exercise: an unconfirmed SSH hang to the load balancer (worked around with a wide-open rule that's still in place, a known security gap), backend SSH blocked when reached through the LB until a rule allowed SSH from the LB's security group, and a ProxyJump identity-file issue where the jump hop doesn't inherit the outer `-i` flag, fixed with a dedicated `ssh.cfg`.

## general

- [general/wsl-setup.md](general/wsl-setup.md) — installing Terraform and Ansible inside WSL2, moving the project into WSL's native filesystem, and a harmless D-Bus warning you can ignore.
- [general/secrets-and-security.md](general/secrets-and-security.md) — moving secrets (`mykey.pem`, `project-openrc.sh`) out of the project entirely, what's gitignored and why, the `host_key_checking = False` tradeoff for this lab, and how the security groups in both exercises are structured.
- [general/linting-and-tooling.md](general/linting-and-tooling.md) — setting up `pre-commit` (`terraform fmt`/`validate`, `yamllint`, `ansible-lint`), the hook configuration, registering the hooks, and two lint-config troubleshooting entries.
