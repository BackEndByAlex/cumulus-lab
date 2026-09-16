resource "openstack_compute_instance_v2" "ex2_backend_server" {
  count = 2

  name = "ex2-backend-server-${count.index + 1}"

  image_name  = "Ubuntu server 24.04.3 autoupgrade"
  flavor_name = "c1-r1-d10"
  key_pair    = "mykey"

  availability_zone = "Education"

  network {
    port = openstack_networking_port_v2.ex2_backend_port[count.index].id
  }
}

resource "openstack_compute_instance_v2" "ex2_loadbalancer_server" {
  name = "ex2-loadbalancer-server"

  image_name  = "Ubuntu server 24.04.3 autoupgrade"
  flavor_name = "c1-r1-d10"
  key_pair    = "mykey"

  availability_zone = "Education"

  network {
    port = openstack_networking_port_v2.ex2_lb_port.id
  }
}
