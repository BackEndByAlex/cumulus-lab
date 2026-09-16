resource "openstack_networking_network_v2" "ex2_private_network" {
  name           = "ex2-private-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "ex2_private_subnet" {
  name        = "ex2-private-subnet"
  network_id  = openstack_networking_network_v2.ex2_private_network.id
  cidr        = "192.168.1.0/24"
  ip_version  = 4
  enable_dhcp = true
}
