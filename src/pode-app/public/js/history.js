/**
 * PIM Activation - Activation History & Analytics
 * Records activation/deactivation events and provides reporting.
 */

class HistoryManager {
    constructor() {
        this.entries = [];       // Local events (from this app)
        this.entraEntries = [];  // Events from Entra audit logs (read-only, not counted in success rate)
        this.maxEntries = 200;
        this.initEventListeners();
    }

    initEventListeners() {
        document.getElementById('history-button')?.addEventListener('click', () => this.showHistoryModal());

        const modal = document.getElementById('history-modal');
        modal?.querySelector('.close-button')?.addEventListener('click', () => this.closeHistoryModal());
        document.getElementById('history-close-button')?.addEventListener('click', () => this.closeHistoryModal());
        document.getElementById('history-clear-button')?.addEventListener('click', () => this.handleClear());
        modal?.addEventListener('click', (e) => {
            if (e.target === modal) this.closeHistoryModal();
        });

    }

    async loadHistory() {
        try {
            const resp = await window.apiClient.getUserPreferences();
            if (resp.success && resp.preferences) {
                this.entries = Array.isArray(resp.preferences.history) ? resp.preferences.history : [];
            }
        } catch (e) {
            this.entries = [];
        }
    }

    async saveHistory() {
        // Cap entries to prevent unbounded growth
        if (this.entries.length > this.maxEntries) {
            this.entries = this.entries.slice(-this.maxEntries);
        }
        await window.apiClient.updateUserPreferences({ history: this.entries });
    }

    /**
     * Load activation history from Entra audit logs in the background.
     * Called after roles are loaded — does not block the UI.
     */
    async loadAuditHistory() {
        try {
            const resp = await window.apiClient.getAuditHistory();
            if (resp.success && Array.isArray(resp.entries)) {
                this.entraEntries = resp.entries.map(e => ({ ...e, source: 'entra' }));
            }
        } catch (e) {
            console.warn('Could not load Entra audit history:', e);
            this.entraEntries = [];
        }
    }

    /**
     * Get all entries (local + Entra) merged, deduplicated, and sorted by timestamp descending.
     * When a local entry matches an Entra entry (same action, same role, within 10 minutes),
     * only the local entry is kept. Entra entries are also deduped against each other.
     */
    getAllEntries() {
        const local = this.entries.map(e => ({ ...e, source: e.source || 'local' }));

        // Build a set of local event keys for fast dedup lookup
        const localKeys = new Set();
        for (const loc of local) {
            // Create keys at 1-minute granularity spanning +/- 10 minutes around the event
            const t = new Date(loc.timestamp).getTime();
            const name = (loc.roleName || '').toLowerCase();
            for (let offset = -10; offset <= 10; offset++) {
                const minuteKey = Math.floor((t + offset * 60000) / 60000);
                localKeys.add(`${loc.action}|${name}|${minuteKey}`);
            }
        }

        // Filter Entra entries: drop if a local entry covers the same event, and dedup among themselves
        const seenEntra = new Set();
        const filtered = [];
        for (const entra of this.entraEntries) {
            const t = new Date(entra.timestamp).getTime();
            const name = (entra.roleName || '').toLowerCase();
            const minuteKey = Math.floor(t / 60000);
            const dedupKey = `${entra.action}|${name}|${minuteKey}`;

            // Skip if local already has this event
            if (localKeys.has(dedupKey)) continue;
            // Skip if already seen from Entra
            if (seenEntra.has(dedupKey)) continue;

            seenEntra.add(dedupKey);
            filtered.push(entra);
        }

        const all = [...local, ...filtered];
        all.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        return all;
    }

