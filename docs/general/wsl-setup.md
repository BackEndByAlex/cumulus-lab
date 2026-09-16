# WSL2 Control Node Setup

Ansible has no native Windows support, it needs a Linux (or macOS, or WSL) control node to run from. Rather than juggle Terraform on Windows and Ansible somewhere else, I moved both onto the same WSL2 Ubuntu install, so the whole stack (Terraform provisioning + Ansible configuration) now runs from one shell.

From this point on, all Terraform and Ansible commands in this project are run from inside WSL Ubuntu, not Git Bash on Windows.

## 1. Install Terraform in WSL

Terraform's Linux packages come from HashiCorp's own apt repository, not the default Ubuntu repos and not snap:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform
```

Confirm it worked:

```bash
terraform version
```

## 2. Install Ansible in WSL

The Ansible version in the default Ubuntu repos is usually stale. Ansible's own recommended method for Ubuntu is the `ppa:ansible/ansible` PPA:

```bash
sudo apt update
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

Confirm it worked:

```bash
ansible --version
```

## 3. Move the project into the WSL native filesystem

The project started out on the Windows side, under `/mnt/c/Users/<username>/Desktop/cumulus-lab`. I copied it into WSL's own native filesystem instead of working on it from the `/mnt/c/...` mount:

```bash
cp -r /mnt/c/Users/<username>/Desktop/cumulus-lab ~/cumulus-lab
cd ~/cumulus-lab/01-single-server/terraform
terraform init
```

`terraform init` has to be run fresh here, since the Terraform provider is a compiled binary and the Linux build is different from the Windows one downloaded earlier. Files under `/mnt/c/...` are also noticeably slower to work with from inside WSL than files that live natively in the Linux filesystem, which is the other reason for the move.

## Troubleshooting

### 1. "Failed to connect to system scope bus" during `apt` or `terraform init`

**Symptom:** running `sudo apt upgrade`, or even `terraform init`, prints a line like:

```
Failed to connect to system scope bus via local transport: No such file or directory
```

**Cause:** this comes from a systemd unit trigger trying to talk to systemd's D-Bus, which isn't fully running in this WSL2 setup. It's unrelated to whatever command actually printed it, apt and terraform just happen to trigger a package hook that tries to notify systemd of something.

**Fix:** nothing to fix. This is harmless noise, not an error. The command it appears next to still completes normally, check the actual exit status or the rest of the output rather than treating this line as a failure.
