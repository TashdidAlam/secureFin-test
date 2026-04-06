# =============================================================================
# Network Module - Main
# =============================================================================
# WHY: Defines the entire network topology for one environment in a single
# module. This ensures the VNet, subnets, and NSGs are always deployed as a
# unit — you can't accidentally create a subnet without its security rules.
#
# DESIGN DECISIONS:
# ─────────────────
# 1. One VNet per environment: Isolation between dev/staging/production at
#    the network level. No peering needed within a single environment.
#
# 2. Dedicated subnets: AKS gets its own subnet (Azure CNI requires it),
#    and private endpoints get a separate subnet to keep PaaS traffic
#    isolated from compute traffic.
#
# 3. Deny-by-default NSG: Attached to every subnet. Azure's implicit
#    "allow VNet" rules are overridden by explicit deny rules at a lower
#    priority. Only traffic we explicitly allow gets through.
#
# 4. No NAT Gateway yet: Will be added when AKS nodes need controlled
#    outbound access (Module 3+). For now, outbound uses Azure default SNAT.
# =============================================================================

# ---------------------------------------------------------------------------
# Virtual Network
# ---------------------------------------------------------------------------
# WHY a single VNet: In fintech, a single VNet per environment simplifies
# network policy enforcement, reduces peering complexity, and ensures all
# traffic between services stays on the Azure backbone (no public internet).
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "securefin_vnet" {
  name                = "vnet-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Subnet: AKS Cluster
# ---------------------------------------------------------------------------
# WHY a dedicated AKS subnet:
# - Azure CNI assigns pod IPs directly from this subnet (each pod = 1 IP)
# - Sizing: /24 = 251 usable IPs. Enough for dev/staging (~30 pods + nodes).
#   Production should use /22 or larger for pod density.
# - service_endpoints: not used here because we prefer private endpoints
#   for PaaS connectivity (stronger isolation than service endpoints).
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "securefin_aks_snet" {
  name                 = "snet-aks-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.securefin_vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
}

# ---------------------------------------------------------------------------
# Subnet: Private Endpoints
# ---------------------------------------------------------------------------
# WHY a dedicated private endpoint subnet:
# - Private endpoints for Key Vault, ACR, Storage, SQL etc. are placed here
# - Keeps PaaS NICs isolated from compute NICs (easier auditing)
# - private_endpoint_network_policies_enabled = false is REQUIRED for private
#   endpoint support on this subnet (Azure enforces policy behavior at the subnet level)
# - NSG is associated: traffic is controlled by the subnet NSG plus the PaaS
#   service firewall and private DNS configuration
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "securefin_pep_snet" {
  name                              = "snet-pep-${var.environment}"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.securefin_vnet.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
}

# ---------------------------------------------------------------------------
# Network Security Group: Deny-by-Default
# ---------------------------------------------------------------------------
# WHY deny-by-default:
# - Azure NSGs have 3 implicit rules (AllowVNetInBound, AllowAzureLBInBound,
#   DenyAllInBound) at priority 65000+. We can't delete them.
# - We add an EXPLICIT deny-all at priority 4096 (the highest user priority)
#   to make the deny intent visible in code and Azure Portal.
# - All "allow" rules must be added at LOWER priority numbers (higher
#   priority) with specific source/destination/port combinations.
# - This follows NIST 800-53 AC-4: deny-by-default information flow.
#
# RULE PRIORITY PLAN:
# 100-199: Critical infrastructure (AKS API server, Azure services)
# 200-299: Application traffic (ingress, inter-service)
# 300-399: Operations (monitoring, logging agents)
# 4096:    Explicit deny-all (catch-all)
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "securefin_aks_nsg" {
  name                = "nsg-aks-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # -------------------------------------------------------------------------
  # Rule: Allow inbound from Azure Load Balancer
  # -------------------------------------------------------------------------
  # WHY: AKS uses an internal Azure LB for service traffic distribution.
  # Without this rule, health probes and service routing fail silently.
  # Source "AzureLoadBalancer" is a service tag — not an IP range.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # -------------------------------------------------------------------------
  # Rule: Allow intra-VNet traffic
  # -------------------------------------------------------------------------
  # WHY: Pods, nodes, and internal services within the VNet must communicate.
  # Azure CNI assigns pod IPs from the VNet, so pod-to-pod traffic is VNet
  # traffic. Without this, kube-proxy, CoreDNS, and service mesh fail.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # -------------------------------------------------------------------------
  # Rule: Deny all other inbound traffic
  # -------------------------------------------------------------------------
  # WHY: Explicit deny-all at priority 4096. This overrides Azure's implicit
  # AllowVNetInBound (65000) by having a lower priority number (= higher
  # precedence). Makes the deny intent auditable in code and Portal.
  # -------------------------------------------------------------------------
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

  # -------------------------------------------------------------------------
  # Rule: Allow outbound to Azure services
  # -------------------------------------------------------------------------
  # WHY: AKS nodes need outbound access to Azure APIs (ARM, AAD, ACR, MCR)
  # for cluster operations, image pulls, and OIDC token exchange.
  # The "AzureCloud" service tag covers all Azure datacenter IPs.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  # -------------------------------------------------------------------------
  # Rule: Allow outbound VNet traffic
  # -------------------------------------------------------------------------
  # WHY: Same as inbound VNet rule — pods and nodes need bidirectional
  # communication within the VNet for service discovery and health checks.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowVNetOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # -------------------------------------------------------------------------
  # Rule: Allow outbound HTTPS to Internet
  # -------------------------------------------------------------------------
  # WHY: AKS nodes need outbound HTTPS for provisioning and runtime:
  #   - packages.microsoft.com (apt packages, AKS extensions)
  #   - mcr.microsoft.com (base container images — NOT in AzureCloud tag)
  #   - azure.archive.ubuntu.com (OS security patches)
  #   - login.microsoftonline.com (AAD token exchange)
  # Without this, CSE fails with OutboundConnFail (exit code 50).
  #
  # PRODUCTION NOTE: Replace with Azure Firewall + FQDN filtering for
  # granular egress control. This broad rule is acceptable for dev/test.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowInternetOutboundHttps"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  # -------------------------------------------------------------------------
  # Rule: Allow outbound HTTP to Internet
  # -------------------------------------------------------------------------
  # WHY: Some package repos (azure.archive.ubuntu.com, security.ubuntu.com)
  # serve apt packages over HTTP (port 80). Required during node bootstrap.
  # -------------------------------------------------------------------------
  security_rule {
    name                       = "AllowInternetOutboundHttp"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }

  # -------------------------------------------------------------------------
  # Rule: Deny all other outbound traffic
  # -------------------------------------------------------------------------
  # WHY: Prevents data exfiltration on non-HTTP(S) ports. AKS nodes can
  # reach Azure services (443), package repos (80/443), and VNet peers,
  # but all other outbound (SSH, FTP, custom ports) is blocked.
  # When Azure Firewall is added, this rule stays and the Internet rules
  # above are replaced with Firewall-routed FQDN rules.
  # -------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# NSG ↔ Subnet Association: AKS
# ---------------------------------------------------------------------------
# WHY associate explicitly: NSGs can float unattached in Azure (a common
# misconfiguration). Explicit association ensures the deny-by-default rules
# are enforced on the AKS subnet from the moment it's created.
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "securefin_aks_nsg_assoc" {
  subnet_id                 = azurerm_subnet.securefin_aks_snet.id
  network_security_group_id = azurerm_network_security_group.securefin_aks_nsg.id
}

# ---------------------------------------------------------------------------
# Network Security Group: Private Endpoints
# ---------------------------------------------------------------------------
# WHY: PCI-DSS requires every subnet to have an NSG for audit trail purposes.
# While Azure private endpoints bypass NSG enforcement at the NIC level,
# attaching an NSG documents intent and satisfies compliance scanning tools
# that flag unprotected subnets.
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "securefin_pep_nsg" {
  name                = "nsg-pep-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
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
}

resource "azurerm_subnet_network_security_group_association" "securefin_pep_nsg_assoc" {
  subnet_id                 = azurerm_subnet.securefin_pep_snet.id
  network_security_group_id = azurerm_network_security_group.securefin_pep_nsg.id
}
