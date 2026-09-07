resource "openstack_networking_floatingip_v2" "campus_server_floating_ip" {
  pool = data.openstack_networking_network_v2.campus_external_network.name
}

resource "openstack_networking_floatingip_associate_v2" "campus_server_floating_ip_associate" {
  floating_ip = openstack_networking_floatingip_v2.campus_server_floating_ip.address
  port_id     = openstack_networking_port_v2.campus_server_port.id

  depends_on = [openstack_networking_router_interface_v2.campus_router_interface]
}

output "server_public_ip" {
  description = "The floating IP address the server is reachable on (SSH + HTTP)."
  value       = openstack_networking_floatingip_v2.campus_server_floating_ip.address
}
