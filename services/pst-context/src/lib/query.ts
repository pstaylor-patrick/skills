const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

export function parseLimit(value: string | null): number {
  if (value === null) return DEFAULT_LIMIT;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 1) return DEFAULT_LIMIT;
  return Math.min(n, MAX_LIMIT);
}

export function escapeLikePattern(pattern: string): string {
  return pattern.replace(/[%_\\]/g, "\\$&");
}

export function parseJsonBody(raw: unknown):
  | {
      ok: true;
      data: Record<string, unknown>;
    }
  | { ok: false } {
  if (typeof raw === "object" && raw !== null && !Array.isArray(raw)) {
    return { ok: true, data: raw as Record<string, unknown> };
  }
  return { ok: false };
}
