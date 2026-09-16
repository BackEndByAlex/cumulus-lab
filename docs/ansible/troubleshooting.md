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
