resource "openstack_networking_port_v2" "campus_server_port" {
  name = "campus-server-port"

  network_id = openstack_networking_network_v2.campus_private_network.id

  security_group_ids = [openstack_networking_secgroup_v2.web.id]

  depends_on = [openstack_networking_subnet_v2.campus_private_subnet]
}

resource "openstack_compute_instance_v2" "campus_web_server" {
  name = "campus-web-server"

  image_name  = "Ubuntu server 24.04.3 autoupgrade"
  flavor_name = "c1-r1-d10"
  key_pair    = "mykey"

  availability_zone = "Education"

  network {
    port = openstack_networking_port_v2.campus_server_port.id
  }
}
