# Troubleshooting

Every issue below came up during the two runs of this lab: one in the portal, one in Terraform.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Ping and SSH from web → DB fail after adding `Allow-Web-Subnet` | The portal pre-fills **port 8080** when Service = Custom. The rule only matched TCP/UDP on 8080. ICMP (ping) has no port, so it fell through to the Deny. | Set **Destination port ranges** to `*`, or to the real DB port. Click **Save** and confirm in the rules list. |
| 2 | The NSG "lockdown" doesn't block anything | Default rule **65000 AllowVnetInBound** already allows all VNet traffic. An Allow on top of an Allow is a no-op. | Add **Deny, source `VirtualNetwork`, priority 4000** under the Allow. |
| 3 | `ping 10.0.2.4` succeeds in 0.03 ms but the NSG is set to Deny | You were on **vm-db-01**, pinging itself (loopback speed) | Check the prompt. `exit` until you're on the right host. Cross-subnet pings take ~1.5 ms. |
| 4 | `nc -zv 10.0.2.4 22` times out right after deploy, while ping works | Transient. A fresh VM and Azure's network programming need a few minutes to settle. | Wait and retry. Before changing anything, confirm each layer: `az network watcher test-ip-flow` (NSG), `az vm run-command ... "ufw status; iptables -S"` (host firewall), `ss -tln` (listener). |
| 5 | `systemctl is-active ssh` returns **inactive**, but port 22 is listening | Ubuntu 24.04 uses **socket activation**. `ssh.socket` holds :22 and starts `ssh.service` on demand. | Normal. Check `ss -tln \| grep :22` instead. |
| 6 | `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | The VM was rebuilt and reused the same IP, so it has a new host key | **Confirm you rebuilt it**, then run `ssh-keygen -R <ip>` and reconnect. Never clear this blindly on a server you didn't rebuild. |
| 7 | `Error: Too many command line arguments` on `terraform plan -out=lab02.tfplan` | **PowerShell** splits arguments at the `.` | Quote the flag: `terraform plan "-out=lab02.tfplan"` |
| 8 | `Identity file ... not accessible` when SSHing from a VM | You ran the command on a VM, but the key only exists on your laptop | Run SSH from your laptop. For the DB, use `ssh -J` (ProxyJump). |
| 9 | `az: command not found` | You ran an Azure CLI command inside a VM | Run `az` from your laptop |
| 10 | `mv: ~/Downloads/key-lab02.pem: No such file` | The key had already been moved | Run `ls -la ~/.ssh/`. Check the date and the `-r--------` permissions. |
| 11 | SSH: `UNPROTECTED PRIVATE KEY FILE` | Key permissions are too open | `chmod 400 ~/.ssh/key-lab02.pem` |
| 12 | Orphaned NSGs and public IP after deleting the VMs (portal) | The VM wizard doesn't delete NSGs, and the public IP needs a checkbox | Filter **All resources** by tag and delete the leftovers. A public IP left behind keeps billing. |
| 13 | Tag shows as `lab : lab02` with an empty value | The whole string was typed into the **Name** box | Name `lab`, Value `lab02` |
| 14 | Ubuntu 20.04 missing from the image list | End of standard support (April 2025) | Use Ubuntu Server 24.04 LTS |

## Useful diagnostic commands

```bash
# What does the NSG decide for this flow?
az network watcher test-ip-flow -g <rg> --vm vm-db-01 --direction Inbound \
  --protocol TCP --local 10.0.2.4:22 --remote 10.0.1.4:50000

# Run a command on a VM without network access to it
az vm run-command invoke -g <rg> -n vm-db-01 --command-id RunShellScript \
  --scripts "ss -tln | grep :22; ufw status; iptables -S | head"

# Every resource left in your RG
az resource list -g <rg> -o table
```
