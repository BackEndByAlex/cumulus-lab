resource "openstack_networking_network_v2" "campus_private_network" {
  name           = "campus-private-network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "campus_private_subnet" {
  name        = "campus-private-subnet"
  network_id  = openstack_networking_network_v2.campus_private_network.id
  cidr        = "192.168.0.0/24"
  ip_version  = 4
  enable_dhcp = true
}

