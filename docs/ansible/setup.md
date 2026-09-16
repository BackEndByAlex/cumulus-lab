# WSL2 Control Node Setup

Phase 3 moves the toolchain off Windows entirely. Ansible has no native Windows support, it needs a Linux (or macOS, or WSL) control node to run from. Rather than juggle Terraform on Windows and Ansible somewhere else, I moved both onto the same WSL2 Ubuntu install, so the whole stack (Terraform provisioning + Ansible configuration) now runs from one shell.

From this point on, Terraform commands in `docs/terraform/commands.md` are run from inside WSL Ubuntu, not Git Bash on Windows. Everything else in that doc still applies as written.

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
cd ~/cumulus-lab/terraform
terraform init
```

`terraform init` has to be run fresh here, since the Terraform provider is a compiled binary and the Linux build is different from the Windows one downloaded earlier. Files under `/mnt/c/...` are also noticeably slower to work with from inside WSL than files that live natively in the Linux filesystem, which is the other reason for the move.

## 4. Move secrets out of the project entirely

Two things used to sit inside the repo that should never be at risk of being committed to git, even by accident:

- `mykey.pem` — the SSH private key, created out-of-band with `openstack keypair create --private-key mykey.pem mykey` (see `docs/commands.md`). This was never a Terraform-managed resource, Terraform only references the keypair by name.
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

## 5. Create the Ansible inventory

`ansible/inventory.ini` tells Ansible which host(s) to manage and how to reach them:

```ini
[webserver]
xxx.xx.xx.xx ansible_user=ubuntu ansible_ssh_private_key_file=~/.cumulus-secrets/mykey.pem
```

- `[webserver]` — a group name. Groups are how Ansible targets a set of hosts at once (`ansible webserver ...` below targets everything in this group).
- `xx.xx.xx.xx` — the server's floating IP (the same one `terraform output server_public_ip` prints).
- `ansible_user=ubuntu` — the SSH user to connect as. Cumulus's Ubuntu images default to a user called `ubuntu`, same as the manual/Terraform phases.
- `ansible_ssh_private_key_file=~/.cumulus-secrets/mykey.pem` — points Ansible at the relocated private key instead of a key sitting inside the project.

## 6. Verify connectivity

```bash
cd ~/cumulus-lab/ansible
ansible webserver -i inventory.ini -m ping
```

`-i inventory.ini` tells Ansible which inventory file to read (instead of relying on a default). `-m ping` runs Ansible's built-in `ping` module, which isn't a network ping, it's an SSH connection test that confirms Ansible can log in and run a command as the configured user. A working connection returns:

```
xxx.xx.xx.xx | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If this fails on the very first attempt, see `docs/ansible/troubleshooting.md`, the first SSH connection to a brand-new instance almost always needs one manual step first.
