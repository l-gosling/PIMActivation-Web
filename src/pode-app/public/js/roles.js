/**
 * PIM Activation - Role Management
 */

class RoleManager {
    constructor() {
        this.eligibleRoles = [];
        this.activeRoles = [];
        this.selectedEligible = new Set();
        this.selectedActive = new Set();
        this.initEventListeners();
    }

    initEventListeners() {
        document.getElementById('activate-button')?.addEventListener('click', () => this.handleActivate());
        document.getElementById('deactivate-button')?.addEventListener('click', () => this.handleDeactivate());
        document.getElementById('refresh-button')?.addEventListener('click', () => this.loadRoles());
        document.getElementById('refresh-button-bottom')?.addEventListener('click', () => this.loadRoles());

        document.getElementById('search-active')?.addEventListener('input', (e) => {
            this.filterRoles('active', e.target.value);
        });
        document.getElementById('search-eligible')?.addEventListener('input', (e) => {
            this.filterRoles('eligible', e.target.value);
        });
    }

    sortRoles(roles) {
        return roles.sort((a, b) => {
            const typeA = (a.type || '').toLowerCase();
            const typeB = (b.type || '').toLowerCase();
            if (typeA !== typeB) return typeA.localeCompare(typeB);
            const nameA = (a.name || '').toLowerCase();
            const nameB = (b.name || '').toLowerCase();
            if (nameA !== nameB) return nameA.localeCompare(nameB);
            const scopeA = (a.scope || '').toLowerCase();
            const scopeB = (b.scope || '').toLowerCase();
            return scopeA.localeCompare(scopeB);
        });
    }

    async loadRoles() {
        try {
            showLoading(true);

            const [eligibleResponse, activeResponse] = await Promise.all([
                window.apiClient.getEligibleRoles(),
                window.apiClient.getActiveRoles()
            ]);

            if (activeResponse.success) {
                this.activeRoles = this.sortRoles(activeResponse.roles || []);
                this.renderActiveRoles();
            }

            if (eligibleResponse.success) {
                this.eligibleRoles = this.sortRoles(eligibleResponse.roles || []);
                this.renderEligibleRoles();
            }

            showToast('Roles loaded successfully', 'success');
        } catch (error) {
            showToast(`Failed to load roles: ${error.message}`, 'error');
            console.error('Error loading roles:', error);
        } finally {
            showLoading(false);
        }
    }

    renderActiveRoles() {
        const tbody = document.getElementById('active-roles-body');
        const empty = document.getElementById('active-empty');
        const count = document.getElementById('active-count');

        if (!tbody) return;

        count.textContent = `${this.activeRoles.length} roles active`;

        if (this.activeRoles.length === 0) {
            tbody.innerHTML = '';
            empty?.classList.remove('hidden');
            return;
        }
        empty?.classList.add('hidden');

        tbody.innerHTML = this.activeRoles.map((role, i) => {
            const uid = role.uid || role.id;
            const typeBadge = `<span class="type-badge ${(role.type || '').toLowerCase()}">[${role.type}]</span>`;
            const resource = role.resourceName || 'Entra ID Directory';
            const scope = role.scope || 'Directory';
            const memberType = role.memberType || 'Direct';

            let expiresHtml;
            if (role.endDateTime) {
                const d = new Date(role.endDateTime);
                const now = new Date();
                const hoursLeft = (d - now) / 3600000;
                const cls = hoursLeft < 1 ? 'expires-soon' : '';
                expiresHtml = `<span class="${cls}">${d.toLocaleString()}</span>`;
            } else {
                expiresHtml = '<span class="expires-permanent">Permanent</span>';
            }

            return `<tr data-uid="${uid}" data-index="${i}">
                <td class="col-check"><label class="check-area"><input type="checkbox" class="active-check" data-uid="${uid}"></label></td>
                <td>${typeBadge}</td>
                <td>${escapeHtml(role.name)}</td>
                <td class="${resource.includes('via Group') ? 'resource-via-group' : ''}">${escapeHtml(resource)}</td>
                <td>${escapeHtml(scope)}</td>
                <td>${escapeHtml(memberType)}</td>
                <td>${expiresHtml}</td>
            </tr>`;
        }).join('');

        tbody.querySelectorAll('.active-check').forEach(cb => {
            cb.addEventListener('change', (e) => {
                const uid = e.target.dataset.uid;
                if (e.target.checked) this.selectedActive.add(uid);
                else this.selectedActive.delete(uid);
                this.updateButtons();
            });
        });
    }

