const API_URL = 'http://localhost:8080';

class AdminApi {
  constructor() {
    this.adminKey = localStorage.getItem('adminKey') || '';
  }

  setAdminKey(key) {
    this.adminKey = key;
    localStorage.setItem('adminKey', key);
  }

  logout() {
    this.adminKey = '';
    localStorage.removeItem('adminKey');
  }

  isAuthenticated() {
    return this.adminKey.length > 0;
  }

  async _fetch(endpoint, options = {}) {
    if (!this.adminKey) throw new Error('Not authenticated');

    const headers = {
      'Content-Type': 'application/json',
      'x-admin-key': this.adminKey,
      ...options.headers,
    };

    const response = await fetch(`${API_URL}${endpoint}`, {
      ...options,
      headers,
    });

    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        this.logout();
      }
      throw new Error(body.error?.message || 'API request failed');
    }

    return body.data;
  }

  async getOverview() {
    return this._fetch('/admin/overview');
  }

  async getUsers(role) {
    const qs = role ? `?role=${encodeURIComponent(role)}` : '';
    return this._fetch(`/admin/users${qs}`);
  }

  async getHosts() {
    return this._fetch('/admin/hosts');
  }

  async getSessions(status) {
    const qs = status ? `?status=${encodeURIComponent(status)}` : '';
    return this._fetch(`/admin/sessions${qs}`);
  }

  async getHostsEarnings() {
    return this._fetch('/admin/hosts/earnings');
  }

  async createPayout(hostId, credits, method = 'upi') {
    return this._fetch(`/admin/hosts/${hostId}/payout`, {
      method: 'POST',
      body: JSON.stringify({ credits, method }),
    });
  }

  async confirmPayout(hostId, payoutId, amountCredits, reference) {
    return this._fetch(`/admin/payouts/${payoutId}/confirm`, {
      method: 'POST',
      body: JSON.stringify({ hostId, amountCredits, reference }),
    });
  }
}

export const api = new AdminApi();
