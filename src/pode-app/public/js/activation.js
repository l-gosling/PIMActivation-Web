/**
 * PIM Activation - Role Activation Dialog
 */

class ActivationManager {
    constructor() {
        this.currentRole = null;
        this.rolePolicy = null;
        this.onSuccess = null;
        this.initEventListeners();
    }

    initEventListeners() {
        const modal = document.getElementById('activation-modal');
        const closeBtn = modal?.querySelector('.close-button');
        const cancelBtn = document.getElementById('modal-cancel-button');
        const activateBtn = document.getElementById('modal-activate-button');

        closeBtn?.addEventListener('click', () => this.closeDialog());
        cancelBtn?.addEventListener('click', () => this.closeDialog());
        activateBtn?.addEventListener('click', () => this.handleActivate());

        // Close on overlay click
        modal?.addEventListener('click', (e) => {
            if (e.target === modal) {
                this.closeDialog();
            }
        });

        // Preferences modal
        const prefsCloseBtn = document.getElementById('preferences-modal')?.querySelector('.close-button');
        const prefsCancelBtn = document.getElementById('preferences-cancel-button');
        const prefsSaveBtn = document.getElementById('preferences-save-button');

        prefsCloseBtn?.addEventListener('click', () => this.closePreferencesDialog());
        prefsCancelBtn?.addEventListener('click', () => this.closePreferencesDialog());
        prefsSaveBtn?.addEventListener('click', () => this.handleSavePreferences());

        document.getElementById('preferences-button')?.addEventListener('click', () => {
            this.showPreferencesDialog();
        });
    }

    async showActivationDialog(role, onSuccess = null) {
        this.currentRole = role;
        this.onSuccess = onSuccess;

        // Update modal with role info
        const roleInfo = document.getElementById('modal-role-info');
        if (roleInfo) {
            roleInfo.innerHTML = `
                <div class="role-name">${escapeHtml(role.name)}</div>
                <div class="role-scope">${escapeHtml(role.scope || 'N/A')}</div>
            `;
        }

        // Load role policy
        try {
            const policyResponse = await window.apiClient.getRolePolicies(role.id);
            if (policyResponse.success) {
                this.rolePolicy = policyResponse;
                this.updatePolicyRequirements();
            }
        } catch (error) {
            console.error('Error loading policy:', error);
        }

        // Show modal
        const modal = document.getElementById('activation-modal');
        if (modal) {
            modal.classList.remove('hidden');
            document.body.style.overflow = 'hidden';
        }
    }

    updatePolicyRequirements() {
        const container = document.getElementById('policy-requirements');
        if (!container || !this.rolePolicy) return;

        const requirements = [];

        if (this.rolePolicy.requiresMfa) {
            requirements.push('🔐 Multi-factor authentication required');
        }

        if (this.rolePolicy.requiresJustification) {
            requirements.push('📝 Justification is required');
        }

        if (this.rolePolicy.requiresTicket) {
            requirements.push('🎫 Ticket number is required');
        }

        if (requirements.length > 0) {
            container.innerHTML = `
                <div class="alert alert-info">
                    <strong>Policy Requirements:</strong>
                    <ul>
                        ${requirements.map(req => `<li>${req}</li>`).join('')}
                    </ul>
                </div>
            `;
        } else {
            container.innerHTML = '';
        }

        // Update form validation
        const justificationInput = document.getElementById('justification-input');
        const ticketInput = document.getElementById('ticket-input');

        if (justificationInput) {
            justificationInput.required = this.rolePolicy.requiresJustification;
        }

        if (ticketInput) {
            ticketInput.required = this.rolePolicy.requiresTicket;
        }
    }

    async handleActivate() {
        const form = document.getElementById('activation-form');
        if (!form.checkValidity()) {
            showToast('Please fill in all required fields', 'error');
            return;
        }

        const durationMinutes = parseInt(document.getElementById('duration-select').value);
        const justification = document.getElementById('justification-input').value;
        const ticketNumber = document.getElementById('ticket-input').value;

        try {
            showLoading(true);

            const result = await window.apiClient.activateRole(this.currentRole.id, 'User', {
                durationMinutes,
                justification: justification || null,
                ticketNumber: ticketNumber || null
            });

            if (result.success) {
                showToast(`Role "${this.currentRole.name}" activated successfully for ${durationMinutes} minutes`, 'success');
                this.closeDialog();

                // Refresh roles
                await window.roleManager.loadRoles();

                if (this.onSuccess) {
                    this.onSuccess();
                }
            } else {
                showToast(`Activation failed: ${result.error}`, 'error');
            }
        } catch (error) {
            showToast(`Error: ${error.message}`, 'error');
        } finally {
            showLoading(false);
        }
    }

    closeDialog() {
        const modal = document.getElementById('activation-modal');
        if (modal) {
            modal.classList.add('hidden');
            document.body.style.overflow = '';
        }
        this.currentRole = null;
        this.rolePolicy = null;
        this.onSuccess = null;
    }

    showPreferencesDialog() {
        const modal = document.getElementById('preferences-modal');
        if (modal) {
            // Restore saved theme selection
            const themeSelect = document.getElementById('theme-select');
            if (themeSelect) {
                themeSelect.value = localStorage.getItem('pim-theme') || 'auto';
            }
            modal.classList.remove('hidden');
            document.body.style.overflow = 'hidden';
        }
    }

    closePreferencesDialog() {
        const modal = document.getElementById('preferences-modal');
        if (modal) {
            modal.classList.add('hidden');
            document.body.style.overflow = '';
        }
    }

    async handleSavePreferences() {
        try {
            const preferences = {
                theme: document.getElementById('theme-select')?.value || 'auto',
                autoRefresh: document.getElementById('autorefresh-checkbox')?.checked || false
            };

            await window.apiClient.updateUserPreferences(preferences);
            showToast('Preferences saved successfully', 'success');
            this.closePreferencesDialog();

            // Apply theme
            applyThemePreference(preferences.theme);
        } catch (error) {
            showToast(`Error saving preferences: ${error.message}`, 'error');
        }
    }
}

// Global activation manager instance
window.activationManager = new ActivationManager();
