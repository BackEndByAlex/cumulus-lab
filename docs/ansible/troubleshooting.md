# Ansible / WSL Troubleshooting

Real problems I ran into setting up the WSL2 control node and getting Ansible talking to the Cumulus server, with causes and fixes. Search this page for your exact error message.

## 1. "Failed to connect to system scope bus" during `apt` or `terraform init`

**Symptom:** running `sudo apt upgrade`, or even `terraform init`, prints a line like:

```
Failed to connect to system scope bus via local transport: No such file or directory
```

**Cause:** this comes from a systemd unit trigger trying to talk to systemd's D-Bus, which isn't fully running in this WSL2 setup. It's unrelated to whatever command actually printed it, apt and terraform just happen to trigger a package hook that tries to notify systemd of something.

**Fix:** nothing to fix. This is harmless noise, not an error. The command it appears next to still completes normally, check the actual exit status or the rest of the output rather than treating this line as a failure.

## 2. Ansible `ping` fails with "Host key verification failed"

**Symptom:** the very first `ansible webserver -i inventory.ini -m ping` against a brand-new instance fails, with an error mentioning host key verification, even though the IP, user, and key path in `inventory.ini` are all correct.

**Cause:** SSH refuses to connect non-interactively to a host it has never seen before, because it has no way to confirm the server is who it claims to be (no entry for it yet in `~/.ssh/known_hosts`). Normally SSH would prompt "are you sure you want to continue connecting?" and wait for a yes/no answer, but Ansible runs non-interactively and has nothing to answer that prompt with, so it just fails instead.

**Fix:** connect once by hand first, and accept the fingerprint manually:

```bash
ssh -i ~/.cumulus-secrets/mykey.pem ubuntu@<floating-ip>
```

Type `yes` when prompted, then exit. That one connection writes an entry into `~/.ssh/known_hosts`, and every Ansible connection to that same IP after that works non-interactively.

**Note:** this needs to happen again for any new server that gets a floating IP address it hasn't been reachable on before, for example after a `terraform destroy` / `terraform apply` cycle that reassigns the same IP to a brand-new VM (see `docs/troubleshooting.md#5-warning-remote-host-identification-has-changed-on-reconnect` for the related case where the IP is reused and the *old* host key needs to be removed instead).

## 3. YAML parsing failed: "Mapping values are not allowed in this context"

**Symptom:** running `ansible-playbook` fails immediately, before any task runs, with:

```
[ERROR]: YAML parsing failed: Mapping values are not allowed in this context.
```

**Cause:** I forgot the `- ` (dash + space) in front of a `name:` line somewhere in a playbook or tasks file. Plays in a playbook, tasks in a tasks file, and roles in a `roles:` list are all YAML *lists*, not plain key-value mappings. Every item in one of those lists needs a leading `- ` to mark it as a list entry. Without it, YAML reads the line as a plain mapping key sitting where a list item is expected, and the parser rejects the whole file rather than guessing what I meant.

**Fix:** check that every play, every task, and every role-list entry starts with `- `:

```yaml
- name: Install nginx
  apt:
    name: nginx
    state: present
```

not:

```yaml
  name: Install nginx
  apt:
    name: nginx
    state: present
```

**Tip:** install `yamllint` and run it against a playbook before handing it to `ansible-playbook`, it catches this kind of structural mistake without needing to actually run anything against a server:

```bash
sudo apt install yamllint
yamllint playbook.yml
```

## 4. Playbook succeeds but the deployed site is unreachable from outside

**Symptom:** `ansible-playbook` finishes cleanly (`failed=0`), but `curl http://<floating-ip>:<port>` from outside Cumulus just hangs or times out.

**Cause:** Ansible and Terraform operate at two separate layers, and a successful Ansible run only proves the app-level layer is correct. Ansible configured the server itself (for example, nginx is installed, running, and listening on the new port). Terraform controls the network-level firewall (the security group) that decides which ports are even allowed to reach the server from outside at all. If the new port was never added to the security group, traffic never gets past Cumulus's network layer, regardless of how correctly nginx is configured on the server.

**Fix:** add the port to the `web_ports_open` list in `terraform/variables.tf`, then apply the change:

```bash
cd ~/cumulus-lab/terraform
terraform plan
terraform apply
```

`terraform plan` shows the new security group rule that will be added before committing to it. Once applied, the port is open at the network level and the site becomes reachable.

**Lesson:** if a deployment "works" according to the tool that ran it but the result isn't reachable, check whether the problem is actually one layer down (or up) from the tool that just succeeded. Ansible succeeding says nothing about what Terraform's security group currently allows.

## 5. ansible-lint warns "Found incompatible custom yamllint configuration" and disables fix-mode

**Symptom:** running `ansible-lint` (directly, or via `pre-commit run --all-files`) prints:

```
WARNING Found incompatible custom yamllint configuration ...
```

and its own YAML-related fix-mode gets disabled, even though a project-level `.yamllint` file already exists and mostly works fine with plain `yamllint`.

**Cause:** `ansible-lint` ships its own YAML rule that normally delegates to `yamllint`, but only if the project's `.yamllint` config matches a specific set of settings it expects. My `.yamllint` extended the sensible `default` ruleset and relaxed `line-length`, but was still missing a few exact overrides `ansible-lint` requires before it will trust the config: `comments.min-spaces-from-content`, `comments-indentation`, `braces.max-spaces-inside`, and `octal-values`. Without those exact values present, `ansible-lint` treats the config as "incompatible" and quietly turns off the checks/fixes that depend on it, instead of failing loudly.

**Fix:** add the missing overrides to `.yamllint`:

```yaml
rules:
  comments:
    min-spaces-from-content: 1
  comments-indentation: false
  braces:
    max-spaces-inside: 1
  octal-values:
    forbid-implicit-octal: true
    forbid-explicit-octal: true
```

Once these exact values are present alongside the rest of the config, `ansible-lint` recognizes `.yamllint` as compatible and re-enables its YAML checks.
