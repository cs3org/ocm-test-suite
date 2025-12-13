export const config = {
    manifestUrl: './artifacts/manifest.json',
    workflowStatusUrl: './artifacts/workflow-status.json',
    thumbnailExtension: 'avif',
    videoExtension: 'mp4',
    categories: [
        {
            id: 'auth-tests',
            title: 'Authentication Tests',
            icon: 'fingerprint',
            platforms: [
                'Nextcloud v27.1.11',
                'Nextcloud v28.0.14',
                'oCIS v5.0.9',
                'OcmStub v1.0.0',
                'ownCloud v10.15.0',
                'Seafile v11.0.13'
            ],
            workflowPrefix: 'login-'
        },
        {
            id: 'share-link-tests',
            title: 'Public Link Sharing Tests',
            icon: 'link',
            sources: ['Nextcloud v27.1.11', 'Nextcloud v28.0.14', 'ownCloud v10.15.0'],
            targets: ['Nextcloud v27.1.11', 'Nextcloud v28.0.14', 'ownCloud v10.15.0'],
            workflowPrefix: 'share-link-'
        },
        {
            id: 'share-with-tests',
            title: 'Direct User Sharing Tests',
            icon: 'user-friends',
            sources: ['Nextcloud v27.1.11', 'Nextcloud v28.0.14', 'OcmStub v1.0.0', 'ownCloud v10.15.0', 'Seafile v11.0.13'],
            targets: ['Nextcloud v27.1.11', 'Nextcloud v28.0.14', 'OcmStub v1.0.0', 'ownCloud v10.15.0', 'Seafile v11.0.13'],
            workflowPrefix: 'share-with-'
        },
        {
            id: 'sciencemesh-tests',
            title: 'ScienceMesh Federation Tests',
            icon: 'network-wired',
            sources: ['Nextcloud v27.1.11 (ScienceMesh)', 'oCIS v5.0.9', 'ownCloud v10.15.0 (ScienceMesh)'],
            targets: ['Nextcloud v27.1.11 (ScienceMesh)', 'oCIS v5.0.9', 'ownCloud v10.15.0 (ScienceMesh)'],
            workflowPrefix: 'invite-link-'
        },
        {
            id: 'wayf-tests',
            title: 'WAYF Directory Service Tests',
            icon: 'address-book',
            sources: ['Nextcloud v33', 'CERNBox v2'],
            targets: ['Nextcloud v33', 'CERNBox v2'],
            workflowPrefix: 'wayf-'
        }
    ],
    platformMap: {
        'Nextcloud v27.1.11': 'nc-v27',
        'Nextcloud v28.0.14': 'nc-v28',
        'Nextcloud v33': 'nc-v33',
        'CERNBox v2': 'crnbx-v2',
        'oCIS v5.0.9': 'ocis-v5',
        'OcmStub v1.0.0': 'os-v1',
        'ownCloud v10.15.0': 'oc-v10',
        'Seafile v11.0.13': 'sf-v11',
        'Nextcloud v27.1.11 (ScienceMesh)': 'nc-sm-v27',
        'ownCloud v10.15.0 (ScienceMesh)': 'oc-sm-v10'
    }
};