const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function certificateRequest(input: unknown): { courseId: string; companyId: string } {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid request');
  const { courseId, companyId } = input as Record<string, unknown>;
  if (typeof courseId !== 'string' || typeof companyId !== 'string' || !uuid.test(courseId) || !uuid.test(companyId)) {
    throw new Error('Invalid request');
  }
  return { courseId, companyId };
}

// Decode only after caller() verifies this bearer token. Never use request-body claims.
export function verifiedSessionId(jwt: string): string {
  const encoded = jwt.split('.')[1]?.replaceAll('-', '+').replaceAll('_', '/');
  if (!encoded) throw new Error('Session required');
  const payload = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')));
  if (typeof payload.session_id !== 'string' || !uuid.test(payload.session_id)) throw new Error('Session required');
  return payload.session_id;
}
