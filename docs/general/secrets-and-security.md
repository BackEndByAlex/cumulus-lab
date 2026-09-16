# Secrets and Security

## Move secrets out of the project entirely

Two things used to sit inside the repo that should never be at risk of being committed to git, even by accident:

- `mykey.pem` — the SSH private key, created out-of-band with `openstack keypair create --private-key mykey.pem mykey` (see `docs/01-single-server/manual-cli/openstack-cli.md`). This was never a Terraform-managed resource, Terraform only references the keypair by name.
- `project-openrc.sh` — the OpenStack credentials file downloaded from the Cumulus dashboard (Project → API Access).

Both got moved into a dedicated directory outside the project:

```bash
mkdir -p ~/.cumulus-secrets
mv ~/cumulus-lab/mykey.pem ~/.cumulus-secrets/
mv ~/cumulus-lab/project-openrc.sh ~/.cumulus-secrets/
chmod 700 ~/.cumulus-secrets
chmod 600 ~/.cumulus-secrets/mykey.pem ~/.cumulus-secrets/project-openrc.sh
```

`chmod 700` on the directory means only my own user can even list what's in it. `chmod 600` on the files means only my own user can read or write them, not even other local accounts. SSH also refuses to use a private key file with looser permissions than that anyway, so this isn't optional.

Both `01-single-server/ansible/group_vars/webserver.yml` and `02-load-balanced/ansible/group_vars/loadbalancer.yml` point at the relocated key via `ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem`, instead of a key sitting inside the project.

## What actually ends up gitignored, and why

`inventory.ini` now only ever contains real Cumulus IPs, and `group_vars/webserver.yml` only ever contains local file paths, both environment-specific and both kept out of version control (see `.gitignore` at the project root), while a future teammate could still get a template `group_vars/webserver.yml.example` committed without leaking anything personal.

- `inventory.ini` is matched by a bare `inventory.ini` pattern in `.gitignore` (no leading slash), which matches it anywhere in the repo, so it covers both `01-single-server/ansible/inventory.ini` and `02-load-balanced/ansible/inventory.ini` without needing a separate line for each.
- `01-single-server/ansible/group_vars/webserver.yml` needed its own explicit line added, since it carries the same kind of environment-specific values (`ansible_user`, and especially the local `ansible_ssh_private_key_file` path) that were being kept out of git before.
- `*.tfvars` is also gitignored project-wide. `02-load-balanced/terraform/terraform.tfvars` holds the student's own public IP (used to lock down SSH access to the load balancer and backends), which is environment-specific and shouldn't be committed either.
- A few other patterns exist in `.gitignore` for the same reason, secrets or environment-specific files that should never end up committed even by accident: `*.retry` (Ansible's automatically generated retry files after a failed playbook run), `group_vars/**/vault.yml`, `*.vault`, and `.vault_pass` (Ansible Vault encrypted-secrets files, not currently used in this project but ignored defensively).

## Turn off host key checking for this project only

Cumulus lab instances get destroyed and recreated often during this workshop, and each new instance comes with a brand-new floating IP. SSH, and by extension Ansible, remembers host keys per IP address in `~/.ssh/known_hosts`. Every time the floating IP changed, the very first Ansible run against it stopped to ask whether the new host's key should be trusted, which meant babysitting every single run instead of letting it complete on its own.

Both `01-single-server/ansible/ansible.cfg` and `02-load-balanced/ansible/ansible.cfg`:

```ini
[defaults]
host_key_checking = False
```

- `[defaults]` is the section Ansible's core settings live under.
- `host_key_checking = False` tells Ansible not to check or prompt about SSH host keys at all when connecting to hosts.
- Each `ansible.cfg` sits inside its own exercise's `ansible/` directory, so it only applies when Ansible is run from that directory. It does not touch the regular `ssh` command, global `~/.ssh/config`, or anything outside of Ansible.

This was a deliberate tradeoff for this specific lab, not a default I'd reach for elsewhere. These are throwaway instances with no real data on them, and the whole point of host key checking is to catch a server unexpectedly presenting a different identity than before, which is exactly what's supposed to happen here every time the lab environment gets rebuilt. Turning the check off entirely removes any value it was providing in this context.

For anything longer-lived, production infrastructure, a persistent server, real user data, this is not the right fix. The safer middle ground there is `StrictHostKeyChecking=accept-new` (trust a host the first time it's seen, but still fail loudly if the key ever changes afterward), or managing known hosts properly through configuration management, not disabling the check outright.

`02-load-balanced/ansible/ssh.cfg` applies the same `StrictHostKeyChecking no` / `UserKnownHostsFile /dev/null` idea at the SSH level instead, since Ansible reaches the backend servers by SSH-jumping through the load balancer (`ProxyJump`), which needs its own host-key handling for the jump hop.

## Security groups (network-level access control)

Terraform, not Ansible, controls which ports are reachable from outside Cumulus at all, via OpenStack security groups:

- **01-single-server:** one security group (`web-security-group`) opens the ports listed in `variables.tf`'s `web_ports_open` to any source IP, since this is a single publicly reachable server.
- **02-load-balanced:** two separate security groups. The load balancer's security group opens HTTP (80) to the whole internet but SSH (22) only from the student's own IP (`var.my_public_ip`, provided via `terraform.tfvars`, gitignored). The backend servers' security group only allows inbound traffic on their app port from the load balancer's own private IP (not from the internet), plus SSH from the load balancer's security group (since Ansible reaches the backends by jumping through the LB) and from the student's own IP directly.

A successful Ansible run only proves the server itself is configured correctly, it says nothing about whether Terraform's security group actually lets traffic reach it. See `docs/01-single-server/ansible.md`'s troubleshooting section for a concrete case of this exact layering mistake.
