#!/bin/sh

# Configure any extra settings that are not supported neither by the Helm chart or the owncloud/server image.
su www-data -c "php occ config:system:set sharing.remoteShareesSearch --value 'OCA\ScienceMesh\Plugins\ScienceMeshSearchPlugin'"
