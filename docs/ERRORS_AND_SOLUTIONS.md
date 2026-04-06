# SecureFin Platform — Notable Errors & Solutions

A concise reference of significant errors encountered during Module 1 & 2 development, with root causes and fixes.

---

## Module 1 — Terraform Foundation & CI/CD

### 1. AADSTS700016 — Application Not Found

```
AADSTS700016: Application with identifier '***' was not found
```

**Root Cause**: GitHub secret was named `AZURE_CLIENT_ID_PLAN` instead of `AZURE_CLIENT_ID`.  
**Fix**: Renamed GitHub secret to match what the pipeline references.

---

### 2. 403 Forbidden on State Storage

```
Error: Failed to get existing workspaces: storage: service returned error StatusCode=403
```

**Root Cause**: Service principal lacked RBAC role on the storage account.  
**Fix**: Assigned `Storage Blob Data Contributor` to the SP on the state storage account.

---

### 3. 404 on tfstate Container

```
Error: Error creating blob: container "tfstate" does not exist
```

**Root Cause**: The blob container was never created.  
**Fix**: Created `tfstate` container in `tashdidstatebackup68` storage account.

---

### 4. AADSTS700038 — Placeholder Client ID

```
AADSTS700038: The application '00000000-0000-0000-0000-000000000000' is not valid
```

**Root Cause**: GitHub secrets had placeholder `00000000-...` values.  
**Fix**: Switched to **repository variables** (not secrets) with real GUIDs. Values are non-sensitive.

---

### 5. Provider Not Using ARM_* Environment Variables

**Root Cause**: AzureRM provider didn't pick up `ARM_*` env vars because no variable defaults existed.  
**Fix**: Added `subscription_id`, `tenant_id` with real defaults in `variables.tf`. ARM_* takes precedence in CI.

---

### 6. Error Ensuring Resource Providers (404 on Deprecated Namespaces)

```
Error ensuring Resource Providers are registered: Cannot register provider Microsoft.Media
```

**Root Cause**: AzureRM tries to register all providers by default; deprecated namespaces (Microsoft.Media, etc.) return 404.  
**Fix (v3)**: `skip_provider_registration = true`  
**Fix (v4)**: `resource_provider_registrations = "none"` + explicit `resource_providers_to_register` list.

---

### 7. No Pipeline Trigger on Merge

**Root Cause**: Pipeline only had `pull_request` trigger. Merging (push event) didn't trigger anything.  
**Fix**: Added `push` trigger for `[dev, staging, production]` branches.

---

### 8. YAML Multi-Line Expression Parse Error

```
Error: Invalid workflow file: unexpected value 'staging'
```

**Root Cause**: Multi-line `${{ }}` expression in YAML broke parsing.  
**Fix**: Collapsed to single-line ternary expression.

---

### 9. Auto-Approve Not Production-Grade

**Root Cause**: `terraform apply -auto-approve` in a single job — no review step.  
**Fix**: Split into Plan/Apply jobs with GitHub Environment approval gates. Staging/production require reviewer approval.

---

## Module 2 — Security & Compliance

### 10. TFLint — Unused Variable Error

```
Warning: variable "client_id" is declared but not used
```

**Root Cause**: `client_id` variable was declared but removed from provider block during refactoring.  
**Fix**: Removed the unused variable declaration from `variables.tf`.

---

### 11. Policy for_each — Splat Syntax Error

```
Error: Unsupported attribute: This object does not have an attribute named "0"
```

**Root Cause**: Policy outputs used splat syntax (`[*]`) with `for_each`, which produces a map not a list.  
**Fix**: Changed outputs from `azurerm_resource_group_policy_assignment.required_tags[*].id` to `values(azurerm_resource_group_policy_assignment.required_tags)[*].id`.

---

### 12. Policy for_each — Set Type Required

```
Error: Invalid for_each argument: for_each requires a map or set of strings
```

**Root Cause**: `for_each` was given a list of resource group IDs. Terraform requires a map or set.  
**Fix**: Changed `resource_group_ids` variable from list to `map(string)` with named keys (`core`, `aks`, `data`).

---

### 13. VNet 404 — Resource Group Not Found

```
Error: creating Virtual Network: ResourceGroupNotFound: Resource group 'rg-securefin-core-dev' not found
```

**Root Cause**: Race condition — Terraform tried to create VNet before the resource group existed. Outputs weren't wired correctly.  
**Fix**: Used module output references (`module.rg_core.name`) instead of hardcoded names. Terraform resolves the dependency graph automatically.

---

### 14. AKS Quota Exceeded

