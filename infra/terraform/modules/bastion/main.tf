# =============================================================================
# Bastion Module - Main
# =============================================================================
# WHY: Provides secure admin access to private AKS clusters via a Jump Box VM.
# Azure Bastion eliminates the need for public IPs on the VM — all SSH traffic
# is tunneled through the Azure Portal or az cli.
#
# ARCHITECTURE:
#   Browser/CLI → Azure Bastion → Jump Box (Bastion VNet) ─── VNet Peering
#                                      │                         │
#                                      └─── kubectl ───→ Private AKS API (Env VNet)
#
# WHY SEPARATE VNet:
#   - Single Bastion serves ALL environments (dev/staging/prod) — cost optimization
#   - Each env VNet is peered to the Bastion VNet (hub-spoke pattern)
#   - Bastion VNet: 10.1.0.0/16 (no overlap with env VNets 10.0.0.0/16)
#   - Separate RG allows independent lifecycle — destroy Bastion without
#     affecting running workloads
#
# COST: Bastion Basic SKU (~$140/mo) + B2s VM (~$15/mo or $0 when deallocated)
#       One Bastion instead of N (one per env) saves ~$140/mo per additional env
# =============================================================================

# ---------------------------------------------------------------------------
# Virtual Network: Bastion (Hub)
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "bastion_vnet" {
  name                = "vnet-${var.project}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.bastion_vnet_address_space
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Subnet: AzureBastionSubnet (name is Azure-enforced)
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "bastion_snet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.bastion_vnet.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

# ---------------------------------------------------------------------------
# Subnet: Jump Box
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "jumpbox_snet" {
  name                 = "snet-jumpbox"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.bastion_vnet.name
  address_prefixes     = [var.jumpbox_subnet_cidr]
}

# ---------------------------------------------------------------------------
# NSG: Jump Box — SSH from Bastion + outbound to VNet/Azure/Internet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "jumpbox_nsg" {
  name                = "nsg-jumpbox-${var.project}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowBastionSSHInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVNetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowInternetHttpsOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "AllowInternetHttpOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllOutbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "jumpbox_nsg_assoc" {
  subnet_id                 = azurerm_subnet.jumpbox_snet.id
  network_security_group_id = azurerm_network_security_group.jumpbox_nsg.id
}

# ---------------------------------------------------------------------------
# VNet Peering: Bastion VNet ←→ Environment VNet (bidirectional)
# ---------------------------------------------------------------------------
# WHY bidirectional: The Jump Box initiates kubectl connections TO the AKS API
# server (bastion→env), and AKS responds back (env→bastion). Without both
# directions, TCP connections fail with timeouts.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "bastion_to_env" {
  name                      = "peer-bastion-to-${var.env_vnet_name}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.bastion_vnet.name
  remote_virtual_network_id = var.env_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "env_to_bastion" {
  name                      = "peer-${var.env_vnet_name}-to-bastion"
  resource_group_name       = var.env_vnet_resource_group_name
  virtual_network_name      = var.env_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.bastion_vnet.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# ---------------------------------------------------------------------------
# Private DNS Zone Link: AKS API server resolution from Bastion VNet
# ---------------------------------------------------------------------------
# WHY: Private AKS creates a DNS zone (privatelink.<region>.azmk8s.io) linked
# only to the AKS VNet. Without linking it to the Bastion VNet, the Jump Box
# can't resolve the AKS API server hostname → kubectl fails with DNS errors.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "aks_dns_to_bastion" {
  count = var.aks_private_dns_zone_name != "" ? 1 : 0

  name                  = "dnslink-bastion-to-aks"
  resource_group_name   = var.aks_private_dns_zone_resource_group
  private_dns_zone_name = var.aks_private_dns_zone_name
  virtual_network_id    = azurerm_virtual_network.bastion_vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

# ---------------------------------------------------------------------------
# Public IP for Azure Bastion
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "bastion_pip" {
  name                = "pip-bastion-${var.project}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Azure Bastion Host
# ---------------------------------------------------------------------------

resource "azurerm_bastion_host" "bastion" {
  name                = "bastion-${var.project}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion_snet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}

# ---------------------------------------------------------------------------
# Jump Box VM — SSH Key (auto-generated, stored in Terraform state)
# ---------------------------------------------------------------------------

resource "tls_private_key" "jumpbox_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ---------------------------------------------------------------------------
# Jump Box NIC (no public IP — Bastion-only access)
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "jumpbox_nic" {
  name                = "nic-jumpbox-${var.project}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "jumpbox-ipconfig"
    subnet_id                     = azurerm_subnet.jumpbox_snet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ---------------------------------------------------------------------------
# Jump Box VM
# ---------------------------------------------------------------------------
# cloud-init installs kubectl, helm, az cli, and kubelogin on first boot.
# ---------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = "vm-jumpbox-${var.project}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.jumpbox_vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.jumpbox_nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.jumpbox_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
      - unzip
    runcmd:
      # Install Azure CLI
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash

      # Install kubectl
      - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
      - apt-get update && apt-get install -y kubectl

      # Install Helm
      - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

      # Install kubelogin
      - az aks install-cli

      # Verify installs
      - echo "=== Installed tools ===" >> /var/log/cloud-init-tools.log
      - az version >> /var/log/cloud-init-tools.log 2>&1
      - kubectl version --client >> /var/log/cloud-init-tools.log 2>&1
      - helm version >> /var/log/cloud-init-tools.log 2>&1
      - kubelogin --version >> /var/log/cloud-init-tools.log 2>&1
  CLOUDINIT
  )
}
