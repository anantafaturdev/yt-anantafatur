#!/bin/bash
set -euo pipefail

# ==================================================
# Azure Runtime & Resource Usage Inventory Script
#
# Collects:
# - VM power state
# - Managed Disk usage (attached / detached)
# - Public IP usage (associated / unassociated)
#
# Outputs:
# - Detailed CSVs per resource type
# ==================================================

# =============================
# PRE-CHECKS
# =============================

az account show >/dev/null

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Active subscription  : $SUBSCRIPTION_ID"
echo "Starting inventory collection..."
echo ""

# =============================
# OUTPUT FILES
# =============================

VM_OUT="azure_vm_power_state.csv"
DISK_ORPHAN_OUT="azure_orphan_disks.csv"
DISK_USED_OUT="azure_used_disks.csv"
PIP_ORPHAN_OUT="azure_orphan_public_ips.csv"
PIP_USED_OUT="azure_used_public_ips.csv"

# =============================
# VM POWER STATE
# =============================

echo "Collecting VM power state..."

az vm list -d --query '
[].{
  resourceType: "VirtualMachine",
  subscriptionId: subscriptionId,
  resourceGroup: resourceGroup,
  name: name,
  location: location,
  size: hardwareProfile.vmSize,
  state: powerState,
  relatedResource: "N/A",
  resourceId: id
}' -o json \
| jq -r '
  (["resourceType","subscriptionId","resourceGroup","name","location","size","state","relatedResource","resourceId"]),
  (.[] |
    [
      .resourceType,
      .subscriptionId,
      .resourceGroup,
      .name,
      .location,
      .size,
      (.state // "unknown"),
      .relatedResource,
      .resourceId
    ]
  )
  | @csv
' > "$VM_OUT"

echo "VM power state completed"
echo ""

# =============================
# ORPHAN MANAGED DISKS
# =============================

echo "Collecting orphan managed disks..."

az graph query -q "
Resources
| where type == 'microsoft.compute/disks'
| where isnull(managedBy)
| project
    resourceType = 'ManagedDisk',
    subscriptionId,
    resourceGroup,
    name,
    location,
    size = tostring(properties.diskSizeGB),
    state = 'detached',
    relatedResource = 'N/A',
    resourceId = id
" -o json \
| jq -r '
  (["resourceType","subscriptionId","resourceGroup","name","location","size","state","relatedResource","resourceId"]),
  (.data[] |
    [
      .resourceType,
      .subscriptionId,
      .resourceGroup,
      .name,
      .location,
      .size,
      .state,
      .relatedResource,
      .resourceId
    ]
  )
  | @csv
' > "$DISK_ORPHAN_OUT"

echo "Orphan disks completed"
echo ""

# =============================
# USED MANAGED DISKS
# =============================

echo "Collecting used managed disks..."

az graph query -q "
Resources
| where type == 'microsoft.compute/disks'
| where isnotnull(managedBy)
| project
    resourceType = 'ManagedDisk',
    subscriptionId,
    resourceGroup,
    name,
    location,
    size = tostring(properties.diskSizeGB),
    state = 'attached',
    relatedResource = managedBy,
    resourceId = id
" -o json \
| jq -r '
  (["resourceType","subscriptionId","resourceGroup","name","location","size","state","relatedResource","resourceId"]),
  (.data[] |
    [
      .resourceType,
      .subscriptionId,
      .resourceGroup,
      .name,
      .location,
      .size,
      .state,
      .relatedResource,
      .resourceId
    ]
  )
  | @csv
' > "$DISK_USED_OUT"

echo "Used disks completed"
echo ""

# =============================
# ORPHAN PUBLIC IPs
# =============================

echo "Collecting orphan public IPs..."

az network public-ip list --query '
[?ipConfiguration==null].{
  resourceType: "PublicIP",
  subscriptionId: subscriptionId,
  resourceGroup: resourceGroup,
  name: name,
  location: location,
  size: sku.name,
  state: "unassociated",
  relatedResource: "N/A",
  resourceId: id
}' -o json \
| jq -r '
  (["resourceType","subscriptionId","resourceGroup","name","location","size","state","relatedResource","resourceId"]),
  (.[] |
    [
      .resourceType,
      .subscriptionId,
      .resourceGroup,
      .name,
      .location,
      .size,
      .state,
      .relatedResource,
      .resourceId
    ]
  )
  | @csv
' > "$PIP_ORPHAN_OUT"

echo "Orphan public IPs completed"
echo ""

# =============================
# USED PUBLIC IPs
# =============================

echo "Collecting used public IPs..."

az network public-ip list --query '
[?ipConfiguration!=null].{
  resourceType: "PublicIP",
  subscriptionId: subscriptionId,
  resourceGroup: resourceGroup,
  name: name,
  location: location,
  size: sku.name,
  state: "associated",
  relatedResource: ipConfiguration.id,
  resourceId: id
}' -o json \
| jq -r '
  (["resourceType","subscriptionId","resourceGroup","name","location","size","state","relatedResource","resourceId"]),
  (.[] |
    [
      .resourceType,
      .subscriptionId,
      .resourceGroup,
      .name,
      .location,
      .size,
      .state,
      .relatedResource,
      .resourceId
    ]
  )
  | @csv
' > "$PIP_USED_OUT"

echo "Used public IPs completed"
echo ""

# =============================
# SUMMARY
# =============================

echo "======================================"
echo "INVENTORY COLLECTION SUMMARY"
echo "======================================"
echo "VM power state        : $VM_OUT"
echo "Orphan disks          : $DISK_ORPHAN_OUT"
echo "Used disks            : $DISK_USED_OUT"
echo "Orphan public IPs     : $PIP_ORPHAN_OUT"
echo "Used public IPs       : $PIP_USED_OUT"
echo ""
echo "Inventory completed successfully"
