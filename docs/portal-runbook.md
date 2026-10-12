# Portal Runbook (corrected)

This is the click-through version of the lab, with the original SOP's gaps fixed. Use it to learn what each resource is before automating it with the Terraform in [`../terraform`](../terraform).

**Estimated time:** 60 minutes · **Difficulty:** Beginner

## Naming

| Item | Value |
|---|---|
| Resource group | your existing RG (e.g. `BSpikes-RG`) |
| VNet | `vnet-lab02` · `10.0.0.0/16` |
| Web subnet | `snet-web` · `10.0.1.0/24` |
| DB subnet | `snet-db` · `10.0.2.0/24` |
| Web VM | `vm-web-01` |
| DB VM | `vm-db-01` |
| SSH key | `key-lab02` |
| Tag on everything | `lab = lab02` |

> **Shared subscription?** Pick your own RG on every create screen. The dropdown lists everyone's RGs.

---

## Phase 1: Network

1. **Virtual networks → + Create**
2. **Basics:** choose your RG, name `vnet-lab02`, region East US
3. **Security:** leave Bastion, Firewall, and DDoS **off** (they cost money)
4. **IP addresses:**
   - Address space `10.0.0.0/16`
   - **Delete the pre-filled `default` subnet**
   - Add `snet-web` at `10.0.1.0/24`
   - Add `snet-db` at `10.0.2.0/24`
   - Leave **Private subnet** enabled on both. This is Azure's newer default, which means no implicit outbound internet access.
5. **Tags:** Name `lab`, Value `lab02` (two separate boxes)
6. **Review + create → Create**

## Phase 2: Web server

1. **Virtual machines → + Create → Azure virtual machine**
2. **Basics:**
   - Name `vm-web-01`
   - Image **Ubuntu Server 24.04 LTS** (the original SOP's 20.04 is end-of-life)
   - Size `Standard_B1s`
   - Authentication: SSH public key, username `azureuser`, **Generate new key pair** named `key-lab02`
   - Public inbound ports: **HTTP (80)** and **SSH (22)**
3. **Disks:** Standard SSD, **Delete with VM** checked
4. **Networking:**
   - VNet `vnet-lab02`, subnet **`snet-web`**
   - Public IP: new
   - NIC NSG: Basic
   - Check **Delete public IP and NIC when VM is deleted**
5. **Management:** turn on auto-shutdown
6. **Tags:** `lab = lab02`
7. **Create**, then **Download private key**. Azure never shows it again.

On a Mac:

```bash
mkdir -p ~/.ssh
mv ~/Downloads/key-lab02.pem ~/.ssh/
chmod 400 ~/.ssh/key-lab02.pem
```

### Lock down SSH (not in the original SOP)

Go to **vm-web-01 → Networking → Network settings**, open the port **22** rule, set **Source** to **My IP address**, and click **Save**. Port 80 stays open to the internet.

## Phase 3: Database server

1. **Basics:**
   - Name `vm-db-01`, same image and size as the web VM
   - SSH key: **Use existing key stored in Azure → `key-lab02`**
   - Public inbound ports: **None**
2. **Networking (the critical step):**
   - Subnet **`snet-db`**. It defaults to the web subnet, so change it.
   - Public IP **None**
   - NIC NSG: Basic
3. **Tags**, then **Create**
4. Confirm the private IP is **10.0.2.4**

## Phase 4: The jump

```bash
ssh -i ~/.ssh/key-lab02.pem azureuser@<web-public-ip>
ping -c 4 10.0.2.4        # replies prove cross-subnet routing
exit

# Reach the DB itself without copying your key anywhere:
ssh-add ~/.ssh/key-lab02.pem
ssh -J azureuser@<web-public-ip> azureuser@10.0.2.4
curl -m 5 https://www.microsoft.com   # should time out
```

> The original SOP suggests copying the `.pem` to the web server. Don't. Use `ProxyJump`.

## Phase 5: NSG lockdown (corrected)

On **vm-db-01-nsg → Inbound security rules**, add these two rules:

| Field | Rule 1 | Rule 2 |
|---|---|---|
| Source | IP Addresses → `10.0.1.0/24` | **Service Tag → VirtualNetwork** |
| Destination port ranges | **`*`** ⚠️ *the portal pre-fills 8080, so change it* | `*` |
| Protocol | Any | Any |
| Action | Allow | **Deny** |
| Priority | 100 | **4000** |
| Name | `Allow-Web-Subnet` | `Deny-VNet-Inbound` |

The original SOP adds only Rule 1. On its own, Rule 1 restricts nothing, because the default rule 65000 `AllowVnetInBound` already allows the whole VNet. Rule 2 is what enforces the boundary.

### Verify both ways

1. From `vm-web-01`, run `ping -c 4 10.0.2.4`. Expect **0% loss**.
2. Switch Rule 1's Action to **Deny**, wait about 30 seconds, and ping again. Expect **100% loss**.
3. Switch Rule 1 back to **Allow** and confirm you get 0% loss again.

## Clean up (shared subscription)

**Don't delete the resource group.** Instead:

1. Go to **All resources** and filter on **Tag `lab = lab02`**
2. Delete both VMs
3. Delete leftover **NSGs** and the **public IP**. The VM wizard doesn't remove them.
4. Delete the **VNet** last
5. Refresh until the filtered list is empty
