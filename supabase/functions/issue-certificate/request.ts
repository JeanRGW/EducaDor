const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function certificateRequest(input: unknown): { courseId: string; companyId: string } {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid request');
  const { courseId, companyId } = input as Record<string, unknown>;
  if (typeof courseId !== 'string' || typeof companyId !== 'string' || !uuid.test(courseId) || !uuid.test(companyId)) {
    throw new Error('Invalid request');
  }
  return { courseId, companyId };
}

// Kept as a re-export so existing certificate tests and imports stay stable.
export { verifiedSessionId } from '../_shared/session.ts';
