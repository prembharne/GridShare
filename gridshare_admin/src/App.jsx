import { useState, useEffect, useCallback } from 'react';
import { ShieldAlert, Zap, LayoutDashboard, Users, CreditCard, Activity, LogOut } from 'lucide-react';
import { api } from './api';
import './index.css';

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(api.isAuthenticated());
  const [authKey, setAuthKey] = useState('');
  const [hosts, setHosts] = useState([]);
  const [users, setUsers] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [overview, setOverview] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('overview');

  const handleLogout = useCallback(() => {
    api.logout();
    setIsAuthenticated(false);
    setAuthKey('');
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [ov, us, hs, ss] = await Promise.all([
        api.getOverview(),
        api.getUsers(),
        api.getHosts(),
        api.getSessions(),
      ]);
      setOverview(ov);
      setUsers(us);
      setHosts(hs);
      setSessions(ss);
    } catch (e) {
      console.error(e);
      if (e.message.includes('authenticated') || e.message.includes('401')) {
        handleLogout();
      } else {
        setError(e.message);
      }
    } finally {
      setLoading(false);
    }
  }, [handleLogout]);

  useEffect(() => {
    if (isAuthenticated) {
      loadData();
    }
  }, [isAuthenticated, loadData]);

  const handleLogin = (e) => {
    e.preventDefault();
    if (!authKey.trim()) return;
    api.setAdminKey(authKey.trim());
    setIsAuthenticated(true);
  };

  const handleCreatePayout = async (hostId, credits) => {
    try {
      await api.createPayout(hostId, credits, 'upi');
      loadData();
    } catch (e) {
      alert('Failed to initiate payout: ' + e.message);
    }
  };

  if (!isAuthenticated) {
    return (
      <div style={{ display: 'flex', height: '100vh', alignItems: 'center', justifyContent: 'center' }}>
        <div className="glass-card" style={{ width: '400px', textAlign: 'center' }}>
          <div style={{ background: 'var(--brand-primary)', width: 64, height: 64, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 24px' }}>
            <ShieldAlert color="white" size={32} />
          </div>
          <h2>Admin Authentication</h2>
          <p style={{ marginBottom: 24 }}>Enter your GridShare Admin API Key to access the dashboard.</p>
          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            <input
              type="password"
              className="input-field"
              placeholder="e.g. mock_admin_key_123"
              value={authKey}
              onChange={(e) => setAuthKey(e.target.value)}
              autoFocus
            />
            <button type="submit" className="btn btn-primary" style={{ width: '100%' }}>
              Authenticate
            </button>
          </form>
        </div>
      </div>
    );
  }

  const titles = {
    overview: ['Overview', 'High-level metrics and system health.'],
    users: ['Users Directory', 'Everyone who has signed in to the GridShare app.'],
    hosts: ['Host Management', 'Registered hosts, their earnings and hosted sessions.'],
    sessions: ['Activity Feed', 'Charging sessions across all users.'],
    payouts: ['Payouts Queue', 'Track host earnings, process verifications, and settle UPI payments.'],
  };
  const [title, subtitle] = titles[activeTab] ?? ['', ''];

  return (
    <div className="app-container">
      {/* Sidebar */}
      <div className="sidebar">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', marginBottom: 32 }}>
          <div style={{ background: 'var(--brand-primary)', padding: 8, borderRadius: 12 }}>
            <Zap color="white" size={24} />
          </div>
          <h2 style={{ margin: 0, fontSize: '1.25rem', letterSpacing: '-0.5px' }}>GridShare HQ</h2>
        </div>

        <NavItem icon={<LayoutDashboard />} label="Overview" active={activeTab === 'overview'} onClick={() => setActiveTab('overview')} />
        <NavItem icon={<Users />} label="Users" active={activeTab === 'users'} onClick={() => setActiveTab('users')} />
        <NavItem icon={<Users />} label="Host Management" active={activeTab === 'hosts'} onClick={() => setActiveTab('hosts')} />
        <NavItem icon={<Activity />} label="Activity Feed" active={activeTab === 'sessions'} onClick={() => setActiveTab('sessions')} />
        <NavItem icon={<CreditCard />} label="Payouts Queue" active={activeTab === 'payouts'} onClick={() => setActiveTab('payouts')} />

        <div style={{ marginTop: 'auto' }}>
          <button className="btn btn-outline" style={{ width: '100%', justifyContent: 'flex-start' }} onClick={handleLogout}>
            <LogOut size={18} /> Sign Out
          </button>
        </div>
      </div>

      {/* Main Content */}
      <div className="main-content">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 40 }}>
          <div>
            <h1>{title}</h1>
            <p>{subtitle}</p>
          </div>
          <button className="btn btn-outline" onClick={loadData} disabled={loading}>
            {loading ? 'Loading…' : 'Refresh Data'}
          </button>
        </div>

        {error && (
          <div className="glass-card" style={{ marginBottom: 24, borderLeft: '3px solid var(--danger)', color: 'var(--danger)' }}>
            {error}
          </div>
        )}

        {activeTab === 'overview' && (
          <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap', marginBottom: 40 }}>
            <MetricCard title="Total Users" value={overview?.totalUsers ?? '—'} trend={`${overview?.riders ?? 0} riders`} />
            <MetricCard title="Hosts" value={overview?.hosts ?? '—'} trend="Registered hosts" />
            <MetricCard title="Active Sessions" value={overview?.activeSessions ?? '—'} trend={`${overview?.totalSessions ?? 0} total`} alert={(overview?.activeSessions ?? 0) > 0} />
            <MetricCard title="Credits in Circulation" value={overview?.creditsInCirculation != null ? `${overview.creditsInCirculation} ⚡` : '—'} trend={overview?.creditsInCirculation != null ? `₹${overview.creditsInCirculation}` : 'n/a'} />
          </div>
        )}

        {activeTab === 'users' && (
          <div className="glass-panel" style={{ padding: 24 }}>
            <h3 style={{ marginBottom: 20 }}>Registered Users</h3>
            <div className="data-table-wrapper">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>User ID</th>
                    <th>Name</th>
                    <th>Phone</th>
                    <th>Role</th>
                    <th>Balance</th>
                    <th>Sessions</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((u) => (
                    <tr key={u.id}>
                      <td><div style={{ fontWeight: 600 }}>{u.id}</div></td>
                      <td>{u.name || <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                      <td>{u.phone || <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                      <td><span className={`badge ${u.role === 'host' ? 'badge-success' : 'badge-warning'}`}>{u.role}</span></td>
                      <td>{u.balanceCredits} ⚡</td>
                      <td>{u.sessionCount}</td>
                    </tr>
                  ))}
                  {users.length === 0 && <EmptyRow cols={6} label="No users yet. They appear here after signing in." />}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === 'hosts' && (
          <div className="glass-panel" style={{ padding: 24 }}>
            <h3 style={{ marginBottom: 20 }}>Host Directory</h3>
            <div className="data-table-wrapper">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Host ID</th>
                    <th>Name</th>
                    <th>Phone</th>
                    <th>Earned Credits</th>
                    <th>Value (INR)</th>
                    <th>Hosted Sessions</th>
                  </tr>
                </thead>
                <tbody>
                  {hosts.map((h) => (
                    <tr key={h.id}>
                      <td><div style={{ fontWeight: 600 }}>{h.id}</div></td>
                      <td>{h.name || <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                      <td>{h.phone || <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                      <td><div style={{ fontWeight: 700, color: 'var(--brand-primary)' }}>{h.earnedCredits} ⚡</div></td>
                      <td>₹{h.earnedCredits}</td>
                      <td>{h.hostedSessions}</td>
                    </tr>
                  ))}
                  {hosts.length === 0 && <EmptyRow cols={6} label="No hosts registered yet." />}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === 'sessions' && (
          <div className="glass-panel" style={{ padding: 24 }}>
            <h3 style={{ marginBottom: 20 }}>Charging Sessions</h3>
            <div className="data-table-wrapper">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Session ID</th>
                    <th>Rider</th>
                    <th>Host</th>
                    <th>Status</th>
                    <th>Deposit</th>
                    <th>Settled</th>
                  </tr>
                </thead>
                <tbody>
                  {sessions.map((s) => (
                    <tr key={s.id}>
                      <td><div style={{ fontWeight: 600 }}>{s.id}</div></td>
                      <td>{s.riderId}</td>
                      <td>{s.hostId}</td>
                      <td><span className={`badge ${statusBadge(s.status)}`}>{s.status}</span></td>
                      <td>{s.depositCredits} ⚡</td>
                      <td>{s.settlement?.amountDue != null ? `${s.settlement.amountDue} ⚡` : '—'}</td>
                    </tr>
                  ))}
                  {sessions.length === 0 && <EmptyRow cols={6} label="No sessions recorded yet." />}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === 'payouts' && (
          <>
            <div style={{ display: 'flex', gap: 24, marginBottom: 40 }}>
              <MetricCard title="Pending Payout Requests" value={hosts.filter((h) => h.earnedCredits > 0).length} trend="Requires Action" alert={hosts.some((h) => h.earnedCredits > 0)} />
              <MetricCard title="Total Credits Owed" value={`${hosts.reduce((a, h) => a + h.earnedCredits, 0)} ⚡`} trend={`₹${hosts.reduce((a, h) => a + h.earnedCredits, 0)}`} />
            </div>

            <div className="glass-panel" style={{ padding: 24 }}>
              <h3 style={{ marginBottom: 20 }}>Active Host Ledger</h3>
              <div className="data-table-wrapper">
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>Host ID</th>
                      <th>Name</th>
                      <th>Earned Credits</th>
                      <th>Value (INR)</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {hosts.map((host) => (
                      <tr key={host.id}>
                        <td><div style={{ fontWeight: 600 }}>{host.id}</div></td>
                        <td>{host.name || <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                        <td><div style={{ fontWeight: 700, color: 'var(--brand-primary)' }}>{host.earnedCredits} ⚡</div></td>
                        <td>₹{host.earnedCredits}</td>
                        <td>
                          {host.earnedCredits > 0 ? (
                            <button
                              className="btn btn-primary"
                              style={{ padding: '6px 12px', fontSize: '0.85rem' }}
                              onClick={() => handleCreatePayout(host.id, host.earnedCredits)}
                            >
                              Initiate Payout
                            </button>
                          ) : (
                            <span className="badge badge-warning">No balance</span>
                          )}
                        </td>
                      </tr>
                    ))}
                    {hosts.length === 0 && <EmptyRow cols={5} label="No host data found." />}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function statusBadge(status) {
  if (status === 'settled') return 'badge-success';
  if (status === 'active') return 'badge-success';
  if (status === 'lock_failed' || status === 'refunded_after_activation_failure') return 'badge-danger';
  return 'badge-warning';
}

function EmptyRow({ cols, label }) {
  return (
    <tr>
      <td colSpan={cols} style={{ textAlign: 'center', padding: '40px 20px', color: 'var(--text-muted)' }}>
        {label}
      </td>
    </tr>
  );
}

function NavItem({ icon, label, active, onClick }) {
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px',
        borderRadius: 12, cursor: 'pointer', transition: 'all 0.2s ease',
        background: active ? 'rgba(255, 255, 255, 0.6)' : 'transparent',
        color: active ? 'var(--brand-primary)' : 'var(--text-secondary)',
        fontWeight: active ? 600 : 500,
        boxShadow: active ? '0 2px 4px rgba(0,0,0,0.02)' : 'none',
      }}
    >
      {icon}
      {label}
    </div>
  );
}

function MetricCard({ title, value, trend, alert }) {
  return (
    <div className="glass-card" style={{ flex: 1, minWidth: 200, display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', fontWeight: 600 }}>{title}</div>
      <div style={{ fontSize: '2.5rem', fontWeight: 800, color: 'var(--text-primary)', letterSpacing: '-1px' }}>{value}</div>
      <div style={{ fontSize: '0.85rem', color: alert ? 'var(--danger)' : 'var(--success)', fontWeight: 600 }}>
        {trend}
      </div>
    </div>
  );
}
