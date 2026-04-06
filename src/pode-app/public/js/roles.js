/**
 * PIM Activation - Role Management
 */

class RoleManager {
    constructor() {
        this.eligibleRoles = [];
        this.activeRoles = [];
        this.selectedRoles = new Set();
        this.initEventListeners();
    }

    initEventListeners() {
        // Tab switching
        document.querySelectorAll('.nav-item').forEach(item => {
            item.addEventListener('click', (e) => this.switchTab(e.currentTarget));
        });

        // Search/filter
        document.getElementById('search-eligible')?.addEventListener('input', (e) => {
            this.filterRoles('eligible', e.target.value);
        });

        document.getElementById('search-active')?.addEventListener('input', (e) => {
            this.filterRoles('active', e.target.value);
        });

        // Select all button
        document.getElementById('select-all-button')?.addEventListener('click', () => {
            this.selectAll();
        });

        // Activate button
        document.getElementById('activate-button')?.addEventListener('click', () => {
            this.handleActivateMultiple();
        });

        // Deactivate button
        document.getElementById('deactivate-button')?.addEventListener('click', () => {
            this.handleDeactivateMultiple();
        });

        // Refresh button
        document.getElementById('refresh-button')?.addEventListener('click', () => {
            this.loadRoles();
        });
    }

