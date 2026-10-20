import { admin, caller, preflight, respond } from '../_shared/invites.ts';
import { certificateRequest, verifiedSessionId } from './request.ts';

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  const current = await caller(req);
  if (!current) return respond(req, { error: 'Authentication required' }, 401);
  try {
    const { courseId, companyId } = certificateRequest(await req.json());
    // This JWT has been verified by caller(); session_id is not accepted from the body.
    const jwt = req.headers.get('authorization')!.replace(/^Bearer\s+/i, '');
    const sessionId = verifiedSessionId(jwt);
    const { data, error } = await admin.rpc('issue_employee_certificate', {
      p_user: current.id, p_session: sessionId, p_company: companyId, p_course: courseId,
    });
    if (error) {
      if (error.message === 'Course incomplete') return respond(req, { error: 'Course incomplete' }, 409);
      return respond(req, { error: 'Certificate unavailable' }, error.message === 'Forbidden' ? 403 : 409);
    }
    return respond(req, { id: data });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
