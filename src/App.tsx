import { Activity, Gauge, Home, KeyRound, Settings, Sparkles } from 'lucide-react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { AppState, Notice, PageName } from './types/app';
import { Overview } from './pages/Overview';
import { Quota } from './pages/Quota';
import { Skills } from './pages/Skills';
import { ActivityPage } from './pages/Activity';
import { SettingsPage } from './pages/Settings';

const pages: Array<{ name: PageName; icon: typeof Home }> = [
  { name: 'Overview', icon: Home },
  { name: 'Quota', icon: Gauge },
  { name: 'Skills', icon: Sparkles },
  { name: 'Activity', icon: Activity },
  { name: 'Settings', icon: Settings }
];

const fallbackState: AppState = {
  config: { localServerPort: 3987 },
  server: { listening: false, host: '127.0.0.1', port: 3987, error: 'Electron preload unavailable' },
  skills: [],
  events: []
};

export default function App(): JSX.Element {
  const [activePage, setActivePage] = useState<PageName>('Overview');
  const [state, setState] = useState<AppState>(fallbackState);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const api = typeof window !== 'undefined' ? window.abar : undefined;

  const refreshState = useCallback(async () => {
    if (!api) {
      return;
    }
    const nextState = (await api.getState()) as AppState;
    setState(nextState);
  }, [api]);

  useEffect(() => {
    void refreshState();
    const timer = window.setInterval(() => void refreshState(), 15_000);
    const dispose = api?.onNavigate((route) => {
      if (pages.some((page) => page.name === route)) {
        setActivePage(route as PageName);
      }
    });
    return () => {
      window.clearInterval(timer);
      dispose?.();
    };
  }, [api, refreshState]);

  const actions = useMemo(
    () => ({
      refreshState,
      refreshQuota: async () => {
        if (!api) return;
        setBusy('quota');
        try {
          const quota = await api.quota.refresh();
          setNotice({
            tone: quota.error ? 'error' : 'success',
            message: quota.error ? quota.error : 'Quota refreshed.'
          });
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
      setProjectPath: async (projectPath: string) => {
        if (!api) return;
        await api.config.setProjectPath(projectPath);
        setNotice({ tone: 'success', message: 'Project path saved.' });
        await refreshState();
      },
      chooseProjectPath: async () => {
        if (!api) return;
        const result = await api.config.chooseProjectPath();
        if (result.ok) {
          setNotice({ tone: 'success', message: 'Project path saved.' });
          await refreshState();
        }
      },
      copyHookSnippet: async () => {
        if (!api) return;
        await api.hooks.copyInstallSnippet();
        setNotice({ tone: 'success', message: 'Hook snippet copied.' });
      },
      openPath: async (targetPath: string) => {
        if (!api) return;
        const result = await api.shell.openPath(targetPath);
        if (!result.ok) {
          setNotice({ tone: 'error', message: result.error ?? 'Unable to open path.' });
        }
      }
    }),
    [api, refreshState]
  );

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">C</div>
          <div>
            <strong>Abar</strong>
            <span>Codex monitor</span>
          </div>
        </div>
        <nav className="nav-list" aria-label="Main navigation">
          {pages.map((page) => {
            const Icon = page.icon;
            return (
              <button
                key={page.name}
                type="button"
                className={activePage === page.name ? 'nav-item active' : 'nav-item'}
                onClick={() => setActivePage(page.name)}
              >
                <Icon size={17} />
                <span>{page.name}</span>
              </button>
            );
          })}
        </nav>
        <div className="sidebar-footer">
          <KeyRound size={15} />
          <span>Local only</span>
        </div>
      </aside>

      <main className="content">
        <header className="topbar">
          <div>
            <p className="eyebrow">Codex-only status bar app</p>
            <h1>{activePage}</h1>
          </div>
          {notice ? (
            <button className={`notice ${notice.tone}`} type="button" onClick={() => setNotice(null)}>
              {notice.message}
            </button>
          ) : null}
        </header>

        {activePage === 'Overview' ? (
          <Overview state={state} actions={actions} busy={busy} />
        ) : null}
        {activePage === 'Quota' ? <Quota state={state} actions={actions} busy={busy} /> : null}
        {activePage === 'Skills' ? <Skills state={state} actions={actions} busy={busy} /> : null}
        {activePage === 'Activity' ? <ActivityPage state={state} actions={actions} busy={busy} /> : null}
        {activePage === 'Settings' ? <SettingsPage state={state} actions={actions} busy={busy} /> : null}
      </main>
    </div>
  );
}