    switchTab(element) {
        // Update nav items
        document.querySelectorAll('.nav-item').forEach(item => {
            item.classList.remove('active');
        });
        element.classList.add('active');

        // Update tab content
        const tabName = element.dataset.tab;
        document.querySelectorAll('.tab-content').forEach(tab => {
            tab.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`)?.classList.add('active');

        this.selectedRoles.clear();
        this.updateActionButtons();
    }

    async loadRoles() {
        try {
            showLoading(true);

            const [eligibleResponse, activeResponse] = await Promise.all([
                window.apiClient.getEligibleRoles(),
                window.apiClient.getActiveRoles()
            ]);

            if (eligibleResponse.success) {
                this.eligibleRoles = eligibleResponse.roles || [];
                this.renderRoles('eligible');
            }

            if (activeResponse.success) {
                this.activeRoles = activeResponse.roles || [];
                this.renderRoles('active');
            }

            showToast('Roles loaded successfully', 'success');
        } catch (error) {
            showToast(`Failed to load roles: ${error.message}`, 'error');
            console.error('Error loading roles:', error);
        } finally {
            showLoading(false);
        }
    }

    renderRoles(type) {
        const container = document.getElementById(`${type}-roles-list`);
        if (!container) return;

        const roles = type === 'eligible' ? this.eligibleRoles : this.activeRoles;

        if (roles.length === 0) {
            container.innerHTML = '<p class="empty-state">No roles found</p>';
            return;
        }

        container.innerHTML = roles.map((role, index) => this.createRoleElement(role, type, index)).join('');

        // Add event listeners to checkboxes
        container.querySelectorAll('.role-checkbox').forEach(checkbox => {
            checkbox.addEventListener('change', (e) => {
                const roleId = e.target.dataset.roleId;
                if (e.target.checked) {
                    this.selectedRoles.add(roleId);
                } else {
                    this.selectedRoles.delete(roleId);
                }
                this.updateActionButtons();
            });
        });

        // Add click handlers for role activation
        if (type === 'eligible') {
            container.querySelectorAll('.role-item').forEach(item => {
                item.addEventListener('click', (e) => {
                    if (e.target.type !== 'checkbox') {
                        const roleId = item.dataset.roleId;
                        const role = roles.find(r => r.id === roleId);
                        if (role) {
                            window.activationManager.showActivationDialog(role);
                        }
                    }
                });
            });
        }
    }

    createRoleElement(role, type, index) {
        const roleType = role.type || 'User';
        const typeBadgeClass = roleType.toLowerCase();
        const expiresAt = role.expiresAt ? new Date(role.expiresAt).toLocaleString() : '';

        let metaHtml = '';
        if (type === 'active' && expiresAt) {
            metaHtml = `<div class="role-meta">
                <div class="role-duration">
                    ⏱️ Expires: ${expiresAt}
                </div>
            </div>`;
        }

        return `
            <div class="role-item" data-role-id="${role.id}" data-role-index="${index}">
                <input 
                    type="checkbox" 
                    class="role-checkbox" 
                    data-role-id="${role.id}"
                    aria-label="Select ${role.name}"
                >
                <div class="role-info-box">
                    <div class="role-name">${escapeHtml(role.name)}</div>
                    <div>
                        <span class="role-type-badge ${typeBadgeClass}">${roleType}</span>
                        ${role.requiresJustification ? '<span class="role-type-badge">⚠️ Justification Required</span>' : ''}
                        ${role.requiresMfa ? '<span class="role-type-badge">🔐 MFA Required</span>' : ''}
                    </div>
                    <div class="role-scope">${escapeHtml(role.scope || 'N/A')}</div>
                    ${metaHtml}
                </div>
            </div>
        `;
    }

    filterRoles(type, query) {
        const container = document.getElementById(`${type}-roles-list`);
        if (!container) return;

        const items = container.querySelectorAll('.role-item');
        const lowerQuery = query.toLowerCase();

        items.forEach(item => {
            const roleeName = item.querySelector('.role-name').textContent.toLowerCase();
            const roleScope = item.querySelector('.role-scope').textContent.toLowerCase();

            if (roleeName.includes(lowerQuery) || roleScope.includes(lowerQuery)) {
                item.style.display = '';
            } else {
                item.style.display = 'none';
            }
        });
    }

    selectAll() {
        const activeTab = document.querySelector('.nav-item.active').dataset.tab;
        const container = document.getElementById(`${activeTab}-roles-list`);
        if (!container) return;

        container.querySelectorAll('.role-checkbox:not(:disabled)').forEach(checkbox => {
            if (checkbox.offsetParent !== null) { // Only visible items
                checkbox.checked = true;
                this.selectedRoles.add(checkbox.dataset.roleId);
            }
        });

        this.updateActionButtons();
    }

    updateActionButtons() {
        const activateBtn = document.getElementById('activate-button');
        const deactivateBtn = document.getElementById('deactivate-button');

        if (activateBtn) {
            activateBtn.disabled = this.selectedRoles.size === 0;
        }

        if (deactivateBtn) {
            deactivateBtn.disabled = this.selectedRoles.size === 0;
        }
    }

    async handleActivateMultiple() {
        if (this.selectedRoles.size === 0) return;

        const roleIds = Array.from(this.selectedRoles);
        const firstRole = this.eligibleRoles.find(r => r.id === roleIds[0]);

        if (firstRole) {
            window.activationManager.showActivationDialog(firstRole, () => {
                this.selectedRoles.clear();
                this.updateActionButtons();
            });
        }
    }

    async handleDeactivateMultiple() {
        if (this.selectedRoles.size === 0) return;

        if (!confirm(`Deactivate ${this.selectedRoles.size} role(s)?`)) {
            return;
        }

        try {
            showLoading(true);

            const roleIds = Array.from(this.selectedRoles);
            const results = await Promise.allSettled(
                roleIds.map(roleId =>
                    window.apiClient.deactivateRole(roleId, 'User')
                )
            );

            const successCount = results.filter(r => r.status === 'fulfilled').length;
            const failureCount = results.filter(r => r.status === 'rejected').length;

            if (successCount > 0) {
                showToast(`${successCount} role(s) deactivated successfully`, 'success');
                await this.loadRoles();
            }

            if (failureCount > 0) {
                showToast(`Failed to deactivate ${failureCount} role(s)`, 'error');
            }
        } catch (error) {
            showToast(`Error: ${error.message}`, 'error');
        } finally {
            showLoading(false);
            this.selectedRoles.clear();
            this.updateActionButtons();
        }
    }
}

// Global role manager instance
window.roleManager = new RoleManager();
