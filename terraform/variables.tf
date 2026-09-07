variable "web_ports_open" {
  description = "Ports to allow inbound access on, for the server's security group (SSH + HTTP)."
  type        = list(number)
  default     = [22, 80]
}
