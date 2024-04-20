output "jumpbox_public_ip_address" {
  value = azurerm_public_ip.jumpbox.ip_address
}

output "vmss_public_ip_fqdn" {
  value = azurerm_public_ip.vmss.fqdn
}