    /**
     * Record one or more activation/deactivation events (local, from this app).
     * @param {Object[]} events - array of { action, roleName, roleType, scope, durationMinutes, justification, success, error }
     */
    async recordEvents(events) {
        const timestamp = new Date().toISOString();
        for (const evt of events) {
            this.entries.push({
                action: evt.action,
                roleName: evt.roleName,
                roleType: evt.roleType || 'Entra',
                scope: evt.scope || 'Directory',
                durationMinutes: evt.durationMinutes || null,
                justification: evt.justification || null,
                success: evt.success,
                error: evt.error || null,
                timestamp,
                source: 'local'
            });
        }
        try {
            await this.saveHistory();
        } catch (e) {
            console.warn('Failed to save history:', e);
        }
    }

    showHistoryModal() {
        const modal = document.getElementById('history-modal');
        if (!modal) return;
        this.renderHistory();
        this.renderAnalytics();
        modal.classList.remove('hidden');
        document.body.style.overflow = 'hidden';
    }

    closeHistoryModal() {
        const modal = document.getElementById('history-modal');
        if (modal) {
            modal.classList.add('hidden');
            document.body.style.overflow = '';
        }
    }

    async handleClear() {
        // Temporarily restore overflow so the confirm dialog can appear
        document.body.style.overflow = '';
        const confirmed = confirm('Clear all activation history?');
        document.body.style.overflow = 'hidden';
        if (!confirmed) return;

        this.entries = [];
        this.entraEntries = [];
        try {
            await this.saveHistory();
            showToast('History cleared', 'success');
            this.renderHistory();
            this.renderAnalytics();
        } catch (e) {
            showToast('Failed to clear history', 'error');
        }
    }

