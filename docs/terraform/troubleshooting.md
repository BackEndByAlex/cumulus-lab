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

## 3. Invalid resource type: openstack_blockstorage_volume_v2

**Symptom:** `terraform apply` fails with:

```
Error: Invalid resource type
The provider terraform-provider-openstack/openstack does not support resource type "openstack_blockstorage_volume_v2". Did you mean "openstack_blockstorage_volume_v3"?
```

**Cause:** I wrote `volume.tf` following an older workshop PDF slide that still showed `openstack_blockstorage_volume_v2`. That resource type was removed in provider version 3.0.0. The provider I'm actually using is 3.4.0, so the v2 name doesn't exist anymore. The v3 name (`openstack_blockstorage_volume_v3`) has existed alongside v2 for a while and is now the only option.

**Fix:** rename the resource type from `openstack_blockstorage_volume_v2` to `openstack_blockstorage_volume_v3`, keep the local resource name and all arguments the same, and update every reference to it elsewhere (in my case, the `volume_id` argument in `openstack_compute_volume_attach_v2`).

**Note:** I checked `openstack_compute_volume_attach_v2` too, since it also touches volumes. That one is a different resource and it's still correct as `v2` in provider 3.4.0. There's no `v3` version of it. I don't want to rename resource types just because a similar-sounding one changed, so I checked the provider changelog before touching it instead of guessing.

## 4. Volume creation fails with "Availability zone 'Education' is invalid"

**Symptom:** `terraform apply` fails while creating `openstack_blockstorage_volume_v3` with:

```
Error: Error creating openstack_blockstorage_volume_v3: ...
"Availability zone 'Education' is invalid."
```

**Cause:** I assumed the volume needed to be in the same availability zone as the server, so I set `availability_zone = "Education"` to match `server.tf`. That's wrong. Compute (Nova) and block storage (Cinder) each have their own separate list of availability zones on OpenStack. They don't have to share the same names, and on Cumulus they don't. Cumulus only exposes one Cinder AZ, and it isn't called `"Education"`.

**Fix:** check the actual valid Cinder AZ instead of guessing or reusing the Nova one:

```bash
openstack availability zone list --volume
```

On Cumulus this returns `nova`. So the fix is:

```hcl
availability_zone = "nova"
```

**Lesson:** don't assume a value carries over between resource types just because it worked elsewhere in the same stack. Compute AZs and storage AZs are different namespaces, and I should check each one directly with the CLI instead of assuming.
