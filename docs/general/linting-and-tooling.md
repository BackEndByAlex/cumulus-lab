# Linting and Tooling (pre-commit)

Both the Terraform and Ansible files in this project can silently drift out of style or break a convention without anything catching it until the next `terraform apply` or `ansible-playbook` run fails. `pre-commit` runs a set of checks automatically before every `git commit`, so problems get caught locally instead of on the next run against the real Cumulus infrastructure.

## Install the tools

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

## The hook configuration

`.pre-commit-config.yaml` at the project root:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.109.1
    hooks:
      - id: terraform_fmt
        files: ^(01-single-server|02-load-balanced)/terraform/
      - id: terraform_validate
        files: ^(01-single-server|02-load-balanced)/terraform/

  - repo: https://github.com/adrienverge/yamllint
    rev: v1.38.0
    hooks:
      - id: yamllint
        files: ^(01-single-server|02-load-balanced)/ansible/

  - repo: https://github.com/ansible/ansible-lint
    rev: v26.8.0
    hooks:
      - id: ansible-lint
        files: ^(01-single-server|02-load-balanced)/ansible/
```

- `terraform_fmt` / `terraform_validate` — run `terraform fmt -check` and `terraform validate` against each exercise's `terraform/` directory, catching formatting drift and syntax/reference errors before they ever reach `terraform plan`.
- `yamllint` — checks general YAML style (indentation, line length, document markers, etc.) against each exercise's `ansible/` directory.
- `ansible-lint` — checks Ansible-specific best practices (module naming, missing file permissions, handler conventions, etc.) against each exercise's `ansible/` directory. It layers on top of `yamllint`, it doesn't replace it.
- Each hook's `files:` pattern scopes it to the right directories, so Terraform hooks never run against Ansible YAML and vice versa. The `(01-single-server|02-load-balanced)` alternation covers both exercises with one hook definition instead of duplicating each hook per exercise.

Two supporting config files control what the YAML/Ansible hooks actually check:

`.yamllint` (project root) — relaxes the default line-length limit to 120 (80 is unrealistic for Ansible vars/playbooks) and adds a few specific rule overrides (`comments.min-spaces-from-content`, `comments-indentation`, `braces.max-spaces-inside`, `octal-values`) that `ansible-lint` requires in order to consider a custom `yamllint` config "compatible" with its own YAML rule — without these exact overrides, ansible-lint refuses to run its YAML fix-mode against the repo (see Troubleshooting below).

`.ansible-lint` (project root) — excludes both exercises' `terraform/` directories entirely, and skips the `yaml` rule family since `yamllint` already covers YAML style on its own.

## Register the hooks

```bash
cd ~/cumulus-lab
pre-commit install
```

From then on, every `git commit` automatically runs `pre-commit run` against whatever files are staged. The same check can also be run manually against every file in the repo, regardless of what's staged:

```bash
pre-commit run --all-files
```

Running this for the first time against the existing `ansible/roles/webserver/` files surfaced a number of real findings, missing `---` document-start markers, files missing a trailing newline, non-FQCN module names (e.g. `apt` instead of `ansible.builtin.apt`), missing explicit `mode:` on template/copy tasks, handler naming/casing issues, and a variable-naming/role-prefix convention violation. These are being fixed by hand in the role files as a learning exercise rather than auto-fixed by tooling, so some of them (missing document-start markers, at least) are still outstanding as of this write-up.

## Troubleshooting

### 1. YAML parsing failed: "Mapping values are not allowed in this context"

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

### 2. ansible-lint warns "Found incompatible custom yamllint configuration" and disables fix-mode

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
