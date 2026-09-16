# Your own public IP, used to lock down SSH access to the load balancer
# and backend servers so nobody else on the internet can try to log in.
#
# Find it by running this from WSL:
#   curl ifconfig.me
#
# Then either:
#   - put it in a terraform.tfvars file as: my_public_ip = "203.0.113.7/32"
#   - or pass it on the command line: terraform apply -var="my_public_ip=203.0.113.7/32"
#
# No default is set on purpose - if you forget to provide this, Terraform
# will stop and ask for it instead of silently using a wrong value.
variable "my_public_ip" {
  description = "Your public IP address in CIDR notation (e.g. 203.0.113.7/32), used to restrict SSH access."
  type        = string
}
