const SENSITIVE_KEYS = ['authorization', 'password', 'secret', 'token', 'api_key', 'apikey', 'cookie'];
const OMITTED_KEYS = ['prompt', 'payload', 'hook_payload', 'transcript'];

function keyMatches(key, candidates) {
  const normalized = String(key).toLowerCase();
  return candidates.some((candidate) => normalized.includes(candidate));
}

export function redactPath(value, home) {
  if (typeof value !== 'string' || !home) {
    return value;
  }
  const shortened = value === home ? '~' : value.startsWith(`${home}/`) ? `~${value.slice(home.length)}` : value;
  return shortened
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, '[redacted-email]')
    .replace(/\bBearer\s+[^\s"',}]+/gi, 'Bearer [redacted]');
}

export function redactDiagnosticValue(value, home, key = '') {
  if (keyMatches(key, SENSITIVE_KEYS)) {
    return '[redacted]';
  }
  if (keyMatches(key, OMITTED_KEYS)) {
    return '[omitted]';
  }
  if (Array.isArray(value)) {
    return value.map((item) => redactDiagnosticValue(item, home));
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([childKey, childValue]) => [
        childKey,
        redactDiagnosticValue(childValue, home, childKey)
      ])
    );
  }
  return redactPath(value, home);
}
