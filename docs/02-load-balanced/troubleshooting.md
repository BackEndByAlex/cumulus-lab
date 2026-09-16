# Load Balancer (02-load-balanced) — Troubleshooting

Real problems I ran into building this exercise, with causes and fixes. Search this page for your exact error message.

## 1. SSH to the load balancer hung indefinitely

**Symptom:** `ssh -i ~/.cumulus-secrets/mykey.pem ubuntu@<lb_floating_ip>` just hung with no response, had to Ctrl+C out of it. Running it verbose (`ssh -v`) showed it stuck at `Connecting to <ip> port 22`, it never completed the TCP handshake.

**Diagnosis:** everything I checked came back correctly configured:

- `openstack server list` — instance was `ACTIVE`
- `openstack floating ip list` — the floating IP was properly associated
- `openstack port show ex2-lb-port` — the correct security group was attached
- `openstack security group rule list ex2-lb-security-group` — a rule existed allowing TCP 22 from my exact public IP, confirmed matching via `curl ifconfig.me`, which returned the identical IP already in the rule
- `openstack router show ex2-router` — `enable_snat: true`, correct external network, router config was fine

**Cause:** not fully confirmed. Every layer I checked was configured correctly, yet the connection still hung. Why the exact-IP-matched security group rule didn't let the connection through was never conclusively proven. The plan was to check `$SSH_CONNECTION` from an active session to see the real source IP as the server saw it (in case something, like an ISP or campus NAT, was presenting a different IP than `curl ifconfig.me` reported), but I moved on to the next task before doing that check.

**Workaround applied (not a real fix):** temporarily opened SSH to the entire internet:

```bash
openstack security group rule create --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0 ex2-lb-security-group
```

This let the connection through immediately, which at least confirms the problem was specifically about IP-matching on the rule, not something else entirely (like the port or security group not being attached at all).

**Known security gap — not cleaned up:** this wide-open rule is still in place as of this writing. Port 22 is currently open to the entire internet on the load balancer. This needs to be narrowed back down once the real source IP is identified (via `$SSH_CONNECTION` or similar) and a corrected exact-match rule can replace the wide-open one.

## 2. Backend SSH access blocked when reached through the load balancer

**Symptom:** `ansible backends -i inventory.ini -m ping` (which uses an SSH ProxyJump through the load balancer to reach the private backend IPs) failed with:

```
Connection closed by UNKNOWN port 65535
```

**Cause:** the backend security group (`ex2_backend_sg`) only allowed SSH (port 22) from my own public IP. There was no rule allowing SSH from the load balancer itself. When Ansible tunnels through the LB, the backend sees the connection arriving from the LB's *private* IP, not mine, which didn't match any allow rule, so it was silently blocked.

**Fix:** added a new Terraform resource, `openstack_networking_secgroup_rule_v2.ex2_backend_allow_ssh_from_lb`, TCP port 22 ingress on `ex2_backend_sg`, with `remote_group_id` set to the LB's security group (`ex2_lb_sg.id`) instead of a specific IP, so it stays correct even if the LB's private IP changes later. Applied with `terraform apply` (1 resource added, 0 changed, 0 destroyed).

## 3. ProxyJump auth failed even after fixing the security group — identity file not inherited by the jump hop

**Symptom:** after fixing issue 2 above, `ansible backends -i inventory.ini -m ping` still failed with the exact same `Connection closed by UNKNOWN port 65535`.

**Cause:** a raw manual test isolated the real problem:

```bash
ssh -v -i ~/.cumulus-secrets/mykey.pem -o ProxyJump=ubuntu@<lb_ip> ubuntu@<backend_private_ip>
```

OpenSSH's implicit `ProxyCommand` spawned for the ProxyJump hop is a **separate** ssh process. It does not inherit the outer `-i` identity file flag. The verbose log showed it trying only default identities (`~/.ssh/id_rsa`, `id_ecdsa`, `id_ed25519`, etc.) against the load balancer itself, none of which were correct, resulting in `Permission denied (publickey)` connecting to the LB. The backend was never even reached.

**Fix:** created a dedicated SSH config file, `02-load-balanced/ansible/ssh.cfg`, with `Host` blocks matching the LB's IP and the backend private IP range (e.g. `192.168.1.*`), each specifying:

```
IdentityFile ~/.cumulus-secrets/mykey.pem
IdentitiesOnly yes
```

Because this file is read independently by both the outer ssh process and the spawned jump-hop process, each matching the target hostname against the same `Host` patterns on its own, the identity file now gets applied correctly to both hops.

I also set `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` in this file, for the same reason as `ansible.cfg`'s `host_key_checking = False`: Cumulus floating IPs change frequently between sessions, so strict host-key checking is pure friction here. Same caveat as before, this tradeoff is appropriate for an ephemeral lab, not production.

Referenced this file from `02-load-balanced/ansible/group_vars/backends.yml`:

```yaml
ansible_ssh_common_args: '-F <absolute_path_to_ssh.cfg>'
```

**Important:** it must be an absolute path. Ansible passes this string straight to the SSH binary without shell expansion, so a `~`-prefixed path literally fails with "No such file or directory". I hit this and fixed it during this session.

I also removed the now-redundant `ansible_ssh_private_key_file` from `backends.yml`, since the identity is now handled entirely by `ssh.cfg` for this group. Leaving both in place would have caused Ansible to inject a second, conflicting `-i` flag.

After this fix, `ansible backends -i inventory.ini -m ping` succeeded for both backends.

## Also worth knowing

The load balancer's floating IP is hardcoded in `ssh.cfg`'s `Host` patterns. If `terraform apply` ever recreates the load balancer, this file goes stale and needs manual updating. Unlike `01-single-server`, which has `scripts/update-inventory.sh` to automate this (see [01-single-server/terraform/troubleshooting.md](../01-single-server/terraform/troubleshooting.md) and [01-single-server/ansible.md](../01-single-server/ansible.md)), `02-load-balanced` currently has no equivalent automation. Same category of issue as the floating-IP-changes-on-recreate problem documented there, just not automated here yet.
