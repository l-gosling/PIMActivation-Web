/**
 * PIM Activation - Saved Role Profiles
 * Save and quickly activate frequently used role combinations.
 */

class ProfileManager {
    constructor() {
        this.profiles = [];
        this.dropdownOpen = false;
        this.initEventListeners();
    }

    initEventListeners() {
        const btn = document.getElementById('profiles-button');
        const menu = document.getElementById('profiles-menu');
        if (btn && menu) {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.toggleDropdown();
            });
            document.addEventListener('click', (e) => {
                if (!e.target.closest('.profiles-dropdown')) {
                    this.closeDropdown();
                }
            });
        }
    }

    async loadProfiles() {
        try {
            const resp = await window.apiClient.getUserPreferences();
            if (resp.success && resp.preferences) {
                this.profiles = Array.isArray(resp.preferences.profiles) ? resp.preferences.profiles : [];
            }
        } catch (e) {
            this.profiles = [];
        }
        this.renderDropdown();
    }

    async saveProfiles() {
        await window.apiClient.updateUserPreferences({ profiles: this.profiles });
    }

    toggleDropdown() {
        const menu = document.getElementById('profiles-menu');
        if (!menu) return;
        this.dropdownOpen = !this.dropdownOpen;
        menu.classList.toggle('hidden', !this.dropdownOpen);
        if (this.dropdownOpen) this.renderDropdown();
    }

    closeDropdown() {
        const menu = document.getElementById('profiles-menu');
        if (menu) menu.classList.add('hidden');
        this.dropdownOpen = false;
    }

    renderDropdown() {
        const menu = document.getElementById('profiles-menu');
        if (!menu) return;

        if (this.profiles.length === 0) {
            menu.innerHTML = `
                <div class="profile-empty">No saved profiles</div>
                <div class="profile-save-row">
                    <input id="profile-name-input" type="text" class="form-input form-input-sm" placeholder="Profile name...">
                    <button id="profile-save-btn" class="btn btn-primary btn-sm">Save</button>
                </div>`;
        } else {
            const eligible = window.roleManager?.eligibleRoles || [];
            const items = this.profiles.map((p, i) => {
                const roleCount = p.roles ? p.roles.length : 0;
                const durH = Math.floor((p.durationMinutes || 60) / 60);
                const durM = (p.durationMinutes || 60) % 60;
                const durText = (durH > 0 ? `${durH}h` : '') + (durM > 0 ? `${durM}m` : '') || '0m';
                const roleLines = (p.roles || []).map(r => {
                    const live = eligible.find(e => (e.uid || e.id) === r.uid);
                    if (!live) return r.uid || 'Unknown';
                    const scope = live.scope && live.scope !== 'Directory' ? ` (${live.scope})` : '';
                    return live.name + scope;
                });
                const tooltipHtml = roleLines.map(n => escapeHtml(n)).join('<br>');
                return `<div class="profile-item" data-index="${i}">
                    <div class="profile-info">
                        <span class="profile-name">${escapeHtml(p.name)}</span>
                        <span class="profile-meta"><span class="profile-role-count">${roleCount} role${roleCount !== 1 ? 's' : ''}<span class="profile-tooltip">${tooltipHtml}</span></span> &middot; ${durText}</span>
                    </div>
                    <div class="profile-actions">
                        <button class="btn btn-primary btn-sm profile-activate-btn" data-index="${i}">Activate</button>
                        <button class="btn btn-danger btn-sm profile-delete-btn" data-index="${i}">&times;</button>
                    </div>
                </div>`;
            }).join('');

            menu.innerHTML = `
                ${items}
                <div class="profile-save-row">
                    <input id="profile-name-input" type="text" class="form-input form-input-sm" placeholder="Profile name...">
                    <button id="profile-save-btn" class="btn btn-primary btn-sm">Save</button>
                </div>`;
        }

        // Bind events
        menu.querySelectorAll('.profile-activate-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(e.target.dataset.index);
                this.activateProfile(this.profiles[idx]);
            });
        });

        menu.querySelectorAll('.profile-delete-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(e.target.dataset.index);
                this.deleteProfile(idx);
            });
        });

        const saveBtn = document.getElementById('profile-save-btn');
        const nameInput = document.getElementById('profile-name-input');
        if (saveBtn && nameInput) {
            saveBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.handleSave();
            });
            nameInput.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    e.stopPropagation();
                    this.handleSave();
                }
            });
        }
    }

    async handleSave() {
        const input = document.getElementById('profile-name-input');
        const name = (input?.value || '').trim();

        if (!name) {
            showToast('Enter a profile name', 'error');
            return;
        }

        // Check duplicate names (case-insensitive)
        if (this.profiles.some(p => p.name.toLowerCase() === name.toLowerCase())) {
            showToast(`Profile "${name}" already exists`, 'error');
            return;
        }

        // Get selected eligible roles
        const selectedUids = Array.from(window.roleManager.selectedEligible);
        if (selectedUids.length === 0) {
            showToast('Select eligible roles first, then save as profile', 'error');
            return;
        }

        const roles = selectedUids
            .map(uid => window.roleManager.eligibleRoles.find(r => (r.uid || r.id) === uid))
            .filter(Boolean)
            .map(r => ({
                uid: r.uid || r.id,
                id: r.id,
                type: r.type,
                directoryScopeId: r.directoryScopeId || '/'
            }));

        const durationMinutes = window.activationManager.getSelectedDurationMinutes();

        this.profiles.push({ name, durationMinutes, roles });

        try {
            await this.saveProfiles();
            showToast(`Profile "${name}" saved (${roles.length} roles)`, 'success');
            if (input) input.value = '';
            this.renderDropdown();
        } catch (e) {
            this.profiles.pop();
            showToast(`Failed to save profile: ${e.message}`, 'error');
        }
    }

    async deleteProfile(index) {
        const removed = this.profiles.splice(index, 1)[0];
        try {
            await this.saveProfiles();
            showToast(`Profile "${removed.name}" deleted`, 'success');
            this.renderDropdown();
        } catch (e) {
            this.profiles.splice(index, 0, removed);
            showToast(`Failed to delete profile: ${e.message}`, 'error');
        }
    }

    activateProfile(profile) {
        this.closeDropdown();

        if (!profile || !profile.roles || profile.roles.length === 0) {
            showToast('Profile has no roles', 'error');
            return;
        }

        const eligible = window.roleManager.eligibleRoles;
        const matched = [];
        const missing = [];

        for (const saved of profile.roles) {
            const found = eligible.find(r => (r.uid || r.id) === saved.uid);
            if (found) {
                matched.push(found);
            } else {
                missing.push(saved.uid);
            }
        }

        if (missing.length > 0) {
            showToast(`${missing.length} role(s) no longer eligible and skipped`, 'warning', 8000);
        }

        if (matched.length === 0) {
            showToast('None of the profile roles are currently eligible', 'error');
            return;
        }

        // Set duration selectors to profile's saved duration
        const hours = Math.floor((profile.durationMinutes || 60) / 60);
        const minutes = (profile.durationMinutes || 60) % 60;
        const hoursSelect = document.getElementById('duration-hours');
        const minutesSelect = document.getElementById('duration-minutes');
        if (hoursSelect) {
            // Pick the closest available option that doesn't exceed the saved value
            const opts = Array.from(hoursSelect.options).map(o => parseInt(o.value));
            const best = opts.filter(v => v <= hours).pop() ?? opts[0];
            hoursSelect.value = best;
        }
        if (minutesSelect) {
            const opts = Array.from(minutesSelect.options).map(o => parseInt(o.value));
            const best = opts.filter(v => v <= minutes).pop() ?? opts[0];
            minutesSelect.value = best;
        }

        window.activationManager.showActivationDialog(matched);
    }
}

// Global profile manager instance — loads after auth
window.profileManager = new ProfileManager();