```
Error: OperationNotAllowed: Subscription quota exceeded for Standard_D2s_v3 in westus2
```

**Root Cause**: Region `westus2` (later `eastus2`) had insufficient vCPU quota for the VM size.  
**Fix**: Switched region to `westus3` which had available quota. Updated all location references.

---

### 15. AKS Outbound Connectivity — loadBalancer vs managedNATGateway

```
Error: Creating AKS: outbound_type "loadBalancer" requires a public IP or NAT gateway
```

**Root Cause**: Free-tier AKS doesn't support `managedNATGateway` outbound type. The `loadBalancer` type requires proper configuration.  
**Fix**: Set `outbound_type = "loadBalancer"` (the default) and let AKS manage its own outbound public IP on the load balancer. This is the only option on free-tier.

---

### 16. AzureRM 4.x Breaking Changes — Renamed Attributes

```
Error: An argument named "enable_auto_scaling" is not expected here. Did you mean "auto_scaling_enabled"?
```

**Root Cause**: AzureRM 4.x renamed several attributes (enable_* → *_enabled pattern).  
**Fix**: Bulk-renamed all affected attributes:
- `enable_auto_scaling` → `auto_scaling_enabled`
- `skip_provider_registration` → `resource_provider_registrations = "none"`
- Removed deprecated `managed` and `enforce` attributes

---

### 17. Resource Provider Registration 404 (AzureRM 4.x)

```
Error: Registering Resource Provider "Microsoft.Network": provider returned HTTP 404
```

**Root Cause**: After switching to `resource_provider_registrations = "none"`, required providers weren't registered.  
**Fix**: Added explicit `resource_providers_to_register` list:
```hcl
resource_providers_to_register = [
  "Microsoft.Network",
  "Microsoft.ContainerService",
  "Microsoft.ManagedIdentity",
  "Microsoft.Authorization",
  "Microsoft.Resources",
  "Microsoft.OperationalInsights",
]
```

---

### 18. ContainerInsights Solution — Missing Tags

```
Error: Policy violation: Resource 'ContainerInsights(law-securefin-dev)' missing required tags
```

**Root Cause**: Azure auto-creates a `ContainerInsights` solution when OMS agent is enabled. This solution inherits no tags, violating the tag policy.  
**Fix**: Pre-created the `ContainerInsights` solution in Terraform with proper tags before the AKS module, so AKS finds it already existing.

---

### 19. Checkov — Free-Tier Unfixable Findings

**Root Cause**: 4 Checkov findings require paid AKS SKUs (Standard/Premium) or enterprise features.  
**Decision**: Accepted as soft-fail. Documented as known limitations:
- API authorized IP ranges (not supported on private + free SKU)
- SLA/uptime (requires Standard SKU)
- Disk encryption (requires Key Vault Premium)
- Subnet service endpoints (not needed for current architecture)

---

### 20. HCL Naming Convention — Inconsistent Resource Names

**Root Cause**: Resources used mixed naming: `this`, `main`, `default`, module-specific names.  
**Fix**: Standardized all HCL resource names to `securefin_<type>` pattern:
- `azurerm_kubernetes_cluster.this` → `azurerm_kubernetes_cluster.securefin_aks`
- `azurerm_virtual_network.main` → `azurerm_virtual_network.securefin_vnet`
- `azurerm_role_assignment.aks_network` → `azurerm_role_assignment.securefin_aks_network_role`

---

### 21. Node.js 20 Deprecation — GitHub Actions

```
Warning: Node.js 20 actions are deprecated. Node.js 24 will be the default June 2, 2026.
```

**Root Cause**: All GitHub Actions were on versions using Node.js 20 runtime.  
**Fix**: Upgraded all actions to Node.js 24 compatible versions:
- checkout v4→v6, setup-terraform v3→v4, azure/login v2→v3
- setup-tflint v4→v6, upload-artifact v4→v6, download-artifact v4→v7
- checkov-action v12 unchanged (Docker-based, not affected)

---

### 22. AKS Manual Resource Group Cleanup Required

**Root Cause**: After failed AKS deployments, orphaned `MC_` resource groups and partially created resources blocked re-deployment with "resource already exists" errors.  
**Fix**: Manually deleted orphaned resource groups via Azure CLI:
```bash
az group delete --name MC_rg-securefin-aks-dev_aks-securefin-dev_westus3 --yes --no-wait
az group delete --name rg-securefin-aks-dev --yes --no-wait
```
Then re-ran `terraform apply` to recreate cleanly.

---

*Last Updated: April 6, 2026 — Covers all errors from Module 1 (commits 0fc14d9–22049b6) and Module 2 (commits ca06dd0–6d15538).*
