/**
 * PIM Activation - API Client
 * Handles all HTTP communication with the backend.
 * Authentication is cookie-based (pim_session) — no token management needed.
 */

class ApiClient {
    constructor() {
        this.baseUrl = window.location.origin;
    }

    /**
     * Generic fetch with error handling
     */
    async fetch(endpoint, options = {}) {
        const url = `${this.baseUrl}${endpoint}`;
        const silent = options.silent;
        delete options.silent;
        const headers = {
            'Content-Type': 'application/json',
            ...options.headers
        };

        try {
            const response = await fetch(url, {
                ...options,
                headers,
                credentials: 'same-origin'
            });

            const data = await response.json();

            if (response.status === 401) {
                if (!silent) {
                    window.dispatchEvent(new CustomEvent('auth:expired'));
                }
                throw new Error(data?.error || 'Session expired. Please log in again.');
            }

            if (!response.ok) {
                throw new Error(data?.message || data?.error || `HTTP ${response.status}`);
            }

            return data;
        } catch (error) {
            console.error(`API Error: ${endpoint}`, error);
            throw error;
        }
    }

    get(endpoint) {
        return this.fetch(endpoint, { method: 'GET' });
    }

    post(endpoint, data) {
        return this.fetch(endpoint, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    }

    // Role endpoints
    async getEligibleRoles() { return this.get('/api/roles/eligible'); }
    async getActiveRoles()   { return this.get('/api/roles/active'); }

    async activateRole(roleId, roleType, options = {}) {
        return this.silentPost('/api/roles/activate', {
            roleId, roleType,
            directoryScopeId: options.directoryScopeId || '/',
            justification: options.justification,
            ticketNumber: options.ticketNumber,
            durationMinutes: options.durationMinutes || 60
        });
    }

    async deactivateRole(roleId, roleType = 'User', options = {}) {
        return this.silentPost('/api/roles/deactivate', {
            roleId, roleType,
            directoryScopeId: options.directoryScopeId || '/'
        });
    }

    async getRolePolicies(roleId) { return this.get(`/api/roles/policies/${roleId}`); }

    // Silent fetch (won't trigger logout on 401)
    silentGet(endpoint) {
        return this.fetch(endpoint, { method: 'GET', silent: true });
    }

    silentPost(endpoint, data) {
        return this.fetch(endpoint, { method: 'POST', body: JSON.stringify(data), silent: true });
    }

    // Config endpoints
    async getFeatureConfig() { return this.silentGet('/api/config/features'); }
    async getThemeConfig()   { return this.silentGet('/api/config/theme'); }

    // User preferences (silent — don't logout on failure)
    async getUserPreferences()              { return this.silentGet('/api/user/preferences'); }
    async updateUserPreferences(preferences) { return this.silentPost('/api/user/preferences', preferences); }

    // Audit history from Entra logs (silent — non-critical)
    async getAuditHistory() { return this.silentGet('/api/history/audits'); }
}

// Global API client instance
window.apiClient = new ApiClient();
