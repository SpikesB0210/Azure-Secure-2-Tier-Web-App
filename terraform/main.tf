# ---------------------------------------------------------------------------
# Lab 02 - Secure 2-Tier Web Application (Terraform version)
# Everything lands in the EXISTING resource group BSpikes-RG.
# The RG is read with a data source, so `terraform destroy` never deletes it.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Public half of the key pair already stored in Azure (private half is ~/.ssh/<key>.pem)
data "azurerm_ssh_public_key" "lab" {
  name                = var.ssh_key_name
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Your current public IPv4, so SSH is open to you and nobody else
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  location = data.azurerm_resource_group.rg.location
  my_ip    = "${chomp(data.http.my_ip.response_body)}/32"
}

# ---------------------------- Phase 1: Network -----------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-lab02"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = data.azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = ["10.0.1.0/24"]
  default_outbound_access_enabled = false # private subnet (Azure's new default)
}

resource "azurerm_subnet" "db" {
  name                            = "snet-db"
  resource_group_name             = data.azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.vnet.name
  address_prefixes                = ["10.0.2.0/24"]
  default_outbound_access_enabled = false # no public IP + private subnet = no internet either way
}

# ------------------------- Web tier NSG (front end) ------------------------

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# ------------------------ DB tier NSG (Phase 5 fix) ------------------------
# The SOP only adds the Allow rule. Default rule 65000 (AllowVnetInBound)
# already allows the whole VNet, so the Allow alone restricts nothing.
# The Deny at 4000 is what actually locks the DB down to the web subnet.

resource "azurerm_network_security_group" "db" {
  name                = "nsg-db"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-Web-Subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = var.db_allow_web ? "Allow" : "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*" # production: "3306" (MySQL) or "5432" (PostgreSQL)
    source_address_prefix      = azurerm_subnet.web.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-VNet-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# --------------------------- Phase 2: Web server ---------------------------

resource "azurerm_public_ip" "web" {
  name                = "pip-vm-web-01"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "web" {
  name                = "nic-vm-web-01"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}

resource "azurerm_linux_virtual_machine" "web" {
  name                            = "vm-web-01"
  location                        = local.location
  resource_group_name             = data.azurerm_resource_group.rg.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.web.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.lab.public_key
  }

  os_disk {
    name                 = "osdisk-vm-web-01"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# ------------------------- Phase 3: Database server ------------------------
# No public IP. Reachable only from inside the VNet (and, after Phase 5,
# only from the web subnet).

resource "azurerm_network_interface" "db" {
  name                = "nic-vm-db-01"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.4"
  }
}

resource "azurerm_linux_virtual_machine" "db" {
  name                            = "vm-db-01"
  location                        = local.location
  resource_group_name             = data.azurerm_resource_group.rg.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.db.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = data.azurerm_ssh_public_key.lab.public_key
  }

  os_disk {
    name                 = "osdisk-vm-db-01"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# --------------- Auto-shutdown (protects the shared subscription) ----------

resource "azurerm_dev_test_global_vm_shutdown_schedule" "web" {
  virtual_machine_id    = azurerm_linux_virtual_machine.web.id
  location              = local.location
  enabled               = true
  daily_recurrence_time = "2200"
  timezone              = "Eastern Standard Time"
  tags                  = var.tags

  notification_settings {
    enabled = false
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "db" {
  virtual_machine_id    = azurerm_linux_virtual_machine.db.id
  location              = local.location
  enabled               = true
  daily_recurrence_time = "2200"
  timezone              = "Eastern Standard Time"
  tags                  = var.tags

  notification_settings {
    enabled = false
  }
}
