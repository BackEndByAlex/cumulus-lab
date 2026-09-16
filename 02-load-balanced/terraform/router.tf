data "openstack_networking_network_v2" "campus_external_network" {
  name     = "campus"
  external = true
}

resource "openstack_networking_router_v2" "ex2_router" {
  name                = "ex2-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.campus_external_network.id
}

resource "openstack_networking_router_interface_v2" "ex2_router_interface" {
  router_id = openstack_networking_router_v2.ex2_router.id
  subnet_id = openstack_networking_subnet_v2.ex2_private_subnet.id
}
