import { certificateRequest, verifiedSessionId } from './request.ts';
const companyId = 'a7000000-0000-4000-8000-000000000001';
const courseId = 'b7000000-0000-4000-8000-000000000001';
function assert(condition: boolean) { if (!condition) throw new Error('Assertion failed'); }
function rejects(action: () => unknown) { try { action(); } catch { return; } throw new Error('Invalid input accepted'); }
Deno.test('certificate input ignores forged user/session/progress claims', () => {
  const request = certificateRequest({companyId,courseId,userId:'admin',sessionId:'forged',completed:true});
  assert(JSON.stringify(request) === JSON.stringify({courseId,companyId}));
});
Deno.test('invalid certificate targets are rejected', () => {
  for (const input of [null,[],{}, {companyId,courseId:'../other'}, {companyId:null,courseId}]) rejects(() => certificateRequest(input));
});
Deno.test('session comes from the previously verified JWT', () => {
  const payload = btoa(JSON.stringify({session_id:companyId,sub:courseId})).replaceAll('=','');
  assert(verifiedSessionId(`header.${payload}.signature`) === companyId);
  rejects(() => verifiedSessionId('missing'));
  rejects(() => verifiedSessionId(`header.${btoa('{}')}.signature`));
});
