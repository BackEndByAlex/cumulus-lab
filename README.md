# Cumulus Lab

This is a lab project for the **2DV013** course at **Linnaeus University (LNU)**. It provisions and configures Ubuntu servers on Cumulus, LNU's OpenStack-based private cloud (IaaS), reachable at [cumulus.lnu.se](https://cumulus.lnu.se). The purpose is to practice Infrastructure as Code (Terraform) and configuration management (Ansible) against a real cloud, and to build a working reference for classmates that documents the real problems encountered along the way, since that's a gap the official course material doesn't cover.

## The Two Exercises

This repo contains two separate exercises, each fully self-contained with its own Terraform and Ansible configuration.

### `01-single-server` — one server, manually and then automated

The simplest possible setup: a single Ubuntu server with nginx, reachable over SSH and HTTP. Built three ways, in order:

1. **Manually**, one `openstack` CLI command at a time, based on the LNU course slides. This is the baseline and still a valid reference for understanding what's happening under the hood.
2. **With Terraform**, recreating the exact same infrastructure (network, router, security group, server, floating IP) declaratively instead of by hand.
3. **Configured with Ansible**, which installs and configures nginx over SSH once Terraform has provisioned the server.

### `02-load-balanced` — two backend servers behind a load balancer

A more realistic setup: two backend web servers on a private network (no public IP of their own) sitting behind an nginx load balancer, which is the only server with a public floating IP. Built with Terraform (network, security groups, ports, servers, floating IP) and configured with Ansible, which installs nginx on the backends and configures nginx as a reverse proxy on the load balancer. Ansible reaches the private backend servers by SSH-jumping through the load balancer (`ProxyJump`), since they have no direct path from outside Cumulus.

This exercise now has full walkthrough docs alongside `01-single-server`, see [Documentation](#documentation) below.

## Tech Stack

- **Terraform** — Infrastructure as Code, using the `terraform-provider-openstack/openstack` provider
- **Ansible** — configuration management, connecting over SSH
- **OpenStack / Cumulus** — the cloud platform both tools target
- **WSL2 (Ubuntu)** — the control node both Terraform and Ansible run from; Ansible has no native Windows support, so the whole toolchain moved here from Windows/Git Bash partway through the project

## Repo Structure

```
cumulus-lab/
├── 01-single-server/
│   ├── terraform/     # network, router, security group, server, floating IP
│   └── ansible/       # webserver role (installs/configures nginx), inventory, scripts/
├── 02-load-balanced/
│   ├── terraform/     # network, security groups, ports, 2 backend servers + LB, floating IP
│   └── ansible/       # webserver + loadbalancer roles, ssh.cfg (ProxyJump config)
├── docs/
│   ├── 01-single-server/   # manual-cli/, terraform/, ansible.md — walkthroughs + troubleshooting
│   ├── 02-load-balanced/   # terraform/, ansible.md, troubleshooting.md — walkthroughs + troubleshooting
│   └── general/            # wsl-setup.md, secrets-and-security.md, linting-and-tooling.md
├── .pre-commit-config.yaml  # terraform fmt/validate, yamllint, ansible-lint hooks
├── .yamllint / .ansible-lint
└── .gitignore
```

## Documentation

Start at [docs/README.md](docs/README.md) — the full documentation index, linking every doc file with a description of what's in it.

Both exercises now have full Terraform + Ansible walkthrough docs, plus troubleshooting docs: [docs/01-single-server/](docs/01-single-server/) and [docs/02-load-balanced/](docs/02-load-balanced/).

## Prerequisites

To reproduce this project, you'll need:

- WSL2 with an Ubuntu distro (see `docs/general/wsl-setup.md`)
- Terraform and Ansible installed inside WSL (see `docs/general/wsl-setup.md`)
- Access to Cumulus (an LNU-issued OpenStack project) and a downloaded `openrc` credentials file
- For `02-load-balanced` specifically: your own public IP address, used in `terraform.tfvars` to restrict SSH access to the load balancer and backend servers (see the `variables.tf` comment in that exercise for the exact format)

Full setup steps (installing the tools, structuring secrets, verifying connectivity) live in the `docs/` files linked above rather than being duplicated here.

## Current Status

Both exercises' Terraform configurations pass `terraform validate`. Cumulus lab instances are lab resources that get destroyed and recreated between sessions to free up quota, so whether either exercise's servers are actually up and reachable at any given moment depends on whether they've been applied recently, not on anything the code itself controls.
