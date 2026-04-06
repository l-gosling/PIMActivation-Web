/**
 * PIM Activation - Authentication Management
 * Uses Entra ID OAuth 2.0 Authorization Code flow
 */

class AuthManager {
    constructor() {
        this.user = null;
        this.isAuthenticated = false;
        this.initEventListeners();
        this.checkForOAuthError();
    }

    initEventListeners() {
        window.addEventListener('auth:expired', () => this.handleSessionExpired());

        const loginBtn = document.getElementById('login-button');
        if (loginBtn) {
            loginBtn.addEventListener('click', () => this.handleLogin());
        }

        const logoutBtn = document.getElementById('logout-button');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', () => this.handleLogout());
        }

        const userBtn = document.getElementById('user-button');
        const userDropdown = document.getElementById('user-dropdown');
        if (userBtn && userDropdown) {
            userBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                userDropdown.classList.toggle('hidden');
            });

            document.addEventListener('click', (e) => {
                if (!e.target.closest('.user-menu')) {
                    userDropdown.classList.add('hidden');
                }
            });
        }
    }

    /**
     * Check URL for OAuth error parameter (set by backend on callback failure)
     */
    checkForOAuthError() {
        const params = new URLSearchParams(window.location.search);
        const error = params.get('error');
        if (error) {
            showToast(`Authentication error: ${error}`, 'error');
            // Clean up URL
            window.history.replaceState({}, '', '/');
        }
    }

    /**
     * Redirect to backend login endpoint which redirects to Entra ID
     */
    handleLogin() {
        window.location.href = '/api/auth/login';
    }

    async handleLogout() {
        try {
            showLoading(true);
            await window.apiClient.post('/api/auth/logout', {});

            this.user = null;
            this.isAuthenticated = false;
            this.updateUI();
            this.showLoginUI();

            showToast('You have been logged out', 'success');
        } catch (error) {
            showToast(`Logout error: ${error.message}`, 'error');
        } finally {
            showLoading(false);
        }
    }

    handleSessionExpired() {
        this.user = null;
        this.isAuthenticated = false;
        this.updateUI();
        this.showLoginUI();
        showToast('Your session has expired. Please log in again.', 'warning');
    }

    updateUI() {
        const userName = document.getElementById('user-name');
        if (userName && this.user) {
            userName.textContent = this.user.name || this.user.email;
        }
    }

    showLoginUI() {
        const loginContainer = document.getElementById('login-container');
        const appContainer = document.getElementById('app-container');

        if (loginContainer && appContainer) {
            loginContainer.classList.remove('hidden');
            appContainer.classList.add('hidden');
        }
    }

    showAppUI() {
        const loginContainer = document.getElementById('login-container');
        const appContainer = document.getElementById('app-container');

        if (loginContainer && appContainer) {
            loginContainer.classList.add('hidden');
            appContainer.classList.remove('hidden');
        }
    }

    /**
     * Check if user has an active session (cookie-based)
     */
    async checkAuthentication() {
        try {
            const response = await window.apiClient.get('/api/auth/me');
            if (response.success && response.user) {
                this.user = response.user;
                this.isAuthenticated = true;
                this.updateUI();
                this.showAppUI();
                return true;
            }
        } catch (error) {
            // Not authenticated — redirect to Entra ID login
        }

        // Auto-redirect to login unless we just came back with an error
        const params = new URLSearchParams(window.location.search);
        if (params.has('error')) {
            this.showLoginUI();
        } else {
            window.location.href = '/api/auth/login';
        }
        return false;
    }
}

// Global auth manager instance
window.authManager = new AuthManager();