    renderEligibleRoles() {
        const tbody = document.getElementById('eligible-roles-body');
        const empty = document.getElementById('eligible-empty');
        const count = document.getElementById('eligible-count');

        if (!tbody) return;

        count.textContent = `${this.eligibleRoles.length} roles available`;

        if (this.eligibleRoles.length === 0) {
            tbody.innerHTML = '';
            empty?.classList.remove('hidden');
            return;
        }
        empty?.classList.add('hidden');

        tbody.innerHTML = this.eligibleRoles.map((role, i) => {
            const uid = role.uid || role.id;
            const typeBadge = `<span class="type-badge ${(role.type || '').toLowerCase()}">[${role.type}]</span>`;
            const scope = role.scope || 'Directory';
            const memberType = role.memberType || 'Direct';

            const maxDur = role.maxDurationHours ? `${role.maxDurationHours}h` : '8h';

            const flagHtml = (val) => val
                ? '<span class="flag-required">Required</span>'
                : '<span class="flag-no">No</span>';
            const yesNo = (val) => val
                ? '<span class="flag-yes">Yes</span>'
                : '<span class="flag-no">No</span>';

            return `<tr data-uid="${uid}" data-index="${i}">
                <td class="col-check"><label class="check-area"><input type="checkbox" class="eligible-check" data-uid="${uid}"></label></td>
                <td>${typeBadge}</td>
                <td>${escapeHtml(role.name)}</td>
                <td>${escapeHtml(scope)}</td>
                <td>${escapeHtml(memberType)}</td>
                <td>${maxDur}</td>
                <td>${yesNo(role.requiresMfa)}</td>
                <td>${flagHtml(role.requiresJustification)}</td>
                <td>${flagHtml(role.requiresTicket)}</td>
                <td>${flagHtml(role.requiresApproval)}</td>
            </tr>`;
        }).join('');

        tbody.querySelectorAll('.eligible-check').forEach(cb => {
            cb.addEventListener('change', (e) => {
                e.stopPropagation();
                const uid = e.target.dataset.uid;
                if (e.target.checked) this.selectedEligible.add(uid);
                else this.selectedEligible.delete(uid);
                this.updateButtons();
            });
        });

        // Row click to activate (only if not clicking checkbox area)
        tbody.querySelectorAll('tr').forEach(row => {
            row.addEventListener('click', (e) => {
                if (e.target.closest('.check-area')) return;
                const uid = row.dataset.uid;
                const role = this.eligibleRoles.find(r => (r.uid || r.id) === uid);
                if (role) window.activationManager.showActivationDialog(role);
            });
        });
    }

    updateButtons() {
        const activateBtn = document.getElementById('activate-button');
        const deactivateBtn = document.getElementById('deactivate-button');
        if (activateBtn) activateBtn.disabled = this.selectedEligible.size === 0;
        if (deactivateBtn) deactivateBtn.disabled = this.selectedActive.size === 0;
    }

    selectAll() {
        document.querySelectorAll('.eligible-check').forEach(cb => {
            cb.checked = true;
            this.selectedEligible.add(cb.dataset.uid);
        });
        this.updateButtons();
    }

    handleActivate() {
        if (this.selectedEligible.size === 0) return;
        const uids = Array.from(this.selectedEligible);
        const roles = uids
            .map(uid => this.eligibleRoles.find(r => (r.uid || r.id) === uid))
            .filter(Boolean);

        if (roles.length > 0) {
            window.activationManager.showActivationDialog(roles, () => {
                this.selectedEligible.clear();
                this.updateButtons();
            });
        }
    }

    async handleDeactivate() {
        if (this.selectedActive.size === 0) return;
        if (!confirm(`Deactivate ${this.selectedActive.size} role(s)?`)) return;

        try {
            showLoading(true);
            const uids = Array.from(this.selectedActive);
            let succeeded = [];
            let failed = [];

            for (const uid of uids) {
                const role = this.activeRoles.find(r => (r.uid || r.id) === uid);
                const roleLabel = role
                    ? `[${role.type}] ${role.name}${role.scope && role.scope !== 'Directory' ? ' (' + role.scope + ')' : ''}`
                    : uid;
                try {
                    const result = await window.apiClient.deactivateRole(role?.id || uid, role?.type || 'User', {
                        directoryScopeId: role?.directoryScopeId || '/'
                    });
                    if (result.success) {
                        succeeded.push(roleLabel);
                    } else {
                        failed.push({ role: roleLabel, error: result.error || 'Unknown error' });
                    }
                } catch (error) {
                    failed.push({ role: roleLabel, error: error.message });
                }
            }

            if (succeeded.length > 0 && failed.length === 0) {
                const roleList = succeeded.join('\n');
                showToast(`Deactivated ${succeeded.length} role(s):\n${roleList}`, 'success', 10000);
                await new Promise(resolve => setTimeout(resolve, 3000));
                await this.loadRoles();
            }
            else if (failed.length > 0) {
                let details = '';
                if (succeeded.length > 0) {
                    details += `Deactivated:\n${succeeded.join('\n')}\n\n`;
                }
                details += `Failed (${failed.length}):\n${failed.map(f => `${f.role}\n  Error: ${f.error}`).join('\n\n')}`;
                showErrorToast(
                    `${succeeded.length} deactivated, ${failed.length} failed`,
                    details
                );
                if (succeeded.length > 0) {
                    await new Promise(resolve => setTimeout(resolve, 3000));
                    await this.loadRoles();
                }
            }
        } catch (error) {
            showErrorToast('Deactivation error', error.message);
        } finally {
            showLoading(false);
            this.selectedActive.clear();
            document.querySelectorAll('.active-check').forEach(cb => cb.checked = false);
            this.updateButtons();
        }
    }

    filterRoles(type, query) {
        const tableId = type === 'eligible' ? 'eligible-roles-body' : 'active-roles-body';
        const tbody = document.getElementById(tableId);
        if (!tbody) return;
        const lower = query.toLowerCase();
        tbody.querySelectorAll('tr').forEach(row => {
            row.style.display = row.textContent.toLowerCase().includes(lower) ? '' : 'none';
        });
    }
}

window.roleManager = new RoleManager();
