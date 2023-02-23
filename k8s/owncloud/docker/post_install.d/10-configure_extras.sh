#!/bin/sh
# Configures any extra settings that are not supported neither by the Helm chart or the owncloud/server image.

# Read any configExtras into a variable
configExtras=$(php -r 'include("config/configmap.config.php"); echo json_encode($CONFIG);')

# Extract the values of iopUrl and revaSharedSecret from the JSON-encoded configExtras
iopUrl=$(echo "$configExtras" | jq -r '.sciencemesh.iopUrl')
revaSharedSecret=$(echo "$configExtras" | jq -r '.sciencemesh.revaSharedSecret')

# Switch to www-data user and set the config extras to the config db
su www-data -c "php occ config:system:set sharing.remoteShareesSearch --value 'OCA\ScienceMesh\Plugins\ScienceMeshSearchPlugin'"
su www-data -c "php occ config:app:set sciencemesh iopUrl --value $iopUrl"
su www-data -c "php occ config:app:set sciencemesh revaSharedSecret --value $revaSharedSecret"
