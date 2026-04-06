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
 * Show a progress overlay for batch operations (activate/deactivate)
 * @param {string} title - e.g. "Activating roles"
 * @param {number} total - total number of items
 */
function showProgress(title, total) {
    hideProgress();
    const overlay = document.createElement('div');
    overlay.id = 'progress-overlay';
    overlay.className = 'progress-overlay';
    overlay.innerHTML = `
        <div class="progress-card">
            <div class="progress-title">${escapeHtml(title)}</div>
            <div class="progress-role" id="progress-role">&nbsp;</div>
            <div class="progress-warning hidden" id="progress-warning"></div>
            <div class="progress-track"><div class="progress-fill" id="progress-fill"></div></div>
            <div class="progress-count" id="progress-count">0 / ${total}</div>
        </div>`;
    document.body.appendChild(overlay);
}

/**
 * Update the progress overlay
 * @param {number} current - items completed so far
 * @param {number} total - total items
 * @param {string} roleName - name of the role currently being processed
 * @param {string} [warning] - optional warning message (shown in yellow)
 */
function updateProgress(current, total, roleName, warning) {
    const fill = document.getElementById('progress-fill');
    const count = document.getElementById('progress-count');
    const role = document.getElementById('progress-role');
    const warn = document.getElementById('progress-warning');
    if (fill) fill.style.width = `${Math.round((current / total) * 100)}%`;
    if (count) count.textContent = `${current} / ${total}`;
    if (role) role.textContent = roleName || '';
    if (warn) {
        if (warning) {
            warn.textContent = warning;
            warn.classList.remove('hidden');
        } else {
            warn.textContent = '';
            warn.classList.add('hidden');
        }
    }
}

/** Remove the progress overlay */
function hideProgress() {
    document.getElementById('progress-overlay')?.remove();
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
            // Load theme immediately (doesn't need auth)
            await this.loadTheme();

            // Check authentication
            const isAuthenticated = await window.authManager.checkAuthentication();

            if (!isAuthenticated) {
                return;
            }

            // Load feature config
            await this.loadFeatureConfig();

            // Initialize keyboard shortcuts
            this.initKeyboardShortcuts();

            // Load initial role data
            await window.roleManager.loadRoles();

            // Load saved profiles
            await window.profileManager.loadProfiles();

            this.initialized = true;
            console.log('PIM Application initialized');
        } catch (error) {
            console.error('Failed to initialize application:', error);
            showToast('Application initialization failed', 'error');
        }
    }

    async loadTheme() {
        try {
            const themeConfig = await window.apiClient.getThemeConfig();
            if (themeConfig.success) {
                this.theme = themeConfig.theme;
                this.applyTheme();
            }
        } catch (error) {
            console.warn('Could not load theme:', error);
        }
    }

    async loadFeatureConfig() {
        try {
            const featureConfig = await window.apiClient.getFeatureConfig();
            if (featureConfig.success) {
                this.config = featureConfig.features;
            }
        } catch (error) {
            console.warn('Could not load feature config:', error);
        }
    }

    applyTheme() {
        if (!this.theme) return;

        const root = document.documentElement;
        if (this.theme.primaryColor) root.style.setProperty('--primary-color', this.theme.primaryColor);
        if (this.theme.secondaryColor) root.style.setProperty('--secondary-color', this.theme.secondaryColor);
        if (this.theme.dangerColor) root.style.setProperty('--danger-color', this.theme.dangerColor);
        if (this.theme.warningColor) root.style.setProperty('--warning-color', this.theme.warningColor);
        if (this.theme.successColor) root.style.setProperty('--success-color', this.theme.successColor);
        if (this.theme.fontFamily) root.style.setProperty('--font-family', this.theme.fontFamily);
        if (this.theme.sectionHeaderColor) root.style.setProperty('--section-header-color', this.theme.sectionHeaderColor);
        if (this.theme.entraColor) root.style.setProperty('--entra-color', this.theme.entraColor);
        if (this.theme.groupColor) root.style.setProperty('--group-color', this.theme.groupColor);
        if (this.theme.azureColor) root.style.setProperty('--azure-color', this.theme.azureColor);

        // Show copyright in both footers if configured
        if (this.theme.copyright) {
            for (const id of ['app-footer', 'login-footer']) {
                const el = document.getElementById(id);
                if (el) {
                    el.textContent = this.theme.copyright;
                    el.classList.remove('hidden');
                }
            }
        }
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