    renderHistory() {
        const tbody = document.getElementById('history-table-body');
        if (!tbody) return;

        const allEntries = this.getAllEntries();

        if (allEntries.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="history-empty">No activation history yet</td></tr>';
            return;
        }

        // Store errors by index for safe retrieval (avoids HTML attribute escaping issues)
        this._displayedErrors = {};

        tbody.innerHTML = allEntries.map((e, idx) => {
            const date = new Date(e.timestamp);
            const dateStr = date.toLocaleDateString();
            const timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const actionClass = e.action === 'activate' ? 'history-action-activate' : 'history-action-deactivate';
            const actionLabel = e.action === 'activate' ? 'Activate' : 'Deactivate';
            const statusClass = e.success ? 'history-status-success' : 'history-status-failed';
            const statusLabel = e.success ? 'OK' : 'Failed';
            const durText = e.durationMinutes
                ? (e.durationMinutes >= 60 ? `${Math.floor(e.durationMinutes/60)}h${e.durationMinutes%60 ? e.durationMinutes%60 + 'm' : ''}` : `${e.durationMinutes}m`)
                : '-';

            const sourceClass = e.source === 'entra' ? 'history-source-entra' : 'history-source-local';
            const sourceLabel = e.source === 'entra' ? 'Entra Log' : 'Local';

            let errorIcon = '';
            if (!e.success && e.error) {
                this._displayedErrors[idx] = e.error;
                errorIcon = `<button class="history-error-btn" data-idx="${idx}" title="Show error details">!</button>`;
            }

            return `<tr class="${e.source === 'entra' ? 'history-row-entra' : ''}">
                <td><span class="${actionClass}">${actionLabel}</span></td>
                <td>${escapeHtml(e.roleName || '-')}</td>
                <td><span class="type-badge ${(e.roleType || '').toLowerCase()}">${escapeHtml(e.roleType || '-')}</span></td>
                <td>${escapeHtml(e.scope || '-')}</td>
                <td>${durText}</td>
                <td><span class="${statusClass}">${statusLabel}</span> ${errorIcon}</td>
                <td>${dateStr} ${timeStr} <span class="${sourceClass}">${sourceLabel}</span></td>
            </tr>`;
        }).join('');

        // Bind error detail buttons using index lookup
        tbody.querySelectorAll('.history-error-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const msg = this._displayedErrors[btn.dataset.idx];
                if (msg) showErrorToast('Error Details', msg);
            });
        });
    }

    renderAnalytics() {
        const container = document.getElementById('analytics-content');
        if (!container) return;

        // Analytics use only LOCAL entries — Entra log entries are excluded
        // to avoid skewing success rate and duration stats
        const local = this.entries.filter(e => (e.source || 'local') === 'local');

        if (local.length === 0 && this.entraEntries.length === 0) {
            container.innerHTML = '<div class="history-empty">No data available yet</div>';
            return;
        }

        const total = local.length;
        const activations = local.filter(e => e.action === 'activate');
        const deactivations = local.filter(e => e.action === 'deactivate');
        const successes = local.filter(e => e.success);
        const failures = local.filter(e => !e.success);
        const successRate = total > 0 ? Math.round((successes.length / total) * 100) : 0;

        // Average duration (local activations only)
        const withDuration = activations.filter(e => e.durationMinutes && e.success);
        const avgDuration = withDuration.length > 0
            ? Math.round(withDuration.reduce((sum, e) => sum + e.durationMinutes, 0) / withDuration.length)
            : 0;
        const avgDurText = avgDuration >= 60
            ? `${Math.floor(avgDuration/60)}h ${avgDuration%60}m`
            : `${avgDuration}m`;

        // Top 5 most activated roles (all sources — usage frequency is not a success metric)
        const allActivations = this.getAllEntries().filter(e => e.action === 'activate' && e.success);
        const roleCounts = {};
        for (const e of allActivations) {
            const key = e.roleName || 'Unknown';
            roleCounts[key] = (roleCounts[key] || 0) + 1;
        }
        const topRoles = Object.entries(roleCounts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5);
        const maxCount = topRoles.length > 0 ? topRoles[0][1] : 1;

        // Activity by day of week (all sources)
        const allEntries = this.getAllEntries();
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const dayCounts = new Array(7).fill(0);
        for (const e of allEntries) {
            dayCounts[new Date(e.timestamp).getDay()]++;
        }
        const maxDay = Math.max(...dayCounts, 1);

        container.innerHTML = `
            <div class="analytics-cards">
                <div class="analytics-card">
                    <div class="analytics-value">${total}</div>
                    <div class="analytics-label">Total Actions</div>
                </div>
                <div class="analytics-card">
                    <div class="analytics-value">${activations.length}</div>
                    <div class="analytics-label">Activations</div>
                </div>
                <div class="analytics-card">
                    <div class="analytics-value">${deactivations.length}</div>
                    <div class="analytics-label">Deactivations</div>
                </div>
                <div class="analytics-card">
                    <div class="analytics-value">${successRate}%</div>
                    <div class="analytics-label">Success Rate</div>
                </div>
                <div class="analytics-card">
                    <div class="analytics-value">${avgDurText}</div>
                    <div class="analytics-label">Avg Duration</div>
                </div>
                <div class="analytics-card">
                    <div class="analytics-value">${failures.length}</div>
                    <div class="analytics-label">Failures</div>
                </div>
            </div>

            <div class="analytics-section">
                <h3>Most Activated Roles</h3>
                ${topRoles.length > 0 ? `<div class="analytics-bars">
                    ${topRoles.map(([name, count]) => `
                        <div class="analytics-bar-row">
                            <span class="analytics-bar-label">${escapeHtml(name)}</span>
                            <div class="analytics-bar-track">
                                <div class="analytics-bar-fill" style="width: ${Math.round((count / maxCount) * 100)}%"></div>
                            </div>
                            <span class="analytics-bar-value">${count}</span>
                        </div>`).join('')}
                </div>` : '<div class="history-empty">No activations recorded</div>'}
            </div>

            <div class="analytics-section">
                <h3>Activity by Day</h3>
                <div class="analytics-bars">
                    ${dayNames.map((name, i) => `
                        <div class="analytics-bar-row">
                            <span class="analytics-bar-label analytics-bar-label-short">${name}</span>
                            <div class="analytics-bar-track">
                                <div class="analytics-bar-fill" style="width: ${Math.round((dayCounts[i] / maxDay) * 100)}%"></div>
                            </div>
                            <span class="analytics-bar-value">${dayCounts[i]}</span>
                        </div>`).join('')}
                </div>
            </div>`;
    }
}

window.historyManager = new HistoryManager();
