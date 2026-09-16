# Terraform (02-load-balanced) — File Structure

This provisions two private backend servers behind an nginx load balancer, entirely through Terraform `.tf` files in `02-load-balanced/terraform/`. It's kept completely separate from `01-single-server` — its own network (`192.168.1.0/24`, vs. `01-single-server`'s `192.168.0.0/24`), its own router, its own security groups — so that exercise stays untouched and comparable. This isn't a technical requirement, it's a deliberate choice to keep both exercises independently reproducible.

The `.tf` files themselves don't contain comments beyond a few short ones marking the trickier resources. Most of the explanation lives in this doc instead, same as `01-single-server`.

## main.tf

Identical in shape to `01-single-server/terraform/main.tf`: declares the `terraform-provider-openstack/openstack` provider (`~> 3.0`) and the `provider "openstack" { auth_url = ... }` block pointing at Cumulus. Credentials still come from the `OS_*` environment variables set by sourcing the Cumulus `openrc` file, never from anything in these files.

## variables.tf

Declares one input variable: `my_public_ip`.

- `variable "my_public_ip"` — the student's own public IP address, in CIDR notation (e.g. `203.0.113.7/32`), used to restrict SSH access to the load balancer and backend servers.
- No `default` is set on purpose. If it's not provided, Terraform stops and asks for it instead of silently using a wrong value.
- This exists at all because, unlike `01-single-server`'s original security group (SSH open to `0.0.0.0/0`), SSH here is deliberately not left open to the whole internet. Find your own IP with `curl ifconfig.me` from WSL, then supply it via a `terraform.tfvars` file (gitignored, since it's environment-specific) or with `-var="my_public_ip=..."` on the command line. See [commands.md](commands.md) for the exact steps.

## network.tf

The private network and subnet for this exercise, kept entirely separate from `01-single-server`'s.

- `openstack_networking_network_v2.ex2_private_network` — named `ex2-private-network`, `admin_state_up = true`.
- `openstack_networking_subnet_v2.ex2_private_subnet` — `cidr = "192.168.1.0/24"` (note the `.1.` — `01-single-server` uses `192.168.0.0/24`, so the two exercises' networks never overlap), `ip_version = 4`, `enable_dhcp = true`.

## router.tf

Its own router, same pattern as `01-single-server/terraform/router.tf`.

- `data "openstack_networking_network_v2" "campus_external_network"` — looks up the pre-existing `"campus"` external network by name, same data source pattern as Exercise 1.
- `openstack_networking_router_v2.ex2_router` — named `ex2-router`, `external_network_id` pointed at the campus network found above.
- `openstack_networking_router_interface_v2.ex2_router_interface` — attaches the router to `ex2_private_subnet`.

## security_group.tf

Two security groups instead of Exercise 1's one, because this exercise has two different kinds of server with two different exposure needs: the load balancer is meant to be reached from the internet, the backends are meant to be reached only through the load balancer.

**`ex2_lb_sg`** — attached to the load balancer.

- `ex2_lb_allow_http` — TCP port 80 ingress from `0.0.0.0/0`. The load balancer is the public-facing entry point for the whole exercise, so HTTP has to be open to everyone.
- `ex2_lb_allow_ssh` — TCP port 22 ingress, but `remote_ip_prefix = var.my_public_ip` instead of `0.0.0.0/0`. Only the student's own home IP can SSH into the load balancer directly.

**`ex2_backend_sg`** — attached to the backend servers.

- `ex2_backend_allow_from_lb` — TCP port 8080 ingress, with `remote_ip_prefix = "${openstack_networking_port_v2.ex2_lb_port.all_fixed_ips[0]}/32"`. This is the actual load-balancing enforcement point at the network level: only the load balancer's own private IP may reach the backends' web port. Backends are never meant to be hit directly, only routed to through the LB.
- `ex2_backend_allow_ssh_from_lb` — TCP port 22 ingress with `remote_group_id = openstack_networking_secgroup_v2.ex2_lb_sg.id` (a security-group reference, not a fixed IP). This rule didn't exist in the first pass — it was added after Ansible's ProxyJump connection to the backends got blocked, because the backend sees the SSH connection arriving from the LB's private IP, not the student's home IP. See [troubleshooting.md](../troubleshooting.md) entry 2 for the full story of finding this.
- `ex2_backend_allow_ssh` — TCP port 22 ingress from `var.my_public_ip`, same restriction as the load balancer, for direct SSH access to a backend when needed.

## ports.tf

Explicit network ports for every instance, same reasoning as `01-single-server/terraform/server.tf`'s port block: creating the port explicitly (rather than letting the instance auto-create one) gives the floating IP association something stable to attach to, and lets the security group be attached at the port level rather than the instance level.

- `openstack_networking_port_v2.ex2_backend_port` — `count = 2`, one port per backend, each with `security_group_ids = [openstack_networking_secgroup_v2.ex2_backend_sg.id]`. `depends_on` the private subnet, so DHCP is ready before a port tries to get an address from it.
- `openstack_networking_port_v2.ex2_lb_port` — the load balancer's single port, `security_group_ids = [openstack_networking_secgroup_v2.ex2_lb_sg.id]`, same `depends_on`.

## server.tf

The compute instances themselves.

- `openstack_compute_instance_v2.ex2_backend_server` — `count = 2`, named `ex2-backend-server-1` / `-2`. Each attaches to `openstack_networking_port_v2.ex2_backend_port[count.index]` via a `network { port = ... }` block, so each backend gets its own dedicated port and IP.
- `openstack_compute_instance_v2.ex2_loadbalancer_server` — named `ex2-loadbalancer-server`, attached to `ex2_lb_port`.
- Both use the same `image_name = "Ubuntu server 24.04.3 autoupgrade"`, `flavor_name = "c1-r1-d10"`, `key_pair = "mykey"`, and `availability_zone = "Education"` as `01-single-server`'s server. None of these instances gets a `security_groups` argument directly on the instance itself — same as Exercise 1, that argument is ignored once an instance is attached via an explicit port, only the port's `security_group_ids` matters.

## floating_ip.tf

Only the load balancer gets a floating IP. The backends never get one — they're private-network-only by design, reachable only from inside the network (i.e. from the load balancer), which is what `ex2_backend_sg` enforces.

- `openstack_networking_floatingip_v2.ex2_lb_floating_ip` — requests a floating IP from the `campus` external network.
- `openstack_networking_floatingip_associate_v2.ex2_lb_floating_ip_associate` — attaches it to `ex2_lb_port`. `depends_on = [openstack_networking_router_interface_v2.ex2_router_interface]`, same reasoning as Exercise 1's equivalent `depends_on`: wait for the router interface to fully attach before associating.
- `output "loadbalancer_public_ip"` — the floating IP the load balancer (and the whole site) is reachable on.
- `output "loadbalancer_private_ip"` — the load balancer's private IP, kept as an output in case a backend ever needs to know about it.
- `output "backend_private_ips"` — a list comprehension (`[for port in openstack_networking_port_v2.ex2_backend_port : port.all_fixed_ips[0]]`) over both backend ports, needed to fill in `02-load-balanced/ansible/inventory.ini`.

## See also

- [commands.md](commands.md) — the Terraform workflow commands for this exercise, including the `terraform.tfvars` setup
- [../troubleshooting.md](../troubleshooting.md) — the real problems hit building this stack (an unresolved SSH hang, the backend-SSH-blocked-via-LB fix, and the ProxyJump identity file issue)
- [../ansible.md](../ansible.md) — how Ansible reaches these servers and configures nginx on both roles
