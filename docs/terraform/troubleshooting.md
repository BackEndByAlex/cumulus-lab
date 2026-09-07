# Terraform Troubleshooting

Real problems I ran into while building the Terraform version of the Cumulus stack, with causes and fixes. Search this page for your exact error message.

## 1. OpenStack auth errors after switching terminals

**Symptom:** `terraform plan` or `terraform apply` fails with an authentication error (for example, missing `auth_url` or credentials), even though it worked a few minutes earlier in a different terminal window or shell type.

**Cause:** the `OS_*` environment variables that `source project-openrc.sh` sets only exist inside the exact shell session where you sourced them. They aren't saved anywhere. Closing that terminal, opening a new one, or switching from Git Bash to PowerShell (or vice versa) starts a fresh session with none of those variables set. The resulting error can look unrelated to authentication (for example, a generic provider error), which makes it easy to mistake for a Terraform or config problem instead of a missing environment variable.

**Fix:** re-source the `openrc` file in whichever terminal session is about to run `terraform` commands:

```bash
source project-openrc.sh
```

Do this every time you open a new terminal window, even if it worked in a previous window a minute ago.

## 2. Floating IP association fails with 404 ExternalGatewayForFloatingIPNotFound

**Symptom:** `terraform apply` fails while creating `openstack_networking_floatingip_associate_v2` with an error along the lines of:

```
Error: Error associating floating IP: request failed:
404 Not Found: ExternalGatewayForFloatingIPNotFound
```

**Cause:** Neutron (OpenStack's networking service) needs an actual route from the private subnet out to the external ("campus") network to exist before it will let you associate a floating IP with a port on that subnet. That route is created by the router interface resource (`openstack_networking_router_interface_v2`, defined in `router.tf`).

Terraform normally figures out the correct order to create resources in automatically, by looking at which resources reference which. But `openstack_networking_floatingip_associate_v2` doesn't reference the router interface anywhere in its arguments. It only references the floating IP and the port. So Terraform has no way to know it needs to wait, and it can attempt the association before the router interface has finished attaching, causing the 404 above.

**Fix:** add an explicit `depends_on` in the association resource, pointing at the router interface:

```hcl
resource "openstack_networking_floatingip_associate_v2" "campus_server_floating_ip_associate" {
  floating_ip = openstack_networking_floatingip_v2.campus_server_floating_ip.address
  port_id     = openstack_networking_port_v2.campus_server_port.id

  depends_on = [openstack_networking_router_interface_v2.campus_router_interface]
}
```

`depends_on` forces an ordering dependency that isn't visible from the resource's own arguments. It tells Terraform "wait for this other resource to finish first," even though nothing here actually reads a value from it.
