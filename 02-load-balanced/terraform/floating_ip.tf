resource "openstack_networking_floatingip_v2" "ex2_lb_floating_ip" {
  pool = data.openstack_networking_network_v2.campus_external_network.name
}

resource "openstack_networking_floatingip_associate_v2" "ex2_lb_floating_ip_associate" {
  floating_ip = openstack_networking_floatingip_v2.ex2_lb_floating_ip.address
  port_id     = openstack_networking_port_v2.ex2_lb_port.id

  depends_on = [openstack_networking_router_interface_v2.ex2_router_interface]
}

output "loadbalancer_public_ip" {
  description = "The floating IP address the load balancer is reachable on (SSH + HTTP)."
  value       = openstack_networking_floatingip_v2.ex2_lb_floating_ip.address
}

output "loadbalancer_private_ip" {
  description = "The load balancer's private-network IP, used by backends if they ever need to know about it."
  value       = openstack_networking_port_v2.ex2_lb_port.all_fixed_ips[0]
}

output "backend_private_ips" {
  description = "Private-network IPs of the backend servers, needed to fill in ansible/inventory.ini."
  value       = [for port in openstack_networking_port_v2.ex2_backend_port : port.all_fixed_ips[0]]
}
