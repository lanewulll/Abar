import { Copy, FolderOpen, Save } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { AppState, HookInstallPrompt } from '../types/app';

type SettingsProps = {
  state: AppState;
  actions: {
    setProjectPath: (projectPath: string) => Promise<void>;
    chooseProjectPath: () => Promise<void>;
    copyHookSnippet: () => Promise<void>;
  };
  busy: string | null;
};

export function SettingsPage({ state, actions }: SettingsProps): JSX.Element {
  const [projectPath, setProjectPath] = useState(state.config.projectPath ?? '');
  const [installPrompt, setInstallPrompt] = useState<HookInstallPrompt | null>(null);

  useEffect(() => {
    setProjectPath(state.config.projectPath ?? '');
  }, [state.config.projectPath]);

  useEffect(() => {
    let mounted = true;
    void window.abar.hooks.getInstallPrompt().then((value) => {
      if (mounted) {
        setInstallPrompt(value as HookInstallPrompt);
      }
    });
    return () => {
      mounted = false;
    };
  }, [state.config.localServerPort]);

  return (
    <div className="page-stack">
      <section className="surface">
        <h2>Project</h2>
        <div className="field-row">
          <input value={projectPath} onChange={(event) => setProjectPath(event.target.value)} placeholder="/Users/name/project" />
          <button type="button" title="Choose folder" onClick={actions.chooseProjectPath}>
            <FolderOpen size={16} />
            Choose
          </button>
          <button type="button" title="Save project path" onClick={() => actions.setProjectPath(projectPath)}>
            <Save size={16} />
            Save
          </button>
        </div>
      </section>

      <section className="surface">
        <h2>Local Server</h2>
        <div className="inline-stats">
          <span>{state.server.listening ? 'Listening' : 'Offline'}</span>
          <span>{state.server.host}:{state.server.port}</span>
        </div>
        {state.server.error ? <p className="error-text">{state.server.error}</p> : null}
      </section>

      <section className="surface">
        <div className="section-header">
          <div>
            <h2>Codex Hook Install Prompt</h2>
            <p className="muted">{installPrompt?.targetFile ?? '~/.codex/hooks.json'}</p>
          </div>
          <button type="button" onClick={actions.copyHookSnippet}>
            <Copy size={16} />
            Copy Install
          </button>
        </div>
        <pre className="snippet">{installPrompt?.promptText ?? 'Loading install prompt...'}</pre>
      </section>
    </div>
  );
}
