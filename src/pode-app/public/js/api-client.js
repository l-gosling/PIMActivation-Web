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

            if (response.status === 401) {
                window.dispatchEvent(new CustomEvent('auth:expired'));
                throw new Error('Session expired. Please log in again.');
            }

            const data = await response.json();

            if (!response.ok) {
                throw new Error(data.message || data.error || `HTTP ${response.status}`);
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
        return this.post('/api/roles/activate', {
            roleId, roleType,
            justification: options.justification,
            ticketNumber: options.ticketNumber,
            durationMinutes: options.durationMinutes || 60
        });
    }

    async deactivateRole(roleId, roleType = 'User') {
        return this.post('/api/roles/deactivate', { roleId, roleType });
    }

    async getRolePolicies(roleId) { return this.get(`/api/roles/policies/${roleId}`); }

    // Config endpoints
    async getFeatureConfig() { return this.get('/api/config/features'); }
    async getThemeConfig()   { return this.get('/api/config/theme'); }

    // User preferences
    async getUserPreferences()              { return this.get('/api/user/preferences'); }
    async updateUserPreferences(preferences) { return this.post('/api/user/preferences', preferences); }
}

// Global API client instance
window.apiClient = new ApiClient();
