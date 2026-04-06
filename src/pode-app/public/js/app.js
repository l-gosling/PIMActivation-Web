/**
 * PIM Activation - Main Application
 */

/**
 * Utility: Escape HTML to prevent XSS
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Show/hide loading indicator
 */
function showLoading(visible) {
    const indicator = document.getElementById('loading-indicator');
    if (indicator) {
        if (visible) {
            indicator.classList.remove('hidden');
        } else {
            indicator.classList.add('hidden');
        }
    }
}

/**
 * Show toast notification
 */
function showToast(message, type = 'info', duration = 5000) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.style.whiteSpace = 'pre-line';
    toast.textContent = message;

    container.appendChild(toast);

    setTimeout(() => {
        toast.style.animation = 'fadeOut 0.3s ease-in-out';
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

/**
 * Show error toast with details and copy button, stays longer
 */
function showErrorToast(title, details) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = 'toast error toast-error-detail';

    const titleEl = document.createElement('div');
    titleEl.className = 'toast-error-title';
    titleEl.textContent = title;
    toast.appendChild(titleEl);

    const detailsEl = document.createElement('pre');
    detailsEl.className = 'toast-error-details';
    detailsEl.textContent = details;
    toast.appendChild(detailsEl);

    const actions = document.createElement('div');
    actions.className = 'toast-error-actions';

    const copyBtn = document.createElement('button');
    copyBtn.className = 'toast-copy-btn';
    copyBtn.textContent = 'Copy';
    copyBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        navigator.clipboard.writeText(`${title}\n${details}`).then(() => {
            copyBtn.textContent = 'Copied!';
            setTimeout(() => { copyBtn.textContent = 'Copy'; }, 1500);
        });
    });
    actions.appendChild(copyBtn);

    const closeBtn = document.createElement('button');
    closeBtn.className = 'toast-close-btn';
    closeBtn.textContent = 'Dismiss';
    closeBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toast.remove();
    });
    actions.appendChild(closeBtn);

    toast.appendChild(actions);
    container.appendChild(toast);

    // Auto-remove after 30 seconds
    setTimeout(() => {
        if (toast.parentNode) {
            toast.style.animation = 'fadeOut 0.3s ease-in-out';
            setTimeout(() => toast.remove(), 300);
        }
    }, 30000);
}

/**
 * Apply theme preference (auto, light, or dark)
 */
function applyThemePreference(theme) {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)');

    if (theme === 'dark' || (theme === 'auto' && prefersDark.matches)) {
        document.body.classList.add('dark-theme');
    } else {
        document.body.classList.remove('dark-theme');
    }

    localStorage.setItem('pim-theme', theme);
}

// Apply saved theme immediately to avoid flash
(function() {
    const saved = localStorage.getItem('pim-theme') || 'auto';
    applyThemePreference(saved);

    // Listen for OS theme changes when in auto mode
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        const current = localStorage.getItem('pim-theme') || 'auto';
        if (current === 'auto') {
            applyThemePreference('auto');
        }
    });
})();

/**
 * Main application initialization
 */
class PIMApplication {
    constructor() {
        this.config = null;
        this.theme = null;
        this.initialized = false;
    }

    async initialize() {
        try {
            // Check authentication first
            const isAuthenticated = await window.authManager.checkAuthentication();

            if (!isAuthenticated) {
                return;
            }

            // Load configuration
            await this.loadConfiguration();

            // Initialize keyboard shortcuts
            this.initKeyboardShortcuts();

            // Load initial role data
            await window.roleManager.loadRoles();

            this.initialized = true;
            console.log('PIM Application initialized');
        } catch (error) {
            console.error('Failed to initialize application:', error);
            showToast('Application initialization failed', 'error');
        }
    }

    async loadConfiguration() {
        try {
            const [featureConfig, themeConfig] = await Promise.all([
                window.apiClient.getFeatureConfig(),
                window.apiClient.getThemeConfig()
            ]);

            if (featureConfig.success) {
                this.config = featureConfig.features;
            }

            if (themeConfig.success) {
                this.theme = themeConfig.theme;
                this.applyTheme();
            }
        } catch (error) {
            console.warn('Could not load configuration:', error);
        }
    }

    applyTheme() {
        if (!this.theme) return;

        const root = document.documentElement;
        root.style.setProperty('--primary-color', this.theme.primaryColor);
        root.style.setProperty('--secondary-color', this.theme.secondaryColor);
        root.style.setProperty('--danger-color', this.theme.dangerColor);
        root.style.setProperty('--warning-color', this.theme.warningColor);
        root.style.setProperty('--success-color', this.theme.successColor);
    }

    initKeyboardShortcuts() {
        document.addEventListener('keydown', (e) => {
            // Ctrl+R or Cmd+R: Refresh roles
            if ((e.ctrlKey || e.metaKey) && e.key === 'r') {
                e.preventDefault();
                window.roleManager.loadRoles();
            }

            // Escape: Close dialogs
            if (e.key === 'Escape') {
                const activationModal = document.getElementById('activation-modal');
                const prefsModal = document.getElementById('preferences-modal');

                if (activationModal && !activationModal.classList.contains('hidden')) {
                    window.activationManager.closeDialog();
                }

                if (prefsModal && !prefsModal.classList.contains('hidden')) {
                    window.activationManager.closePreferencesDialog();
                }
            }

            // Ctrl+A: Select all roles
            if ((e.ctrlKey || e.metaKey) && e.key === 'a' && e.target === document.body) {
                e.preventDefault();
                window.roleManager.selectAll();
            }
        });
    }
}

/**
 * Application startup
 */
document.addEventListener('DOMContentLoaded', async () => {
    const app = new PIMApplication();
    await app.initialize();

    // Handle window focus/blur for session management
    window.addEventListener('focus', () => {
        if (app.initialized && window.authManager.isAuthenticated) {
            // Optionally refresh roles when window regains focus
            // window.roleManager.loadRoles();
        }
    });
});

// Handle visibility changes for session refresh
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        console.log('Application hidden');
    } else {
        console.log('Application visible');
        // Optionally refresh data when tab becomes visible again
    }
});
