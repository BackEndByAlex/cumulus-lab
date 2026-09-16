# Ansible (01-single-server)

Once Terraform has provisioned the server, Ansible connects over SSH to configure it (install and configure nginx), instead of SSHing in by hand. This runs from the same WSL2 control node as Terraform, see `docs/general/wsl-setup.md` for that setup, and `docs/general/secrets-and-security.md` for where the SSH key and OpenStack credentials live.

## Create the Ansible inventory

`01-single-server/ansible/inventory.ini` tells Ansible which host to manage and how to reach it:

```ini
[webserver]
xxx.xx.xx.xx
```

- `[webserver]` — a group name. Groups are how Ansible targets a set of hosts at once (`ansible webserver ...` below targets everything in this group).
- `xxx.xx.xx.xx` — the server's floating IP (the same one `terraform output server_public_ip` prints).

That's all `inventory.ini` holds, just a bare host list. The connection settings (which user to SSH as, which private key to use) used to sit on the same line as the IP, but that mixes "which hosts exist" with "how do I configure things for this group", which is a different concern. Ansible's standard convention is to keep host lists in the inventory file and put per-group configuration in a `group_vars/<group_name>.yml` file instead, so that's where they moved:

`01-single-server/ansible/group_vars/webserver.yml`:

```yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem
```

- The filename `webserver.yml` matches the group name `[webserver]` in the inventory exactly, that's how Ansible knows to apply these variables to that group. (A `group_vars/all.yml` would apply to every group instead.)
- `ansible_user: ubuntu` — the SSH user to connect as. Cumulus's Ubuntu images default to a user called `ubuntu`, same as the manual/Terraform phases.
- `ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem` — points Ansible at the relocated private key instead of a key sitting inside the project.

Both `inventory.ini` and `group_vars/webserver.yml` are gitignored (see `.gitignore` at the project root), since they carry environment-specific values, a real Cumulus IP and a local file path, that should never end up committed even by accident.

## Verify connectivity

```bash
cd ~/cumulus-lab/01-single-server/ansible
ansible webserver -i inventory.ini -m ping
```

`-i inventory.ini` tells Ansible which inventory file to read (instead of relying on a default). `-m ping` runs Ansible's built-in `ping` module, which isn't a network ping, it's an SSH connection test that confirms Ansible can log in and run a command as the configured user. A working connection returns:

```
xxx.xx.xx.xx | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If this fails on the very first attempt, see Troubleshooting entry 1 below, the first SSH connection to a brand-new instance almost always needs one manual step first.

## Keep the inventory in sync with Terraform

The instance's floating IP is not stable, it changes every time the instance is destroyed and recreated (`terraform apply` after a `terraform destroy`, or after certain resource replacements). `inventory.ini` had to be hand-edited after this happened once already, which is exactly the kind of manual step that's easy to forget and causes Ansible to fail against a stale IP.

`01-single-server/ansible/scripts/update-inventory.sh` automates that step: it reads the current IP straight from `terraform output -raw server_public_ip` (from `01-single-server/terraform/`) and overwrites `01-single-server/ansible/inventory.ini` with it.

```bash
./scripts/update-inventory.sh
```

Run this after every `terraform apply` and before running `ansible-playbook` (or the `ansible ... -m ping` check above). It can be run from any directory, it resolves its own paths relative to its own location (walking up from `ansible/scripts/` to the `01-single-server/` exercise root) rather than assuming a particular working directory.

It does not source the OpenStack credentials itself, since that requires an interactive password prompt that a script can't answer on its own. If `~/.cumulus-secrets/project-openrc.sh` hasn't already been sourced in the current shell, `terraform output` fails and the script prints a one-line hint:

```
Tip: source ~/.cumulus-secrets/project-openrc.sh first
```

This is a deliberately small fix, not the final version. A proper OpenStack dynamic inventory plugin (querying the cloud API directly instead of going through Terraform's state) would remove the need for this script and for `inventory.ini` entirely, but that's a planned later optimization, not done yet.

## Troubleshooting

### 1. Ansible `ping` fails with "Host key verification failed"

**Symptom:** the very first `ansible webserver -i inventory.ini -m ping` against a brand-new instance fails, with an error mentioning host key verification, even though the IP, user, and key path in `inventory.ini` are all correct.

**Cause:** SSH refuses to connect non-interactively to a host it has never seen before, because it has no way to confirm the server is who it claims to be (no entry for it yet in `~/.ssh/known_hosts`). Normally SSH would prompt "are you sure you want to continue connecting?" and wait for a yes/no answer, but Ansible runs non-interactively and has nothing to answer that prompt with, so it just fails instead.

**Fix:** connect once by hand first, and accept the fingerprint manually:

```bash
ssh -i ~/.cumulus-secrets/mykey.pem ubuntu@<floating-ip>
```

Type `yes` when prompted, then exit. That one connection writes an entry into `~/.ssh/known_hosts`, and every Ansible connection to that same IP after that works non-interactively.

**Note:** this needs to happen again for any new server that gets a floating IP address it hasn't been reachable on before, for example after a `terraform destroy` / `terraform apply` cycle that reassigns the same IP to a brand-new VM (see [manual-cli/troubleshooting.md](../manual-cli/troubleshooting.md) for the related case where the IP is reused and the *old* host key needs to be removed instead).

### 2. Playbook succeeds but the deployed site is unreachable from outside

**Symptom:** `ansible-playbook` finishes cleanly (`failed=0`), but `curl http://<floating-ip>:<port>` from outside Cumulus just hangs or times out.

**Cause:** Ansible and Terraform operate at two separate layers, and a successful Ansible run only proves the app-level layer is correct. Ansible configured the server itself (for example, nginx is installed, running, and listening on the new port). Terraform controls the network-level firewall (the security group) that decides which ports are even allowed to reach the server from outside at all. If the new port was never added to the security group, traffic never gets past Cumulus's network layer, regardless of how correctly nginx is configured on the server.

**Fix:** add the port to the `web_ports_open` list in `01-single-server/terraform/variables.tf`, then apply the change:

```bash
cd ~/cumulus-lab/01-single-server/terraform
terraform plan
terraform apply
```

`terraform plan` shows the new security group rule that will be added before committing to it. Once applied, the port is open at the network level and the site becomes reachable.

**Lesson:** if a deployment "works" according to the tool that ran it but the result isn't reachable, check whether the problem is actually one layer down (or up) from the tool that just succeeded. Ansible succeeding says nothing about what Terraform's security group currently allows.
