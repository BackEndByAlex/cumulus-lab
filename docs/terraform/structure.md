# Terraform File Structure

This is a walkthrough of every `.tf` file in `terraform/`, explaining what each resource block does and why it's built the way it is. The `.tf` files themselves have no comments, so this document is where those explanations live instead.

Terraform doesn't care what order files load in, or that "main.tf" is named that. It reads every `.tf` file in the directory and combines them into one configuration. The files are split up by topic purely to keep things readable for a human.

## main.tf

Sets up Terraform itself before touching any infrastructure.

- `terraform { required_providers { ... } }` — declares which provider(s) this configuration needs, and which versions are acceptable. Terraform reads this before it does anything else. I'm using the official `terraform-provider-openstack/openstack` provider, version `~> 3.0` (any 3.x release).
- `provider "openstack" { auth_url = ... }` — configures the OpenStack provider. `auth_url` is hardcoded because it's the same for every student on Cumulus this course. It's not a secret, just the address of the API.
- Everything else the provider needs (username, project, password, region) comes from the `OS_*` environment variables set when you source the Cumulus `openrc` file in the shell, before running any `terraform` command. Credentials never go into `.tf` files, since those files are usually committed to git.

## variables.tf

Declares input variables, values that configure resources elsewhere without hardcoding them into the resource blocks themselves.

- `variable "web_ports_open"` — the list of ports the server's security group should allow inbound traffic on: `[22, 80]` (SSH + HTTP).
- `type = list(number)`, not `list(string)`: the OpenStack provider's `port_range_min` / `port_range_max` arguments are numbers, not strings. Declaring the real type here avoids relying on Terraform silently converting `"22"` into `22`, and matches what the provider actually expects.

## network.tf

The student's own private network and subnet. This replaces the `mynetwork` / `mysubnet` that were previously created by hand via `openstack network create` and `openstack subnet create` (see `docs/commands.md`, the old manual-CLI docs). Terraform now owns creating and destroying these.

- `openstack_networking_network_v2.campus_private_network` — the private network itself. `admin_state_up = true` means the network is reachable and usable, as opposed to administratively disabled.
- `openstack_networking_subnet_v2.campus_private_subnet` — the IP range attached to that network.
  - `network_id` — which network this subnet belongs to. Terraform resolves this to the actual network's ID once it's created, so you don't need to hardcode an ID.
  - `cidr = "192.168.0.0/24"` — matches the range used in the manual setup (256 addresses, 192.168.0.1–192.168.0.254 usable).
  - `ip_version = 4` — IPv4, not IPv6.
  - `enable_dhcp = true` — servers on this subnet get IP addresses automatically via DHCP, instead of needing static IP configuration.

## router.tf

The router that connects the private network to the outside world, plus the interface that plugs the private subnet into it. This replaces the manual `openstack router create` / `router set --external-gateway` / `router add subnet` commands.

- `data "openstack_networking_network_v2" "campus_external_network"` — `"campus"` is a pre-existing external network on Cumulus, so I don't create it. We just look up its ID so the router below can reference it. A `data` block reads information about something that already exists in OpenStack, instead of creating something new.
- `openstack_networking_router_v2.campus_router` — the router itself. `external_network_id` points at the "campus" network found via the data source above. This is the Terraform equivalent of `openstack router set myrouter --external-gateway campus`.
- `openstack_networking_router_interface_v2.campus_router_interface` — attaches the router to the private subnet, giving traffic from that subnet a path out through the router and eventually the campus network. Equivalent to `openstack router add subnet myrouter mysubnet`.

## security_group.tf

The security group (firewall) applied to the student's server. Replaces the manual `openstack security group create` / `openstack security group rule create` commands.

- `openstack_networking_secgroup_v2.web` — the security group itself, named `web-security-group`.
- `openstack_networking_secgroup_rule_v2.web_rules` — one ingress rule per port in `var.web_ports_open`, generated with `count`.
  - `count` tells Terraform "create this many copies of this resource". Here, one copy per entry in the ports list (2 entries makes 2 rules).
  - Inside the block, `count.index` is the position of the current copy in that list (0, then 1), so `var.web_ports_open[count.index]` picks out `22` on the first pass and `80` on the second. Without `count`, you'd have to copy-paste this rule once per port by hand.
  - `remote_ip_prefix = "0.0.0.0/0"` — allow from any source IP (standard for a publicly reachable SSH/HTTP server).
  - `depends_on = [openstack_networking_secgroup_v2.web]` — makes sure the security group exists before Terraform tries to attach rules to it.

