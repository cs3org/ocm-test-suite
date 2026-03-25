export class TestOverlay {
    constructor() {
        this.overlay = null;
        this.createOverlay();

        // Import config for platform mapping
        import('../config.js').then(module => {
            this.config = module.config;
        });
    }

    createOverlay() {
        const template = `
            <div class="test-overlay">
                <div class="test-overlay__backdrop"></div>
                <div class="test-overlay__content">
                    <div class="test-overlay__header">
                        <div class="test-overlay__header-content">
                            <div class="test-overlay__badge">Test Recording</div>
                            <h3 class="test-overlay__title"></h3>
                        </div>
                        <div class="test-overlay__actions">
                            <a class="test-overlay__ci-link" target="_blank" title="View in GitHub Actions">
                                <i class="fas fa-external-link-alt"></i>
                                <span>View in GitHub</span>
                            </a>
                            <button class="test-overlay__close" aria-label="Close overlay">
                                <i class="fas fa-times"></i>
                            </button>
                        </div>
                    </div>

                    <div class="test-overlay__body">
                        <div class="test-overlay__main-content">
                            <div class="test-overlay__video-container">
                                <div class="test-overlay__video-wrapper">
                                    <video controls preload="none">
                                        <source type="video/mp4" src="">
                                    </video>
                                    <div class="test-overlay__video-loading">
                                        <div class="spinner"></div>
                                        <span>Loading test recording...</span>
                                    </div>
                                </div>
                                <div class="test-overlay__video-error" role="status" aria-live="polite">
                                    Failed to load video recording
                                </div>
                            </div>

                            <div class="test-overlay__info-panel">
                                <div class="test-overlay__status-card">
                                    <div class="status-icon">
                                        <i class="fas"></i>
                                    </div>
                                    <div class="status-details">
                                        <span class="status-label">Test Status</span>
                                        <span class="status-text"></span>
                                    </div>
                                </div>

                                <div class="test-overlay__actions-card">
                                    <a class="test-overlay__download" download>
                                        <i class="fas fa-download"></i>
                                        <span>Download Recording</span>
                                    </a>
                                    <button class="test-overlay__fullscreen">
                                        <i class="fas fa-expand"></i>
                                        <span>Full Screen</span>
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        const div = document.createElement('div');
        div.innerHTML = template;
        this.overlay = div.firstElementChild;
        document.body.appendChild(this.overlay);

        // Close handlers
        this.overlay.querySelector('.test-overlay__close').addEventListener('click', () => this.hide());
        this.overlay.querySelector('.test-overlay__backdrop').addEventListener('click', () => this.hide());

        // Video handlers
        const video = this.overlay.querySelector('video');
        video.addEventListener('loadstart', () => this.showVideoLoading());
        video.addEventListener('canplay', () => this.hideVideoLoading());
        video.addEventListener('error', () => this.handleVideoError());

        // Fullscreen handler
        const fullscreenBtn = this.overlay.querySelector('.test-overlay__fullscreen');
        fullscreenBtn.addEventListener('click', () => {
            if (video.requestFullscreen) {
                video.requestFullscreen();
            } else if (video.webkitRequestFullscreen) {
                video.webkitRequestFullscreen();
            }
        });
    }

    async checkImageExists(url) {
        try {
            const response = await fetch(url, { method: 'HEAD' });
            return response.ok;
        } catch (error) {
            console.warn('Failed to check thumbnail:', error);
            return false;
        }
    }

    async show(workflowName, status, videoUrl, thumbnailUrl) {
        document.body.classList.add('overlay-active');

        // Format the title
        const formattedTitle = this.formatWorkflowTitle(workflowName);
        this.overlay.querySelector('.test-overlay__title').textContent = formattedTitle;

        this.overlay.querySelector('.test-overlay__ci-link').href =
            `https://github.com/cs3org/ocm-test-suite/actions/workflows/${workflowName}.yml`;

        // Set up video if available
        const video = this.overlay.querySelector('video');
        const source = video.querySelector('source');
        const videoContainer = this.overlay.querySelector('.test-overlay__video-container');
        const downloadLink = this.overlay.querySelector('.test-overlay__download');
        const fullscreenButton = this.overlay.querySelector('.test-overlay__fullscreen');

        this.resetVideoPresentation();

        if (videoUrl) {
            // Check if thumbnail exists before setting it
            if (thumbnailUrl) {
                const thumbnailExists = await this.checkImageExists(thumbnailUrl);
                if (thumbnailExists) {
                    video.poster = thumbnailUrl;
                } else {
                    video.removeAttribute('poster');
                }
            } else {
                video.removeAttribute('poster');
            }

            // Set video source
            source.type = 'video/mp4';
            source.src = videoUrl;
            video.load();

            videoContainer.style.display = 'block';
            this.showVideoLoading();

            // Set up download link
            downloadLink.href = videoUrl;
            downloadLink.style.display = 'flex';
        } else {
            videoContainer.style.display = 'none';
            downloadLink.style.display = 'none';
            fullscreenButton.style.display = 'none';
        }

        // Show status
        const statusIcon = this.overlay.querySelector('.status-icon i');
        const statusText = this.overlay.querySelector('.status-text');
        statusIcon.className = `fas fa-${status.icon}`;
        statusIcon.style.color = status.color;
        statusText.textContent = status.text;
        statusText.style.color = status.color;

        this.overlay.classList.add('active');
    }

    formatWorkflowTitle(workflowName) {
        // Extract prefix and platforms from workflow name
        const parts = workflowName.split('-');
        const prefix = parts[0];

        // Get category title from prefix
        let categoryTitle = '';
        switch (prefix) {
            case 'login':
                categoryTitle = 'Authentication Test';
                break;
            case 'share':
                categoryTitle = parts[1] === 'link' ? 'Public Link Sharing Test' : 'Direct User Sharing Test';
                break;
            case 'invite':
                categoryTitle = 'ScienceMesh Federation Test';
                break;
            case 'code':
                categoryTitle = parts[1] === 'flow' ? 'Code-Flow Remote Access Test' : 'Test';
                break;
            default:
                categoryTitle = 'Test';
        }

        // Get platform mapping from config
        const platformMap = this.config?.platformMap || {};
        const reverseMap = Object.entries(platformMap).reduce((acc, [fullName, shortName]) => {
            acc[shortName] = fullName;
            return acc;
        }, {});

        // Helper function to get full platform name
        const getFullPlatformName = (shortPlatform) => {
            // Try to find the platform in the reverse map
            for (const [short, full] of Object.entries(reverseMap)) {
                if (shortPlatform.startsWith(short)) {
                    return full;
                }
            }
            return shortPlatform; // Fallback to original if not found
        };

        // For authentication tests, there's only one platform
        if (prefix === 'login') {
            const platform = parts.slice(1).join('-');
            const fullPlatform = getFullPlatformName(platform);
            return `${categoryTitle}: ${fullPlatform}`;
        }

        // For ScienceMesh tests, handle special format
        if (prefix === 'invite') {
            // Remove 'invite' and 'link' from parts
            const platformParts = parts.slice(2);

            // Special handling when the second element is 'sm', indicating a ScienceMesh naming convention
            if (platformParts.length >= 2 && platformParts[1] === 'sm') {
                if (platformParts.length >= 5) {
                    // e.g. 'nc', 'sm', 'v27', 'ocis', 'v5' should become 'nc-sm-v27' and 'ocis-v5'
                    const sourcePlatform = platformParts.slice(0, 3).join('-');
                    const targetPlatform = platformParts.slice(3).join('-');

                    const fullSourcePlatform = getFullPlatformName(sourcePlatform);
                    const fullTargetPlatform = getFullPlatformName(targetPlatform);

                    return `${categoryTitle}: ${fullSourcePlatform} ➜ ${fullTargetPlatform}`;
                } else if (platformParts.length === 4) {
                    // e.g. 'oc', 'sm', 'ocis', 'v5' should become 'oc-sm' and 'ocis-v5'
                    const sourcePlatform = platformParts.slice(0, 2).join('-');
                    const targetPlatform = platformParts.slice(2).join('-');

                    const fullSourcePlatform = getFullPlatformName(sourcePlatform);
                    const fullTargetPlatform = getFullPlatformName(targetPlatform);

                    return `${categoryTitle}: ${fullSourcePlatform} ➜ ${fullTargetPlatform}`;
                }
            }
            // Fallback: default split using midpoint
            const midPoint = Math.floor(platformParts.length / 2);
            const sourcePlatform = platformParts.slice(0, midPoint).join('-');
            const targetPlatform = platformParts.slice(midPoint).join('-');

            const fullSourcePlatform = getFullPlatformName(sourcePlatform);
            const fullTargetPlatform = getFullPlatformName(targetPlatform);

            return `${categoryTitle}: ${fullSourcePlatform} ➜ ${fullTargetPlatform}`;
        }

        // For other tests (share-link, share-with, code-flow, wayf)
        const skipCount = (prefix === 'share' || prefix === 'code') ? 2 : 1;
        const platformParts = parts.slice(skipCount);
        const midPoint = Math.floor(platformParts.length / 2);
        const sourcePlatform = platformParts.slice(0, midPoint).join('-');
        const targetPlatform = platformParts.slice(midPoint).join('-');

        // Convert to full platform names
        const fullSourcePlatform = getFullPlatformName(sourcePlatform);
        const fullTargetPlatform = getFullPlatformName(targetPlatform);

        return `${categoryTitle}: ${fullSourcePlatform} ➜ ${fullTargetPlatform}`;
    }

    hide() {
        document.body.classList.remove('overlay-active');
        this.overlay.classList.remove('active');
        this.hideVideoLoading();
        const video = this.overlay.querySelector('video');
        if (video) {
            video.pause();
            video.currentTime = 0;
            video.removeAttribute('poster');
            const source = video.querySelector('source');
            if (source) {
                source.removeAttribute('src');
            }
            video.load();
        }
    }

    showVideoLoading() {
        const loadingEl = this.overlay.querySelector('.test-overlay__video-loading');
        if (loadingEl) {
            loadingEl.style.display = 'flex';
        }
    }

    hideVideoLoading() {
        const loadingEl = this.overlay.querySelector('.test-overlay__video-loading');
        if (loadingEl) {
            loadingEl.style.display = 'none';
        }
    }

    handleVideoError() {
        const video = this.overlay.querySelector('video');
        const videoWrapper = this.overlay.querySelector('.test-overlay__video-wrapper');
        const videoError = this.overlay.querySelector('.test-overlay__video-error');

        this.hideVideoLoading();

        if (video) {
            video.pause();
        }

        if (videoWrapper) {
            videoWrapper.style.display = 'none';
        }

        if (videoError) {
            videoError.style.display = 'flex';
        }

        this.overlay.querySelector('.test-overlay__download').style.display = 'none';
        this.overlay.querySelector('.test-overlay__fullscreen').style.display = 'none';
    }

    resetVideoPresentation() {
        const videoContainer = this.overlay.querySelector('.test-overlay__video-container');
        const videoWrapper = this.overlay.querySelector('.test-overlay__video-wrapper');
        const videoError = this.overlay.querySelector('.test-overlay__video-error');
        const downloadLink = this.overlay.querySelector('.test-overlay__download');
        const fullscreenButton = this.overlay.querySelector('.test-overlay__fullscreen');

        if (videoContainer) {
            videoContainer.style.display = 'block';
        }

        if (videoWrapper) {
            videoWrapper.style.display = 'block';
        }

        if (videoError) {
            videoError.style.display = 'none';
        }

        if (downloadLink) {
            downloadLink.style.display = 'flex';
        }

        if (fullscreenButton) {
            fullscreenButton.style.display = 'flex';
        }

        this.hideVideoLoading();
    }
}