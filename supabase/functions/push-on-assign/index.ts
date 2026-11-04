import { admin, caller, preflight, respond } from '../_shared/invites.ts';
import { verifiedSessionId } from '../issue-certificate/request.ts';
import { createSender } from './fcm.ts';
import { handle, type PushEvent } from './handler.ts';

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  let sender: ReturnType<typeof createSender> | undefined;
  const result = await handle(req, {
    async authenticate(request) {
      const current = await caller(request);
      if (!current) return null;
      // Invoke the caller-context helper before any privileged database call.
      const context = await current.client.rpc('selected_context');
      if (context.error || !context.data?.length) return null;
      let session: string;
      try { session = verifiedSessionId(request.headers.get('authorization')!.replace(/^Bearer\s+/i, '')); }
      catch { return null; }
      return async (event: PushEvent) => {
        const { data, error } = await admin.rpc('claim_push_recipients', {
          p_user: current.id, p_session: session, p_event: event.event,
          p_course: event.event === 'course_available' ? event.course_id : null,
          p_company: event.event === 'course_available' ? event.company_id ?? null : null,
          p_certificate: event.event === 'certificate_issued' ? event.certificate_id : null,
        });
        if (error) throw Error('Unavailable');
        return data;
      };
    },
    async send(token, event, courseId) {
      sender ??= createSender(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON') ?? '');
      return sender(token, event, courseId);
    },
    async cleanup(token) {
      await admin.from('fcm_tokens').delete().eq('user_id', token.user_id)
        .eq('token', token.token).eq('updated_at', token.updated_at);
    },
  });
  return respond(req, result.body, result.status);
});