## server.tf

The network port and the compute instance (the actual server). Replaces the manual `openstack server create` command, and gives the server a stable network attachment point to hang the floating IP off of in the next step.

- `openstack_networking_port_v2.campus_server_port` — a "port" is a network attachment point: what actually plugs a server into a network and gets it an IP address from DHCP. Normally this is invisible. If you just tell an instance "attach to this network," Terraform/OpenStack creates a port for you automatically behind the scenes.
  - I create the port explicitly instead of letting the instance auto-create one, because the next step (attaching a floating IP) needs something stable to point at. A floating IP association resource needs a port ID as its target, and if the port only exists implicitly inside the instance resource, there's nothing outside that resource to reference.
  - `security_group_ids = [openstack_networking_secgroup_v2.web.id]` — attaches the same `web` security group (SSH + HTTP rules) right at the network interface.
  - `depends_on = [openstack_networking_subnet_v2.campus_private_subnet]` — ensures the subnet (and its DHCP config) exists before OpenStack tries to hand this port an IP from it. Terraform usually figures out ordering automatically from references, but the subnet isn't directly referenced anywhere else in this block, so we have to spell it out explicitly.
- `openstack_compute_instance_v2.campus_web_server` — the actual server.
  - `image_name = "Ubuntu server 26.04.1 autoupgrade"` — exact image name as listed by `openstack image list` on Cumulus. `image_name` is simpler to read and write than `image_id`, and there's no ambiguity risk here since Cumulus doesn't have multiple images sharing this exact name.
  - `flavor_name = "c1-r1-d10"` — 1 vCPU / 1024MB RAM / 10GB disk.
  - `key_pair = "mykey"` — an existing keypair already created by hand via `openstack keypair create` (see `docs/commands.md`), with its matching `mykey.pem` private key the student already has. Terraform deliberately does NOT create a keypair resource here. Doing so would either fail (name already exists) or generate a brand-new keypair whose private key doesn't match the one already saved.
  - `availability_zone = "Education"` — matches the manual demo steps; this is where student servers are expected to land on Cumulus.
  - There's deliberately no `security_groups` argument on the instance itself. When an instance is attached via an explicit port (as here), the OpenStack provider ignores `security_groups` set on the instance. Only the port's `security_group_ids` actually matters. Setting it on the instance too would be dead configuration that looks like it works but does nothing.
  - `network { port = ... }` — attaches the instance to the port created above, instead of a network UUID directly. This is what gives the floating IP association step a stable, named target to attach to.

## floating_ip.tf

Requests a floating IP from the "campus" external network and attaches it to the server's port. Replaces the manual `openstack floating ip create campus` / `openstack server add floating ip` commands. This is what makes the server reachable from outside Cumulus at all.

- `openstack_networking_floatingip_v2.campus_server_floating_ip` — requests the floating IP.
  - `pool` takes the external network's NAME, not its ID, unlike most other resources in this stack. We reuse the data source from `router.tf` instead of hardcoding the string `"campus"` a second time, by reading its `.name` attribute rather than `.id`.
- `openstack_networking_floatingip_associate_v2.campus_server_floating_ip_associate` — attaches the floating IP to the port the server is plugged into.
  - This is the `networking_v2` variant (not `compute_floatingip_associate_v2`) because the server is attached via an explicit port rather than a plain network block. This resource is the one built to associate against a `port_id`.
  - `floating_ip` wants the actual IP address string here, not a resource ID.
  - `depends_on = [openstack_networking_router_interface_v2.campus_router_interface]` — forces Terraform to wait until the router interface has fully attached the private subnet before attempting the association. See `docs/terraform/troubleshooting.md` for the actual error this prevents.
- `output "server_public_ip"` — prints the server's public IP after `terraform apply` finishes, so you don't have to dig it out of the OpenStack dashboard by hand.
