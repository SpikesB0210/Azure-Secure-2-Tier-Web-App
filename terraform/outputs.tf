output "web_public_ip" {
  value = azurerm_public_ip.web.ip_address
}

output "web_private_ip" {
  value = azurerm_network_interface.web.private_ip_address
}

output "db_private_ip" {
  value = azurerm_network_interface.db.private_ip_address
}

output "ssh_allowed_from" {
  value = local.my_ip
}

output "ssh_to_web" {
  value = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ${var.admin_username}@${azurerm_public_ip.web.ip_address}"
}

output "ssh_to_db_via_jump" {
  value = "ssh -J ${var.admin_username}@${azurerm_public_ip.web.ip_address} ${var.admin_username}@${azurerm_network_interface.db.private_ip_address}"
}
