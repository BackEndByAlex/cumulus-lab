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
xxx.xx.xx.xx
```

- `[webserver]` — a group name. Groups are how Ansible targets a set of hosts at once (`ansible webserver ...` below targets everything in this group).
- `xx.xx.xx.xx` — the server's floating IP (the same one `terraform output server_public_ip` prints).

That's all `inventory.ini` holds now, just a bare host list. The connection settings (which user to SSH as, which private key to use) used to sit on the same line as the IP, but that mixes "which hosts exist" with "how do I configure things for this group", which is a different concern. Ansible's standard convention is to keep host lists in the inventory file and put per-group configuration in a `group_vars/<group_name>.yml` file instead, so that's where they moved:

`ansible/group_vars/webserver.yml`:

```yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem
```

- The filename `webserver.yml` matches the group name `[webserver]` in the inventory exactly, that's how Ansible knows to apply these variables to that group. (A `group_vars/all.yml` would apply to every group instead.)
- `ansible_user: ubuntu` — the SSH user to connect as. Cumulus's Ubuntu images default to a user called `ubuntu`, same as the manual/Terraform phases.
- `ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem` — points Ansible at the relocated private key instead of a key sitting inside the project.

This also matters for git: `inventory.ini` now only ever contains a real Cumulus IP, and `group_vars/webserver.yml` only ever contains local file paths, both environment-specific and both kept out of version control (see `.gitignore`), while a future teammate could still get a template `group_vars/webserver.yml.example` committed without leaking anything personal.

`inventory.ini` was already covered by the existing `.gitignore` pattern (`inventory.ini`, with no leading slash, matches it anywhere in the repo). `ansible/group_vars/webserver.yml` needed its own new line added, since it now carries the same kind of environment-specific values (`ansible_user`, and especially the local `ansible_ssh_private_key_file` path) that were being kept out of git before. A few other patterns were added at the same time for the same reason, secrets or environment-specific files that should never end up committed even by accident: `*.retry` (Ansible's automatically generated retry files after a failed playbook run), `group_vars/**/vault.yml`, `*.vault`, and `.vault_pass` (Ansible Vault encrypted-secrets files, not used yet in this project but ignored defensively).

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

## 7. Add pre-commit hooks (Terraform + Ansible linting)

Both the Terraform and Ansible files in this project can silently drift out of style or break a convention without anything catching it until the next `terraform apply` or `ansible-playbook` run fails. `pre-commit` runs a set of checks automatically before every `git commit`, so problems get caught locally instead of on the next run against the real Cumulus infrastructure.

Install the tools needed to run pre-commit's hooks:

```bash
sudo apt install python3.14-venv pipx yamllint
pipx install pre-commit
pipx install ansible-lint
pipx ensurepath
```

- `pipx` installs Python command-line tools (like `pre-commit` and `ansible-lint`) into their own isolated environments, so they don't clash with each other's dependencies or with whatever Python packages the system already has.
- `python3.14-venv` is a dependency `pipx` needs to create those isolated environments.
- `yamllint` is installed directly via `apt` rather than `pipx`, since it's also called from the hook config below and is simple enough not to need isolation.
- `pipx ensurepath` adds pipx's install location to `PATH` so `pre-commit` and `ansible-lint` are runnable as plain commands afterward (may need a new shell/terminal to take effect).

The hook configuration itself is `.pre-commit-config.yaml` at the project root:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.109.1
    hooks:
      - id: terraform_fmt
        files: ^terraform/
      - id: terraform_validate
        files: ^terraform/

  - repo: https://github.com/adrienverge/yamllint
    rev: v1.38.0
    hooks:
      - id: yamllint
        files: ^ansible/

  - repo: https://github.com/ansible/ansible-lint
    rev: v26.8.0
    hooks:
      - id: ansible-lint
        files: ^ansible/
```

- `terraform_fmt` / `terraform_validate` — run `terraform fmt -check` and `terraform validate` against `terraform/` only, catching formatting drift and syntax/reference errors before they ever reach `terraform plan`.
- `yamllint` — checks general YAML style (indentation, line length, document markers, etc.) against `ansible/` only.
- `ansible-lint` — checks Ansible-specific best practices (module naming, missing file permissions, handler conventions, etc.) against `ansible/` only. It layers on top of `yamllint`, it doesn't replace it.
- Each hook's `files:` pattern scopes it to the right directory, so Terraform hooks never run against Ansible YAML and vice versa.

Two supporting config files control what the YAML/Ansible hooks actually check:

`.yamllint` (project root) — relaxes the default line-length limit to 120 (80 is unrealistic for Ansible vars/playbooks) and adds a few specific rule overrides (`comments.min-spaces-from-content`, `comments-indentation`, `braces.max-spaces-inside`, `octal-values`) that `ansible-lint` requires in order to consider a custom `yamllint` config "compatible" with its own YAML rule — without these exact overrides, ansible-lint refuses to run its YAML fix-mode against the repo (see `docs/ansible/troubleshooting.md`).

`.ansible-lint` (project root) — excludes `terraform/` entirely, and skips the `yaml` rule family since `yamllint` already covers YAML style on its own.

Finally, register the hooks so they actually run on commit:

```bash
cd ~/cumulus-lab
pre-commit install
```

From then on, every `git commit` automatically runs `pre-commit run` against whatever files are staged. The same check can also be run manually against every file in the repo, regardless of what's staged:

```bash
pre-commit run --all-files
```

Running this for the first time against the existing `ansible/roles/webserver/` files surfaced a number of real findings, missing `---` document-start markers, files missing a trailing newline, non-FQCN module names (e.g. `apt` instead of `ansible.builtin.apt`), missing explicit `mode:` on template/copy tasks, handler naming/casing issues, and a variable-naming/role-prefix convention violation. These are being fixed by hand in the role files as a learning exercise rather than auto-fixed by tooling, so they're not resolved yet as of this write-up.
