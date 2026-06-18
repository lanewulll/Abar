import {
  Activity,
  AlertCircle,
  BatteryCharging,
  Bolt,
  CheckCircle2,
  Copy,
  FolderOpen,
  Gauge,
  Power,
  RefreshCcw,
  RotateCw,
  Settings,
  Sparkles
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { AppState, HookInstallSnippet, Notice } from './types/app';
import type { ActivityStatus, UsageWindow } from '../backend/types';
import { ActivityTimeline } from './components/ActivityTimeline';
import {
  compactPath,
  formatPercent,
  formatReset,
  latestToolCall,
  quotaWindow,
  statusFromEvents
} from './utils/format';

const fallbackState: AppState = {
  config: { localServerPort: 3987 },
  server: { listening: false, host: '127.0.0.1', port: 3987, error: 'Electron preload unavailable' },
  skills: [],
  events: []
};

export default function App(): JSX.Element {
  const [state, setState] = useState<AppState>(fallbackState);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [projectPath, setProjectPath] = useState('');
  const [snippet, setSnippet] = useState<HookInstallSnippet | null>(null);
  const api = typeof window !== 'undefined' ? window.abar : undefined;

  const refreshState = useCallback(async () => {
    if (!api) {
      return;
    }
    const nextState = (await api.getState()) as AppState;
    setState(nextState);
    setProjectPath(nextState.config.projectPath ?? '');
  }, [api]);

  useEffect(() => {
    void refreshState();
    const timer = window.setInterval(() => void refreshState(), 12_000);
    return () => window.clearInterval(timer);
  }, [refreshState]);

  useEffect(() => {
    if (!api) {
      return;
    }
    let mounted = true;
    void api.hooks.getInstallSnippet().then((value) => {
      if (mounted) {
        setSnippet(value as HookInstallSnippet);
      }
    });
    return () => {
      mounted = false;
    };
  }, [api, state.config.localServerPort]);

  const actions = useMemo(
    () => ({
      refreshQuota: async () => {
        if (!api) return;
        setBusy('quota');
        try {
          const quota = await api.quota.refresh();
          setNotice({ tone: quota.error ? 'error' : 'success', message: quota.error ? quota.error : 'Quota refreshed.' });
          await refreshState();
        } finally {
          setBusy(null);
        }
      },
      rescanSkills: async () => {
        if (!api) return;
        setBusy('skills');
        try {
          const result = await api.skills.rescan();
          setNotice({
            tone: result.errors?.length ? 'error' : 'success',
            message: result.errors?.length
              ? `Scanned with ${result.errors.length} warning(s).`
              : `Scanned ${result.skills.length} skill(s).`
          });
          await refreshState();
        } finally {
          setBusy(null);
        }
      },
      chooseProjectPath: async () => {
        if (!api) return;
        const result = await api.config.chooseProjectPath();
        if (result.ok) {
          setNotice({ tone: 'success', message: 'Project saved.' });
          await refreshState();
        }
      },
      saveProjectPath: async () => {
        if (!api) return;
        await api.config.setProjectPath(projectPath);
        setNotice({ tone: 'success', message: 'Project saved.' });
        await refreshState();
      },
      copyHookSnippet: async () => {
        if (!api) return;
        await api.hooks.copyInstallSnippet();
        setNotice({ tone: 'success', message: 'Hook snippet copied.' });
      },
      createTestEvent: async () => {
        if (!api) return;
        setBusy('event');
        try {
          await api.events.createTest();
          setNotice({ tone: 'success', message: 'Test event recorded.' });
          await refreshState();
        } finally {
          setBusy(null);
        }
      },
      quit: async () => {
        if (!api) return;
        await api.quit();
      }
    }),
    [api, projectPath, refreshState]
  );

  const status = statusFromEvents(state.events);
  const recentTool = latestToolCall(state.events);
  const fiveHour = quotaWindow(state.quota, '5h');
  const weekly = quotaWindow(state.quota, 'weekly');

  return (
    <main className="popover-shell">
      <div className="popover-arrow" />
      <header className="popover-header">
        <div>
          <p className="eyebrow">Abar</p>
          <h1>Codex Monitor</h1>
        </div>
        <button
          className="icon-button glass-button"
          type="button"
          title="Settings"
          onClick={() => setSettingsOpen((value) => !value)}
        >
          <Settings size={18} />
        </button>
      </header>

      <div className="popover-content">
        {notice ? (
          <button className={`notice ${notice.tone}`} type="button" onClick={() => setNotice(null)}>
            {notice.tone === 'error' ? <AlertCircle size={15} /> : <CheckCircle2 size={15} />}
            <span>{notice.message}</span>
          </button>
        ) : null}

        <section className="status-panel">
          <div>
            <p className="eyebrow">Status</p>
            <h2>Codex is {status.toLowerCase()}</h2>
            <p>
              {recentTool ? `${recentTool.toolName ?? recentTool.eventType} · ${recentTool.eventType}` : 'Waiting for hook events.'}
            </p>
          </div>
          <StatusOrb status={status} />
        </section>

        <section className="quota-stack">
          <CompactQuotaCard title="5h limit" icon={<Gauge size={17} />} window={fiveHour} error={state.quota?.error} />
          <CompactQuotaCard title="Weekly" icon={<BatteryCharging size={17} />} window={weekly} error={state.quota?.error} />
        </section>

        <section className="metric-grid">
          <MetricTile icon={<Sparkles size={16} />} label="Skills" value={String(state.skills.length)} />
          <MetricTile icon={<Activity size={16} />} label="Events" value={String(state.events.length)} />
          <MetricTile
            icon={<Bolt size={16} />}
            label="Server"
            value={state.server.listening ? `${state.server.port}` : 'Off'}
            tone={state.server.listening ? 'good' : 'warn'}
          />
        </section>

        <section className="panel-block activity-block">
          <div className="section-header">
            <div>
              <h2>Recent Activity</h2>
              <p>{compactPath(state.config.projectPath)}</p>
            </div>
            <button className="mini-button" type="button" onClick={actions.createTestEvent} disabled={busy === 'event'}>
              Test
            </button>
          </div>
          <ActivityTimeline events={state.events.slice(0, 4)} />
        </section>

        {settingsOpen ? (
          <section className="panel-block settings-block">
            <div className="section-header">
              <div>
                <h2>Setup</h2>
                <p>{snippet?.targetFile ?? '~/.codex/hooks.json'}</p>
              </div>
              <button className="mini-button" type="button" onClick={actions.copyHookSnippet}>
                <Copy size={14} />
                Copy hook
              </button>
            </div>
            <div className="field-row">
              <input value={projectPath} onChange={(event) => setProjectPath(event.target.value)} placeholder="/Users/name/project" />
              <button className="icon-button" type="button" title="Choose folder" onClick={actions.chooseProjectPath}>
                <FolderOpen size={16} />
              </button>
            </div>
            <button className="full-button" type="button" onClick={actions.saveProjectPath}>
              Save project path
            </button>
          </section>
        ) : null}
      </div>

      <footer className="popover-actions">
        <button type="button" onClick={actions.refreshQuota} disabled={busy === 'quota'}>
          <RefreshCcw size={16} />
          Quota
        </button>
        <button type="button" onClick={actions.rescanSkills} disabled={busy === 'skills'}>
          <RotateCw size={16} />
          Skills
        </button>
        <button type="button" onClick={actions.quit}>
          <Power size={16} />
          Quit
        </button>
      </footer>
    </main>
  );
}

function CompactQuotaCard({
  title,
  icon,
  window,
  error
}: {
  title: string;
  icon: JSX.Element;
  window?: UsageWindow;
  error?: string;
}): JSX.Element {
  const used = window?.usedPercent ?? 0;
  return (
    <article className="quota-strip">
      <div className="quota-label">
        {icon}
        <strong>{title}</strong>
      </div>
      <span>{formatPercent(window?.usedPercent)}</span>
      <div className="meter">
        <div style={{ width: `${Math.max(0, Math.min(100, used))}%` }} />
      </div>
      <p>{window ? formatReset(window) : error ?? 'Not configured'}</p>
    </article>
  );
}

function MetricTile({
  icon,
  label,
  value,
  tone
}: {
  icon: JSX.Element;
  label: string;
  value: string;
  tone?: 'good' | 'warn';
}): JSX.Element {
  return (
    <article className={`metric-tile ${tone ?? ''}`}>
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

function StatusOrb({ status }: { status: ActivityStatus }): JSX.Element {
  return (
    <div className={`status-orb ${status.toLowerCase().replace(/\s+/g, '-')}`}>
      <span />
      {status}
    </div>
  );
}
