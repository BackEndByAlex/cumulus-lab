# Security group for the load balancer: open to the whole internet on
# HTTP, but SSH only from the student's own IP.
resource "openstack_networking_secgroup_v2" "ex2_lb_sg" {
  name        = "ex2-lb-security-group"
  description = "Allows inbound HTTP (80) from anywhere and SSH (22) from the student's IP only."
}

resource "openstack_networking_secgroup_rule_v2" "ex2_lb_allow_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.ex2_lb_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "ex2_lb_allow_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.my_public_ip
  security_group_id = openstack_networking_secgroup_v2.ex2_lb_sg.id
}

# Security group for the backend servers: only the load balancer may reach
# them on port 8080, and only the student's IP may SSH in directly.
resource "openstack_networking_secgroup_v2" "ex2_backend_sg" {
  name        = "ex2-backend-security-group"
  description = "Allows inbound HTTP-backend (8080) from the load balancer only, and SSH (22) from the student's IP only."
}

resource "openstack_networking_secgroup_rule_v2" "ex2_backend_allow_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = "${openstack_networking_port_v2.ex2_lb_port.all_fixed_ips[0]}/32"
  security_group_id = openstack_networking_secgroup_v2.ex2_backend_sg.id
}

# Allows SSH from the load balancer itself, since Ansible reaches the
# backends by SSH-jumping through the LB (ProxyJump), so the connection
# arrives from the LB's private IP rather than the student's home IP.
resource "openstack_networking_secgroup_rule_v2" "ex2_backend_allow_ssh_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.ex2_lb_sg.id
  security_group_id = openstack_networking_secgroup_v2.ex2_backend_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "ex2_backend_allow_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.my_public_ip
  security_group_id = openstack_networking_secgroup_v2.ex2_backend_sg.id
}
