# =============================================================================
# SecureFin Platform - Post-Deployment Validation Script (PowerShell)
# =============================================================================
# Usage:
#   .\scripts\Post-Deployment-Validation.ps1 -Environment dev
#
# Prerequisites:
#   - Azure CLI (az) authenticated
#   - Az PowerShell module NOT required (uses az CLI only)
# =============================================================================

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "production")]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
$Project    = "securefin"
$RgCore     = "rg-$Project-core-$Environment"
$RgAks      = "rg-$Project-aks-$Environment"
$RgData     = "rg-$Project-data-$Environment"
$AksName    = "aks-$Project-$Environment"
$VnetName   = "vnet-$Project-$Environment"
$LawName    = "law-$Project-$Environment"
$IdentityName = "id-$Project-workload-$Environment"

$Pass = 0
$Fail = 0
$Warn = 0

$RequiredTags = @("Project", "Environment", "Owner", "CostCenter", "ManagedBy")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Check {
    param([string]$Status, [string]$Message)
    switch ($Status) {
        "PASS" { Write-Host "  [PASS] $Message" -ForegroundColor Green; $script:Pass++ }
        "FAIL" { Write-Host "  [FAIL] $Message" -ForegroundColor Red; $script:Fail++ }
        "WARN" { Write-Host "  [WARN] $Message" -ForegroundColor Yellow; $script:Warn++ }
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 1. Resource Groups
# ---------------------------------------------------------------------------
Write-Section "1. Resource Groups"

foreach ($rg in @($RgCore, $RgAks, $RgData)) {
    $exists = az group show --name $rg --query "name" -o tsv 2>$null
    if ($exists) {
        Write-Check "PASS" "Resource group '$rg' exists"

        # Check tags
        $rgTags = az group show --name $rg --query "tags" -o json 2>$null | ConvertFrom-Json
        $missingTags = @()
        foreach ($tag in $RequiredTags) {
            if (-not ($rgTags.PSObject.Properties.Name -contains $tag)) {
                $missingTags += $tag
            }
        }
        if ($missingTags.Count -eq 0) {
            Write-Check "PASS" "'$rg' has all required tags"
        } else {
            Write-Check "FAIL" "'$rg' missing tags: $($missingTags -join ', ')"
        }
    } else {
        Write-Check "FAIL" "Resource group '$rg' does NOT exist"
    }
}

# ---------------------------------------------------------------------------
# 2. Virtual Network & Subnets
# ---------------------------------------------------------------------------
Write-Section "2. Network (VNet, Subnets, NSGs)"

$vnet = az network vnet show --resource-group $RgCore --name $VnetName --query "name" -o tsv 2>$null
if ($vnet) {
    Write-Check "PASS" "VNet '$VnetName' exists in '$RgCore'"
} else {
    Write-Check "FAIL" "VNet '$VnetName' NOT found in '$RgCore'"
}

# Subnets
foreach ($snet in @("snet-aks-$Environment", "snet-pep-$Environment")) {
    $subnet = az network vnet subnet show --resource-group $RgCore --vnet-name $VnetName --name $snet --query "name" -o tsv 2>$null
    if ($subnet) {
        Write-Check "PASS" "Subnet '$snet' exists"
    } else {
        Write-Check "FAIL" "Subnet '$snet' NOT found"
    }
}

# NSGs
foreach ($nsgName in @("nsg-aks-$Project-$Environment", "nsg-pep-$Project-$Environment")) {
    $nsg = az network nsg show --resource-group $RgCore --name $nsgName --query "name" -o tsv 2>$null
    if ($nsg) {
        Write-Check "PASS" "NSG '$nsgName' exists"
        # Count rules
        $ruleJson = az network nsg rule list --resource-group $RgCore --nsg-name $nsgName -o json 2>$null | ConvertFrom-Json
        $ruleCount = $ruleJson.Count
        Write-Check "PASS" "'$nsgName' has $ruleCount custom rules"
    } else {
        Write-Check "FAIL" "NSG '$nsgName' NOT found"
    }
}

# NSG-Subnet associations
$aksSnetNsg = az network vnet subnet show --resource-group $RgCore --vnet-name $VnetName --name "snet-aks-$Environment" --query "networkSecurityGroup.id" -o tsv 2>$null
if ($aksSnetNsg) {
    Write-Check "PASS" "AKS subnet has NSG associated"
} else {
    Write-Check "FAIL" "AKS subnet has NO NSG association"
}

$pepSnetNsg = az network vnet subnet show --resource-group $RgCore --vnet-name $VnetName --name "snet-pep-$Environment" --query "networkSecurityGroup.id" -o tsv 2>$null
if ($pepSnetNsg) {
    Write-Check "PASS" "PEP subnet has NSG associated"
} else {
    Write-Check "FAIL" "PEP subnet has NO NSG association"
}

# ---------------------------------------------------------------------------
# 3. AKS Cluster
# ---------------------------------------------------------------------------
Write-Section "3. AKS Cluster"

$aksJson = az aks show --resource-group $RgAks --name $AksName -o json 2>$null
if ($aksJson) {
    $aks = $aksJson | ConvertFrom-Json
    Write-Check "PASS" "AKS cluster '$AksName' exists"
    Write-Check "PASS" "Provisioning state: $($aks.provisioningState)"

    # Private cluster
    if ($aks.apiServerAccessProfile.enablePrivateCluster -eq $true) {
        Write-Check "PASS" "Private cluster enabled"
    } else {
        Write-Check "FAIL" "Private cluster NOT enabled"
    }

    # OIDC issuer
    if ($aks.oidcIssuerProfile.enabled -eq $true) {
        Write-Check "PASS" "OIDC issuer enabled"
    } else {
        Write-Check "FAIL" "OIDC issuer NOT enabled"
    }

    # Workload identity
    if ($aks.securityProfile.workloadIdentity.enabled -eq $true) {
        Write-Check "PASS" "Workload identity enabled"
    } else {
        Write-Check "FAIL" "Workload identity NOT enabled"
    }

    # Azure Policy
    if ($aks.addonProfiles.azurepolicy.enabled -eq $true) {
        Write-Check "PASS" "Azure Policy addon enabled"
    } else {
        Write-Check "FAIL" "Azure Policy addon NOT enabled"
    }

    # OMS Agent (Container Insights)
    if ($aks.addonProfiles.omsagent.enabled -eq $true) {
        Write-Check "PASS" "OMS Agent (Container Insights) enabled"
    } else {
        Write-Check "FAIL" "OMS Agent NOT enabled"
    }

    # Secrets Store CSI
    if ($aks.addonProfiles.azureKeyvaultSecretsProvider.enabled -eq $true) {
        Write-Check "PASS" "Secrets Store CSI Driver enabled"
        $rotation = $aks.addonProfiles.azureKeyvaultSecretsProvider.config.enableSecretRotation
        if ($rotation -eq "true") {
            Write-Check "PASS" "Secret rotation enabled"
        } else {
            Write-Check "WARN" "Secret rotation NOT enabled"
        }
    } else {
        Write-Check "FAIL" "Secrets Store CSI Driver NOT enabled"
    }

    # Local accounts disabled
    if ($aks.disableLocalAccounts -eq $true) {
        Write-Check "PASS" "Local accounts disabled"
    } else {
        Write-Check "FAIL" "Local accounts NOT disabled"
    }

    # AAD RBAC
    if ($aks.aadProfile.enableAzureRbac -eq $true) {
        Write-Check "PASS" "Azure AD RBAC enabled"
    } else {
        Write-Check "FAIL" "Azure AD RBAC NOT enabled"
    }

    # Network plugin
    if ($aks.networkProfile.networkPlugin -eq "azure") {
        Write-Check "PASS" "Network plugin: Azure CNI"
    } else {
        Write-Check "FAIL" "Network plugin: $($aks.networkProfile.networkPlugin) (expected: azure)"
    }

    # Network policy
    if ($aks.networkProfile.networkPolicy -eq "azure") {
        Write-Check "PASS" "Network policy: Azure"
    } else {
        Write-Check "FAIL" "Network policy: $($aks.networkProfile.networkPolicy) (expected: azure)"
    }

    # Upgrade channel
    $upgradeChannel = $aks.autoUpgradeProfile.upgradeChannel
    if ($upgradeChannel -eq "stable") {
        Write-Check "PASS" "Upgrade channel: stable"
    } else {
        Write-Check "WARN" "Upgrade channel: $upgradeChannel (expected: stable)"
    }

    # Node pool checks
    $nodePool = $aks.agentPoolProfiles[0]
    Write-Check "PASS" "Node pool '$($nodePool.name)': $($nodePool.count) node(s), VM size $($nodePool.vmSize)"

    if ($nodePool.osDiskType -eq "Ephemeral") {
        Write-Check "PASS" "OS disk type: Ephemeral"
    } else {
        Write-Check "WARN" "OS disk type: $($nodePool.osDiskType) (expected: Ephemeral)"
    }

    if ($nodePool.maxPods -ge 50) {
        Write-Check "PASS" "Max pods: $($nodePool.maxPods) (>= 50)"
    } else {
        Write-Check "FAIL" "Max pods: $($nodePool.maxPods) (expected >= 50)"
    }

    # Kubernetes version
    Write-Check "PASS" "Kubernetes version: $($aks.kubernetesVersion)"

    # Tags
    $aksTags = $aks.tags
    $missingAksTags = @()
    foreach ($tag in $RequiredTags) {
        if (-not ($aksTags.PSObject.Properties.Name -contains $tag)) {
            $missingAksTags += $tag
        }
    }
    if ($missingAksTags.Count -eq 0) {
        Write-Check "PASS" "AKS cluster has all required tags"
    } else {
        Write-Check "FAIL" "AKS cluster missing tags: $($missingAksTags -join ', ')"
    }
} else {
    Write-Check "FAIL" "AKS cluster '$AksName' NOT found"
}

# ---------------------------------------------------------------------------
# 4. Log Analytics Workspace
# ---------------------------------------------------------------------------
Write-Section "4. Log Analytics Workspace"

$law = az monitor log-analytics workspace show --resource-group $RgAks --workspace-name $LawName --query "name" -o tsv 2>$null
if ($law) {
    Write-Check "PASS" "Log Analytics workspace '$LawName' exists"
    $lawSku = az monitor log-analytics workspace show --resource-group $RgAks --workspace-name $LawName --query "sku.name" -o tsv 2>$null
    Write-Check "PASS" "LAW SKU: $lawSku"
} else {
    Write-Check "FAIL" "Log Analytics workspace '$LawName' NOT found"
}

# ---------------------------------------------------------------------------
# 5. Managed Identity & Federated Credential
# ---------------------------------------------------------------------------
Write-Section "5. Workload Identity"

$identity = az identity show --resource-group $RgCore --name $IdentityName --query "name" -o tsv 2>$null
if ($identity) {
    Write-Check "PASS" "User Assigned Identity '$IdentityName' exists"

    # Federated credentials
    $ficList = az identity federated-credential list --resource-group $RgCore --identity-name $IdentityName -o json 2>$null | ConvertFrom-Json
    $ficCount = $ficList.Count
    if ($ficCount -gt 0) {
        Write-Check "PASS" "Federated identity credential(s): $ficCount"
        foreach ($fic in $ficList) {
            Write-Check "PASS" "FIC '$($fic.name)' -> subject: $($fic.subject)"
        }
    } else {
        Write-Check "FAIL" "No federated identity credentials found"
    }
} else {
    Write-Check "FAIL" "User Assigned Identity '$IdentityName' NOT found"
}

# ---------------------------------------------------------------------------
# 6. RBAC Role Assignment (AKS â†’ Network Contributor on subnet)
# ---------------------------------------------------------------------------
Write-Section "6. RBAC Role Assignments"

if ($aksJson) {
    $aksPrincipalId = ($aksJson | ConvertFrom-Json).identity.principalId
    $subnetId = az network vnet subnet show --resource-group $RgCore --vnet-name $VnetName --name "snet-aks-$Environment" --query "id" -o tsv 2>$null
    if ($subnetId -and $aksPrincipalId) {
        $roleAssignment = az role assignment list --scope $subnetId --assignee $aksPrincipalId --query "[?roleDefinitionName=='Network Contributor'].id" -o tsv 2>$null
        if ($roleAssignment) {
            Write-Check "PASS" "AKS identity has 'Network Contributor' on AKS subnet"
        } else {
            Write-Check "FAIL" "AKS identity missing 'Network Contributor' on AKS subnet"
        }
    } else {
        Write-Check "WARN" "Could not verify RBAC (subnet or principal ID not found)"
    }
}

# ---------------------------------------------------------------------------
# 7. Azure Policy Assignments
# ---------------------------------------------------------------------------
Write-Section "7. Azure Policy Assignments"

foreach ($rg in @($RgCore, $RgAks, $RgData)) {
    $rgId = az group show --name $rg --query "id" -o tsv 2>$null
    if (-not $rgId) { continue }

    $assignments = az policy assignment list --scope $rgId --query "[].{name:displayName}" -o json 2>$null | ConvertFrom-Json
    $assignCount = $assignments.Count

    if ($assignCount -gt 0) {
        Write-Check "PASS" "'$rg' has $assignCount policy assignment(s)"

        # Check for deny-public-ip
        $denyPip = $assignments | Where-Object { $_.name -like "*Deny Public*" }
        if ($denyPip) {
            Write-Check "PASS" "'$rg' â†’ Deny Public IP policy assigned"
        } else {
            Write-Check "WARN" "'$rg' â†’ Deny Public IP policy NOT found"
        }

        # Check for allowed locations
        $locations = $assignments | Where-Object { $_.name -like "*location*" }
        if ($locations) {
            Write-Check "PASS" "'$rg' â†’ Allowed Locations policy assigned"
        } else {
            Write-Check "WARN" "'$rg' â†’ Allowed Locations policy NOT found"
        }

        # Check for tag policies
        $tagPolicies = $assignments | Where-Object { $_.name -like "*tag*" }
        if ($tagPolicies.Count -ge $RequiredTags.Count) {
            Write-Check "PASS" "'$rg' â†’ $($tagPolicies.Count) tag enforcement policies"
        } else {
            Write-Check "WARN" "'$rg' â†’ Only $($tagPolicies.Count) tag policies (expected $($RequiredTags.Count))"
        }
    } else {
        Write-Check "FAIL" "'$rg' has NO policy assignments"
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  Environment : $Environment" -ForegroundColor White
Write-Host "  Passed   : $Pass" -ForegroundColor Green
Write-Host "  Failed   : $Fail" -ForegroundColor Red
Write-Host "  Warnings : $Warn" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Cyan

if ($Fail -gt 0) {
    Write-Host ""
    Write-Host "  RESULT: VALIDATION FAILED - $Fail check(s) require attention" -ForegroundColor Red
    exit 1
} elseif ($Warn -gt 0) {
    Write-Host ""
    Write-Host "  RESULT: VALIDATION PASSED WITH WARNINGS" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host ""
    Write-Host "  RESULT: ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
}

