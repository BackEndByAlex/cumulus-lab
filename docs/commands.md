# Command Reference

This is the full, working command sequence for setting up an SSH-accessible Ubuntu server on Cumulus, in order. Run these in Git Bash on Windows (or any bash shell on Linux/macOS).

## Authenticate

```bash
# Authenticate — source the RC file downloaded from Cumulus dashboard (Project → API Access)
source project-openrc.sh
```

## 1. SSH Keypair

```bash
# 1. Create SSH keypair (name the private key file yourself, e.g. mykey.pem)
openstack keypair create --private-key mykey.pem mykey

# IMPORTANT (Windows only) — fix line endings immediately, see troubleshooting.md
sed -i 's/\r$//' mykey.pem
ssh-keygen -l -f mykey.pem   # confirms the key loads correctly before continuing
```

## 2-6. Networking

```bash
# 2. Create a router
openstack router create myrouter

# 3. Set the router's external gateway
# NOTE: the slides use "public" as a generic placeholder name — check your actual
# external network name first with: openstack network list --external
# On LNU's Cumulus this is called "campus"
openstack router set myrouter --external-gateway campus

# 4. Create a private network
openstack network create mynetwork

# 5. Create a subnet with an IP range
openstack subnet create --subnet-range 192.168.0.0/24 --network mynetwork mysubnet

# 6. Attach the router to the subnet
openstack router add subnet myrouter mysubnet
```

## 7-8. Server Creation

```bash
# 7. Check available images and flavors before creating the server
openstack image list
openstack flavor list
# Flavor naming convention: c<vCPUs>-r<RAM in MB>-d<disk in GB>
# e.g. c1-r1-d10 = 1 vCPU / 1024MB RAM / 10GB disk (matches the slides' spec)

# 8. Create the server
openstack server create --image "Ubuntu server 24.04.3 autoupgrade" \
  --flavor c1-r1-d10 \
  --key-name mykey \
  --network mynetwork \
  --availability-zone Education \
  server1

# check it's ACTIVE before continuing
openstack server show server1
```

## 9. Security Group

```bash
# 9. Create a security group and allow inbound SSH (port 22)
openstack security group create ssh-group
openstack security group rule create --dst-port 22 --protocol tcp --ingress ssh-group
openstack server add security group server1 ssh-group
```

## 10-11. Floating IP

```bash
# 10. Allocate a floating IP on the external network (campus, not public — see above)
openstack floating ip create campus
# note the floating_ip_address from the output

# 11. Attach the floating IP to the server
openstack server add floating ip server1 <your-floating-ip>
```

## 12. Connect

```bash
# 12. Connect
ssh -i mykey.pem ubuntu@<your-floating-ip>
```
