resource "openstack_networking_secgroup_v2" "web" {
  name        = "web-security-group"
  description = "Allows inbound SSH (22) and HTTP (80) traffic to the server."
}

resource "openstack_networking_secgroup_rule_v2" "web_rules" {
  count = length(var.web_ports_open)

  direction        = "ingress"
  ethertype        = "IPv4"
  protocol         = "tcp"
  port_range_min   = var.web_ports_open[count.index]
  port_range_max   = var.web_ports_open[count.index]
  remote_ip_prefix = "0.0.0.0/0"

  security_group_id = openstack_networking_secgroup_v2.web.id
  depends_on        = [openstack_networking_secgroup_v2.web]
}
