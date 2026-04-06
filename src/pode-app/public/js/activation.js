/**
 * PIM Activation - Role Activation Dialog
 */

class ActivationManager {
    constructor() {
        this.rolesToActivate = [];
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

        modal?.addEventListener('click', (e) => {
            if (e.target === modal) this.closeDialog();
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

    /**
     * Get the duration in minutes from the main page duration selectors
     */
    getSelectedDurationMinutes() {
        const hours = parseInt(document.getElementById('duration-hours')?.value || '8');
        const minutes = parseInt(document.getElementById('duration-minutes')?.value || '0');
        return (hours * 60) + minutes;
    }

    getSelectedDurationText() {
        const hours = parseInt(document.getElementById('duration-hours')?.value || '8');
        const minutes = parseInt(document.getElementById('duration-minutes')?.value || '0');
        const parts = [];
        if (hours > 0) parts.push(`${hours}h`);
        if (minutes > 0) parts.push(`${minutes}m`);
        return parts.join(' ') || '0m';
    }

    /**
     * Show activation dialog for one or multiple roles
     * @param {Object|Object[]} roles - single role or array of roles
     * @param {Function} onSuccess - callback after successful activation
     */
    showActivationDialog(roles, onSuccess = null) {
        this.rolesToActivate = Array.isArray(roles) ? roles : [roles];
        this.onSuccess = onSuccess;

        // Build role list table
        const roleList = document.getElementById('modal-role-list');
        if (roleList) {
            roleList.innerHTML = `
                <table>
                    <thead>
                        <tr>
                            <th>Type</th>
                            <th>Role Name</th>
                            <th>Scope</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${this.rolesToActivate.map(r => `
                            <tr>
                                <td><span class="type-badge ${(r.type || '').toLowerCase()}">${r.type || 'Entra'}</span></td>
                                <td>${escapeHtml(r.name)}</td>
                                <td>${escapeHtml(r.scope || 'Directory')}</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            `;
        }

        // Show duration from main page
        const durationInfo = document.getElementById('modal-duration-info');
        if (durationInfo) {
            durationInfo.textContent = `Duration: ${this.getSelectedDurationText()} (max duration enforced per role)`;
        }

        // Check policy requirements across all selected roles
        const needsJustification = this.rolesToActivate.some(r => r.requiresJustification);
        const needsTicket = this.rolesToActivate.some(r => r.requiresTicket);
        const needsMfa = this.rolesToActivate.some(r => r.requiresMfa);

        // Update policy requirements display
        const container = document.getElementById('policy-requirements');
        if (container) {
            const reqs = [];
            if (needsMfa) reqs.push('Multi-factor authentication required');
            if (needsJustification) reqs.push('Justification is required');
            if (needsTicket) reqs.push('Ticket number is required');

            if (reqs.length > 0) {
                container.innerHTML = `
                    <div class="alert alert-info">
                        <strong>Policy Requirements:</strong>
                        <ul>${reqs.map(r => `<li>${r}</li>`).join('')}</ul>
                    </div>
                `;
            } else {
                container.innerHTML = '';
            }
        }

        // Set field requirements
        const justInput = document.getElementById('justification-input');
        const ticketInput = document.getElementById('ticket-input');
        if (justInput) justInput.required = needsJustification;
        if (ticketInput) ticketInput.required = needsTicket;

        // Clear previous values
        if (justInput) justInput.value = '';
        if (ticketInput) ticketInput.value = '';

        // Show modal
        const modal = document.getElementById('activation-modal');
        if (modal) {
            modal.classList.remove('hidden');
            document.body.style.overflow = 'hidden';
        }
    }

    async handleActivate() {
        const form = document.getElementById('activation-form');
        if (!form.checkValidity()) {
            showToast('Please fill in all required fields', 'error');
            return;
        }

        const durationMinutes = this.getSelectedDurationMinutes();
        const justification = document.getElementById('justification-input').value;
        const ticketNumber = document.getElementById('ticket-input').value;

        try {
            showLoading(true);
            this.closeDialog();

            let successCount = 0;
            let errors = [];

            for (const role of this.rolesToActivate) {
                try {
                    const roleType = role.type === 'Group' ? 'Group' : 'User';
                    const result = await window.apiClient.activateRole(role.id, roleType, {
                        durationMinutes,
                        justification: justification || 'Activated via PIM Web',
                        ticketNumber: ticketNumber || null
                    });

                    if (result.success) {
                        successCount++;
                    } else {
                        errors.push(`${role.name}: ${result.error}`);
                    }
                } catch (error) {
                    errors.push(`${role.name}: ${error.message}`);
                }
            }

            if (successCount > 0) {
                showToast(`${successCount} role(s) activated for ${this.getSelectedDurationText()}`, 'success');
                await window.roleManager.loadRoles();
                if (this.onSuccess) this.onSuccess();
            }
            if (errors.length > 0) {
                showToast(`Failed: ${errors.join('; ')}`, 'error');
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
        this.rolesToActivate = [];
        this.onSuccess = null;
    }

    showPreferencesDialog() {
        const modal = document.getElementById('preferences-modal');
        if (modal) {
            const themeSelect = document.getElementById('theme-select');
            if (themeSelect) themeSelect.value = localStorage.getItem('pim-theme') || 'auto';
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
            applyThemePreference(preferences.theme);
        } catch (error) {
            showToast(`Error saving preferences: ${error.message}`, 'error');
        }
    }
}

// Global activation manager instance
window.activationManager = new ActivationManager();
