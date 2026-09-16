# Ansible (02-load-balanced)

Once Terraform has provisioned the load balancer and both backends, Ansible connects over SSH to configure all three: installing nginx on the backends as plain web servers, and installing nginx on the load balancer configured as a reverse proxy. Same control node setup as `01-single-server` (see `docs/general/wsl-setup.md` and `docs/general/secrets-and-security.md`).

The interesting difference from `01-single-server` is that the backends have no public IP at all — Ansible has to reach them by tunneling through the load balancer.

## Inventory

`02-load-balanced/ansible/inventory.ini`:

```ini
[backends]
192.168.1.166
192.168.1.175

[loadbalancer]
172.27.62.135
```

Two groups instead of one: `[backends]` holds the two backends' private IPs (from `terraform output backend_private_ips`), `[loadbalancer]` holds the load balancer's floating IP (from `terraform output loadbalancer_public_ip`). Same as `01-single-server`, this file is gitignored, since it carries real environment-specific IPs.

## group_vars

Per-group connection settings live in `02-load-balanced/ansible/group_vars/`, same convention as `01-single-server`.

`group_vars/loadbalancer.yml`:

```yaml
ansible_user: ubuntu
ansible_ssh_private_key_file: ~/.cumulus-secrets/mykey.pem
```

Nothing unusual here — the load balancer has a public IP, so Ansible reaches it directly, exactly like `01-single-server`'s single server.

`group_vars/backends.yml`:

```yaml
ansible_user: ubuntu
ansible_ssh_common_args: '-F /home/sev3n/cumulus-lab/02-load-balanced/ansible/ssh.cfg'
```

No `ansible_ssh_private_key_file` here. Instead, `ansible_ssh_common_args` points SSH at a dedicated config file, `ssh.cfg`, which is what makes reaching the private backends possible at all.

## Reaching the backends: ProxyJump

The backends only exist on the `192.168.1.0/24` private network (see [terraform/structure.md](terraform/structure.md)) — they have no floating IP, and their security group only accepts traffic from the load balancer. Ansible can't reach them directly from outside Cumulus, so it has to tunnel its SSH connection through the load balancer instead, using SSH's `ProxyJump` feature.

`02-load-balanced/ansible/ssh.cfg` configures this:

```
Host 172.27.62.135
  User ubuntu
  IdentityFile ~/.cumulus-secrets/mykey.pem
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host 192.168.1.*
  User ubuntu
  IdentityFile ~/.cumulus-secrets/mykey.pem
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ProxyJump 172.27.62.135
```

The second `Host` block matches any backend private IP (`192.168.1.*`) and tells SSH to first jump through `172.27.62.135` (the load balancer's floating IP, hardcoded here) before connecting on. This exists as its own file, rather than a simpler `ansible_ssh_common_args` one-liner, because of an identity-file inheritance quirk in OpenSSH's `ProxyJump` handling — see [troubleshooting.md](troubleshooting.md) entry 3 for the full story of why a plain `-J`/`ProxyJump` flag on the command line wasn't enough and this dedicated config file was needed instead.

The backend security group also had to be opened for SSH from the load balancer's own security group (`ex2_backend_allow_ssh_from_lb` in `terraform/security_group.tf`), since the backend sees the tunneled connection arriving from the LB's private IP rather than the student's home IP. See [troubleshooting.md](troubleshooting.md) entry 2 for how that was discovered.

## Verify connectivity

```bash
cd ~/cumulus-lab/02-load-balanced/ansible
ansible loadbalancer -i inventory.ini -m ping
ansible backends -i inventory.ini -m ping
```

Same `ping` module as `01-single-server`, an SSH connection test rather than a network ping. Both should return `"ping": "pong"`.

## Roles

`site.yml` applies two roles:

```yaml
- name: Configure backend web servers
  hosts: backends
  become: true
  roles:
    - webserver

- name: Configure load balancer
  hosts: loadbalancer
  become: true
  roles:
    - loadbalancer
```

### webserver — reused unchanged from 01-single-server

The `webserver` role (`roles/webserver/`) is the exact same role from `01-single-server`, applied here to the `[backends]` group. It installs nginx and deploys `nginx.conf.j2`, which listens on `webserver_http_port` (`8080`, from `roles/webserver/vars/main.yml`) and serves the static `index.html`. No changes were needed to make it work for this exercise — both backends just run the same plain web server Exercise 1 already built.

### loadbalancer — new role, the actual load-balancing mechanism

`roles/loadbalancer/tasks/main.yml` installs nginx (same `apt` steps as `webserver`), then deploys `nginx-lb.conf.j2` to `/etc/nginx/sites-available/default`:

```nginx
upstream backend_servers {
{% for backend in groups['backends'] %}
  server {{ backend }}:8080;
{% endfor %}
}

server {
  listen {{ loadbalancer_http_port }} default_server;
  listen [::]:{{ loadbalancer_http_port }} default_server;

  server_name _;

  location / {
    proxy_pass http://backend_servers;
  }
}
```

`{% for backend in groups['backends'] %}` is a Jinja2 loop over the inventory's `[backends]` group, so the `upstream` block automatically lists both backends' private IPs on port 8080, whatever they currently are, without hardcoding them into the template. `proxy_pass http://backend_servers;` forwards all port-80 traffic arriving at the load balancer into that upstream group. This is the actual load-balancing mechanism for this exercise — nginx's default behavior for an `upstream` block with no explicit algorithm directive is round-robin, so no algorithm was configured explicitly.

## Verifying the load-balancing actually works

Running `ansible-playbook site.yml` cleanly (`failed=0` across all three hosts) only proves nginx is installed and configured on each host — it doesn't prove requests are actually being spread across both backends. To check that, each backend's `index.html` was temporarily overwritten with content identifying itself, using an ad-hoc `copy` command with the `inventory_hostname` variable:

```bash
ansible backends -i inventory.ini -m copy -a "content='{{ inventory_hostname }}' dest=/var/www/html/index.html"
```

Then curling the load balancer's public IP repeatedly:

```bash
curl http://<loadbalancer_public_ip>/
```

showed the response alternating between both backends' private IPs, confirming nginx's round-robin was actually distributing requests rather than always hitting the same backend. The real site content was restored afterward by re-running `ansible-playbook site.yml`, which redeploys the real `index.html` from the `webserver` role.

## See also

- [terraform/structure.md](terraform/structure.md) — the network and security group design behind why the backends are only reachable via ProxyJump in the first place
- [terraform/commands.md](terraform/commands.md) — the Terraform workflow that produces the IPs used in `inventory.ini`
- [troubleshooting.md](troubleshooting.md) — the full stories behind the ProxyJump identity file fix and the backend-SSH-from-LB security group rule
