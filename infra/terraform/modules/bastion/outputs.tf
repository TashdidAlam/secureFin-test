# =============================================================================
# Bastion Module - Outputs
# =============================================================================

output "bastion_name" {
  description = "Name of the Azure Bastion host"
  value       = azurerm_bastion_host.bastion.name
}

output "bastion_id" {
  description = "Resource ID of the Azure Bastion host"
  value       = azurerm_bastion_host.bastion.id
}

output "bastion_vnet_id" {
  description = "Resource ID of the Bastion VNet (for future peering with additional env VNets)"
  value       = azurerm_virtual_network.bastion_vnet.id
}

output "bastion_vnet_name" {
  description = "Name of the Bastion VNet"
  value       = azurerm_virtual_network.bastion_vnet.name
}

output "jumpbox_name" {
  description = "Name of the Jump Box VM"
  value       = azurerm_linux_virtual_machine.jumpbox.name
}

output "jumpbox_private_ip" {
  description = "Private IP of the Jump Box VM"
  value       = azurerm_network_interface.jumpbox_nic.private_ip_address
}

output "jumpbox_admin_username" {
  description = "Admin username for SSH into the Jump Box"
  value       = var.admin_username
}

output "jumpbox_ssh_private_key" {
  description = "SSH private key for the Jump Box (retrieve with: terraform output -raw jumpbox_ssh_private_key)"
  value       = tls_private_key.jumpbox_ssh.private_key_pem
  sensitive   = true
}
