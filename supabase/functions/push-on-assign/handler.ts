export type PushEvent = { event: 'course_available'; course_id: string; company_id?: string } |
  { event: 'certificate_issued'; certificate_id: string };
export type Token = { user_id: string; token: string; updated_at: string };
export type Claim = { suppressed: boolean; tokens: Token[]; course_id?: string };
export type Dependencies = {
  authenticate(req: Request): Promise<((event: PushEvent) => Promise<Claim>) | null>;
  send(token: string, event: PushEvent, courseId: string): Promise<'sent' | 'invalid' | 'failed'>;
  cleanup(token: Token): Promise<void>;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function parseEvent(value: unknown): PushEvent {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Invalid');
  const v = value as Record<string, unknown>;
  const valid = (x: unknown): x is string => typeof x === 'string' && uuid.test(x);
  if (v.event === 'course_available' && valid(v.course_id) &&
      (v.company_id === undefined || valid(v.company_id)) &&
      Object.keys(v).every((k) => ['event', 'course_id', 'company_id'].includes(k))) {
    return { event: v.event, course_id: v.course_id, ...(v.company_id ? { company_id: v.company_id as string } : {}) };
  }
  if (v.event === 'certificate_issued' && valid(v.certificate_id) &&
      Object.keys(v).every((k) => ['event', 'certificate_id'].includes(k))) {
    return { event: v.event, certificate_id: v.certificate_id };
  }
  throw Error('Invalid');
}
export async function handle(req: Request, deps: Dependencies): Promise<{ status: number; body: unknown }> {
  const claim = await deps.authenticate(req);
  if (!claim) return { status: 401, body: { error: 'Authentication required' } };
  let event: PushEvent;
  try {
    const text = await req.text();
    if (text.length > 1024) throw Error('Invalid');
    event = parseEvent(JSON.parse(text));
  } catch { return { status: 400, body: { error: 'Invalid request' } }; }
  let result: Claim;
  try { result = await claim(event); } catch { return { status: 403, body: { error: 'Unavailable' } }; }
  const tokens = result.tokens.slice(0, 100);
  let sent = 0, failed = 0;
  let index = 0;
  async function worker() {
    while (index < tokens.length) {
      const token = tokens[index++];
      try {
        const outcome = await deps.send(token.token, event, result.course_id!);
        if (outcome === 'sent') sent++;
        else {
          failed++;
          if (outcome === 'invalid') { try { await deps.cleanup(token); } catch { /* best effort */ } }
        }
      } catch { failed++; }
    }
  }
  await Promise.all(Array.from({ length: Math.min(tokens.length, 5) }, () => worker()));
  return { status: 200, body: { event: event.event, sent, failed, truncated: result.tokens.length > 100,
    suppressed: result.suppressed } };
}
