# One private-network port per backend server. Backends never get a
# floating IP - they are only reachable from inside the private network
# (i.e. from the load balancer), enforced by ex2_backend_sg.
resource "openstack_networking_port_v2" "ex2_backend_port" {
  count = 2

  name       = "ex2-backend-port-${count.index + 1}"
  network_id = openstack_networking_network_v2.ex2_private_network.id

  security_group_ids = [openstack_networking_secgroup_v2.ex2_backend_sg.id]

  depends_on = [openstack_networking_subnet_v2.ex2_private_subnet]
}

# The load balancer's port on the private network. Its floating IP
# (see floating_ip.tf) is attached to this same port, the same pattern
# Exercise 1 uses for its single server.
resource "openstack_networking_port_v2" "ex2_lb_port" {
  name       = "ex2-lb-port"
  network_id = openstack_networking_network_v2.ex2_private_network.id

  security_group_ids = [openstack_networking_secgroup_v2.ex2_lb_sg.id]

  depends_on = [openstack_networking_subnet_v2.ex2_private_subnet]
}
