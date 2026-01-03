#!/bin/bash

# Set your resource group
RESOURCE_GROUP="rg-vm-backup-poc"

# Get all snapshot names in the resource group
SNAPSHOTS=$(az snapshot list --resource-group $RESOURCE_GROUP --query "[].name" -o tsv)

# Loop through each snapshot
for SNAPSHOT in $SNAPSHOTS; do
    echo "Revoking SAS access for snapshot: $SNAPSHOT"
    az snapshot revoke-access --resource-group $RESOURCE_GROUP --name $SNAPSHOT

    echo "Deleting snapshot: $SNAPSHOT"
    az snapshot delete --resource-group $RESOURCE_GROUP --name $SNAPSHOT
done

echo "All snapshots revoked and deleted in resource group $RESOURCE_GROUP."
