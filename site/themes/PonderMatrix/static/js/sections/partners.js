export function initPartnersTabSwitching() {
    const tabs = document.querySelectorAll('.partners-tabs .tab');
    const collaboratorsGrid = document.getElementById('collaboratorsGrid');
    const sponsorsGrid = document.getElementById('sponsorsGrid');
    const container = document.querySelector('.partners-container');

    if (!tabs.length || !collaboratorsGrid || !sponsorsGrid || !container) return;

    // Adjust container height based on active grid
    function updateContainerHeight(activeTab) {
        if (activeTab === 'sponsors') {
            container.style.minHeight = '950px';
        } else {
            container.style.minHeight = '600px';
        }
    }

    tabs.forEach(tab => {
        tab.addEventListener('click', function () {
            // Remove active class from all tabs
            tabs.forEach(t => t.classList.remove('active'));
            // Add active class to clicked tab
            this.classList.add('active');

            // Add switching class for fade effect
            collaboratorsGrid.classList.add('switching');
            sponsorsGrid.classList.add('switching');

            // Switch grids after fade out
            setTimeout(() => {
                if (this.dataset.tab === 'collaborators') {
                    collaboratorsGrid.classList.remove('hidden');
                    sponsorsGrid.classList.add('hidden');
                    updateContainerHeight('collaborators');
                } else {
                    collaboratorsGrid.classList.add('hidden');
                    sponsorsGrid.classList.remove('hidden');
                    updateContainerHeight('sponsors');
                }

                // Remove switching class for fade in
                setTimeout(() => {
                    collaboratorsGrid.classList.remove('switching');
                    sponsorsGrid.classList.remove('switching');
                }, 50);
            }, 300);
        });
    });
}
