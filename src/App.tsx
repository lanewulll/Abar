import {
  AlertCircle,
  Bolt,
  CheckCircle2,
  Copy,
  FolderOpen
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { AppState, HookInstallPrompt, Notice } from './types/app';
import type { AgentRun, UsageWindow } from '../backend/types';
import {
  formatAgentRunDuration,
  formatAgentRunLine,
  formatPercent,
  formatReset,
  mainMetricTiles,
  noticePlacement,
  quotaWindow,
  quotaRefreshNotice,
  serverSettingsSummary,
  shouldAutoRefreshQuota
} from './utils/format';

const fallbackState: AppState = {
  config: { localServerPort: 3987 },
  server: { listening: false, host: '127.0.0.1', port: 3987, error: 'Electron preload unavailable' },
  skills: [],
  events: [],
  agentRuns: []
};

export default function App(): JSX.Element {
  const [state, setState] = useState<AppState>(fallbackState);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(() => window.location.hash === '#settings');
  const [projectPath, setProjectPath] = useState('');
  const [installPrompt, setInstallPrompt] = useState<HookInstallPrompt | null>(null);
  const autoQuotaRefreshRequested = useRef(false);
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
      return undefined;
    }
    return api.onStateChanged(() => {
      void refreshState();
    });
  }, [api, refreshState]);

  useEffect(() => {
    const syncSettingsHash = () => {
      setSettingsOpen(window.location.hash === '#settings');
    };
    window.addEventListener('hashchange', syncSettingsHash);
    syncSettingsHash();
    return () => window.removeEventListener('hashchange', syncSettingsHash);
  }, []);

  useEffect(() => {
    if (!api) {
      return;
    }
    let mounted = true;
    void api.hooks.getInstallPrompt().then((value) => {
      if (mounted) {
        setInstallPrompt(value as HookInstallPrompt);
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
          const nextNotice = quotaRefreshNotice(quota, false);
          setNotice(nextNotice);
          await refreshState();
        } finally {
          setBusy(null);
        }
      },
      refreshQuotaSilently: async () => {
        if (!api) return;
        setBusy('quota');
        try {
          const quota = await api.quota.refresh();
          const nextNotice = quotaRefreshNotice(quota, true);
          setNotice(nextNotice);
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
        await api.hooks.copyInstallPrompt();
        setNotice({ tone: 'success', message: 'Install prompt copied. Paste it into Codex, then trust in /hooks.' });
      }
    }),
    [api, projectPath, refreshState]
  );

  useEffect(() => {
    if (!api || autoQuotaRefreshRequested.current || !shouldAutoRefreshQuota(state.quota) || busy === 'quota') {
      return;
    }
    autoQuotaRefreshRequested.current = true;
    void actions.refreshQuotaSilently();
  }, [actions, api, busy, state.quota]);

  const placement = noticePlacement(notice);
  const metrics = mainMetricTiles(state.skills.length, state.agentRuns.length);
  const serverSummary = serverSettingsSummary(state.server);
  const fiveHour = quotaWindow(state.quota, '5h');
  const weekly = quotaWindow(state.quota, 'weekly');

  return (
    <main className="popover-shell">
      <div className="popover-arrow" />
      {placement === 'header' && notice ? <CompactNotice notice={notice} onDismiss={() => setNotice(null)} /> : null}

      <div className="popover-content">
        {placement === 'content' && notice ? (
          <button className={`notice ${notice.tone}`} type="button" onClick={() => setNotice(null)}>
            {notice.tone === 'error' ? <AlertCircle size={15} /> : <CheckCircle2 size={15} />}
            <span>{notice.message}</span>
          </button>
        ) : null}

        <section className="quota-stack">
          <CompactQuotaCard title="5h limit" icon={<LimitIcon />} window={fiveHour} error={state.quota?.error} />
          <CompactQuotaCard title="Weekly" icon={<WeeklyIcon />} window={weekly} error={state.quota?.error} />
        </section>

        <section className="metric-grid">
          {metrics.map((metric) => (
            <MetricTile key={metric.key} icon={metricIcon(metric.key)} label={metric.label} value={metric.value} />
          ))}
        </section>

        <section className="panel-block activity-block">
          <AgentRunList runs={state.agentRuns} />
        </section>

        {settingsOpen ? (
          <section className="panel-block settings-block">
            <div className="section-header">
              <div>
                <h2>Setup</h2>
                <p>{installPrompt?.targetFile ?? '~/.codex/hooks.json'}</p>
              </div>
              <button className="mini-button" type="button" onClick={actions.copyHookSnippet}>
                <Copy size={14} />
                Copy install
              </button>
            </div>
            <button className="full-button prompt-button" type="button" onClick={actions.copyHookSnippet}>
              <Copy size={15} />
              Copy install prompt
            </button>
            <ServerSettingsRow summary={serverSummary} />
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

    </main>
  );
}

function CompactNotice({ notice, onDismiss }: { notice: Notice; onDismiss: () => void }): JSX.Element {
  return (
    <button className={`compact-notice ${notice.tone}`} type="button" onClick={onDismiss} title={notice.message}>
      {notice.tone === 'error' ? <AlertCircle size={13} /> : <CheckCircle2 size={13} />}
      <span>{notice.message}</span>
    </button>
  );
}

function metricIcon(key: 'skills' | 'events'): JSX.Element {
  return key === 'skills' ? <SkillsIcon /> : <EventsIcon />;
}

function IconSvg({ children }: { children: ReactNode }): JSX.Element {
  return (
    <svg
      className="app-icon"
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

function LimitIcon(): JSX.Element {
  return (
    <IconSvg>
      <path d="M3.2 9.7a4.8 4.8 0 0 1 9.6 0" />
      <path d="M8 8.8 10.4 6" />
      <path d="M3.8 5.9 2.7 4.8" />
      <path d="M12.2 5.9 13.3 4.8" />
      <path d="M8 4.9V3.3" />
    </IconSvg>
  );
}

function WeeklyIcon(): JSX.Element {
  return (
    <IconSvg>
      <path d="M4.1 5.1H2.7v5.8h1.4" />
      <path d="M11.9 5.1h1.4v5.8h-1.4" />
      <path d="M6.2 11.1 4.9 8l1.3-3.1" />
      <path d="M9.8 4.9 11.1 8l-1.3 3.1" />
      <path d="M7.4 10.9 8.6 5.1" />
    </IconSvg>
  );
}

function SkillsIcon(): JSX.Element {
  return (
    <IconSvg>
      <path d="M8 2.8v3" />
      <path d="M8 10.2v3" />
      <path d="M2.8 8h3" />
      <path d="M10.2 8h3" />
      <path d="M4.8 4.8 6 6" />
      <path d="M10 10l1.2 1.2" />
      <circle cx="8" cy="8" r="1.35" />
    </IconSvg>
  );
}

function EventsIcon(): JSX.Element {
  return (
    <IconSvg>
      <path d="M2.6 8h2l1.1-3.4 2.1 7 1.5-5.2 1.1 1.6h3" />
      <circle cx="5.7" cy="4.6" r=".55" />
      <circle cx="7.8" cy="11.6" r=".55" />
    </IconSvg>
  );
}

function ServerSettingsRow({ summary }: { summary: ReturnType<typeof serverSettingsSummary> }): JSX.Element {
  return (
    <div className={`server-settings-row ${summary.tone}`}>
      <Bolt size={15} />
      <div>
        <strong>Server</strong>
        <p>{summary.detail}</p>
      </div>
      <span>{summary.value}</span>
    </div>
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
        <div className="quota-copy">
          <strong>{title}</strong>
          <p>{window ? formatReset(window) : error ?? 'Not configured'}</p>
        </div>
      </div>
      <span>{formatPercent(window?.usedPercent)}</span>
      <div className="meter">
        <div style={{ width: `${Math.max(0, Math.min(100, used))}%` }} />
      </div>
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

function AgentRunList({ runs }: { runs: AgentRun[] }): JSX.Element {
  if (runs.length === 0) {
    return <p className="empty-state">No agent runs recorded yet.</p>;
  }

  return (
    <div className="agent-run-list">
      {runs.map((run) => (
        <div className={`agent-run-row ${run.status}`} key={run.sessionId}>
          <span className={`event-dot ${run.status === 'running' ? '' : 'success'}`} />
          <div>
            <strong>{formatAgentRunLine(run)}</strong>
            <p>{run.sessionId.slice(0, 8)}</p>
          </div>
          <time>{formatAgentRunDuration(run)}</time>
        </div>
      ))}
    </div>
  );
}
