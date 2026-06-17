import { Copy, FolderOpen, Save } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { AppState, HookInstallSnippet } from '../types/app';

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
  const [snippet, setSnippet] = useState<HookInstallSnippet | null>(null);

  useEffect(() => {
    setProjectPath(state.config.projectPath ?? '');
  }, [state.config.projectPath]);

  useEffect(() => {
    let mounted = true;
    void window.abar.hooks.getInstallSnippet().then((value) => {
      if (mounted) {
        setSnippet(value as HookInstallSnippet);
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
            <h2>Codex Hook</h2>
            <p className="muted">{snippet?.targetFile ?? '~/.codex/hooks.json'}</p>
          </div>
          <button type="button" onClick={actions.copyHookSnippet}>
            <Copy size={16} />
            Copy
          </button>
        </div>
        <pre className="snippet">{snippet?.hooksJson ?? 'Loading hook snippet...'}</pre>
      </section>
    </div>
  );
}
