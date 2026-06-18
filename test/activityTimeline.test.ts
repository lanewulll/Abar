import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ActivityTimeline } from '../src/components/ActivityTimeline';
import type { CodexEvent } from '../src/types/app';

const event: CodexEvent = {
  id: 'event-1',
  agent: 'codex',
  eventType: 'PostToolUse',
  toolName: 'Bash',
  status: 'success',
  payload: { command: 'echo hello' },
  createdAt: '2026-06-18T08:31:19.000Z'
};

describe('ActivityTimeline', () => {
  it('renders preview events as non-interactive rows by default', () => {
    const markup = renderToStaticMarkup(React.createElement(ActivityTimeline, { events: [event] }));

    expect(markup).not.toContain('<details');
    expect(markup).not.toContain('<summary');
    expect(markup).not.toContain('<pre');
    expect(markup).toContain('PostToolUse Bash');
  });

  it('can render expandable event details when requested', () => {
    const markup = renderToStaticMarkup(React.createElement(ActivityTimeline, { events: [event], interactive: true }));

    expect(markup).toContain('<details');
    expect(markup).toContain('<summary');
    expect(markup).toContain('<pre');
  });
});
