const SENSITIVE_KEY_PATTERN =
  /(?:^|[_-])(access[_-]?token|refresh[_-]?token|authorization|auth|cookie|credential|secret|password|oauth|api[_-]?key)(?:$|[_-])/i;

export function redactSensitive(value: unknown, depth = 0): unknown {
  if (depth > 8) {
    return '[Max depth]';
  }

  if (value === null || value === undefined) {
    return value;
  }

  if (typeof value === 'string') {
    return value.length > 5000 ? `${value.slice(0, 5000)}...[truncated]` : value;
  }

  if (typeof value !== 'object') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.slice(0, 200).map((item) => redactSensitive(item, depth + 1));
  }

  const redacted: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      redacted[key] = '[REDACTED]';
      continue;
    }

    redacted[key] = redactSensitive(nested, depth + 1);
  }

  return redacted;
}

export function safeJsonStringify(value: unknown): string {
  try {
    return JSON.stringify(redactSensitive(value));
  } catch {
    return JSON.stringify({ error: 'Unable to serialize payload' });
  }
}

export function safeJsonParse<T>(value: string | null | undefined, fallback: T): T {
  if (!value) {
    return fallback;
  }

  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}
