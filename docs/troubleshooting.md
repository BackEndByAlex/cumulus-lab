# Troubleshooting

Real problems I ran into while working through the Cumulus lab, with causes and fixes. Search this page for your exact error message.

## 1. "No Network found for public"

Command that fails:

```bash
openstack router set myrouter --external-gateway public
```

**Cause:** the course slides use `public` as a generic example network name. The actual external network name depends on the deployment.

**Fix:** run the following first to find the real name:

```bash
openstack network list --external
```

On LNU's Cumulus it's `campus`. Use that name instead:

```bash
openstack router set myrouter --external-gateway campus
```

## 2. "Missing value auth-url required for auth plugin password"

**Cause:** no OpenStack credentials are loaded into the shell session.

**Fix:** download an RC file from the Cumulus dashboard (Project → API Access → Download OpenStack RC File), then source it in Git Bash before running any `openstack` command:

```bash
source project-openrc.sh
```

Plain PowerShell can't source `.sh` files. Use Git Bash or WSL instead.

It will prompt for the Cumulus password. This only lasts for that terminal session, so you need to re-source it in every new terminal window.

## 3. SSH key fails with "error in libcrypto: unsupported" (Windows-specific)

This is the most valuable finding in this document, and the reason this repo exists. The official slides don't mention it at all.

**Symptom:** running either of these fails:

```bash
ssh -i mykey.pem ubuntu@<ip>
openstack server ssh
```

with:

```
Load key "mykey.pem": error in libcrypto: unsupported
```

And `ssh-keygen -l -f mykey.pem` reports `mykey.pem is not a key file`, even though the file clearly starts with `-----BEGIN OPENSSH PRIVATE KEY-----`.

**Root cause:** on Windows, the `openstack` CLI (Python-based) can write the private key file using Windows text-mode line endings. That converts Unix `\n` into `\r\n` (CRLF). This corrupts the base64-encoded blocks inside the PEM structure, so libcrypto (used by both `ssh-keygen` and `ssh`) refuses to parse it, even though the file looks structurally correct at a glance (correct BEGIN/END headers).

This is **not** caused by:
- renaming the file
- capital letters in the filename
- file location

I ruled out all of those during debugging.

**Fix:** immediately after creating the key, strip carriage returns before ever touching it:

```bash
openstack keypair create --private-key mykey.pem mykey
sed -i 's/\r$//' mykey.pem
ssh-keygen -l -f mykey.pem   # should now print a clean fingerprint — confirms it's fixed
```

**Verification tip** for diagnosing it in the first place:

```bash
head -c 200 mykey.pem | cat -A | head -5
```

CRLF corruption shows up as `^M$` at line ends instead of just `$`.

Do this check **before** creating the server with `--key-name`. A server boots with the public key baked in via cloud-init at first boot only. If you discover the key is broken after the server already exists, you'll need to recreate both the keypair and the server (see next item).

## 4. Server unreachable after regenerating a keypair

**Cause:** SSH public keys are injected into a server only once, at first boot (via cloud-init). Deleting and recreating just the keypair doesn't update an already-running server. It still trusts the old, now-lost key.

**Fix:** if you had to regenerate the keypair because the original private key was corrupted or lost, you also need to delete and recreate the server:

```bash
openstack server delete server1
```

Then recreate it with `--key-name` pointing at the new keypair. You don't need to recreate the network, subnet, router, security group, or floating IP, just re-attach the security group and floating IP to the new server instance.

## 5. "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" on reconnect

**Cause:** after deleting and recreating the server, the same floating IP got reassigned to a brand-new VM with a different SSH host key. Your local `known_hosts` file still has the old host key cached for that IP address, so SSH (correctly) warns you it doesn't match, in case of an actual man-in-the-middle attack.

**Fix:** only do this when you're certain the change is legitimate (for example, you just recreated the server on purpose). Remove the stale entry and reconnect:

```bash
ssh-keygen -R <floating-ip>
ssh -i mykey.pem ubuntu@<floating-ip>
```
