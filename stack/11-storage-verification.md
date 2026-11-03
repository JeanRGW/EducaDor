# Storage signing verification

## Scope and evidence

This change is local-only verification. **No hosted storage, deployed Edge Function,
production Auth, bucket CORS, or live RLS verification was performed.** Offline
HTTP tests inject authentication and lesson visibility; they prove that handlers
fail closed when those dependencies deny access, not that deployed JWT verification
or SQL policies are correct. Shared `caller()` semantics are unchanged: Auth verifies
the JWT and creates a caller-scoped client. Upload requires that client's active
`selected_context()` to be `gestor`. Download queries each requested lesson under
that client/RLS before signing any of its files. The API still accepts one
`lessonId` and returns `{ urls: { [key]: url } }`, including all image frames.

AWS `client-s3` and `s3-request-presigner` are pinned to `3.1161.0`, resolved from
`npm view <package> version` during implementation (not a guessed version). Each
storage function has a scoped Deno config/lock capturing transitive integrity.
Use frozen locks in checks; update both locks deliberately when upgrading.

## Local checks

Run from the repository root with Deno 2.9.8 (the CI version). The initial
storage checks also passed on Deno 2.9.6:

```bash
deno test supabase/functions/ --ignore=supabase/functions/storage-upload-url/signing_test.ts
deno check --frozen --config supabase/functions/storage-upload-url/deno.json supabase/functions/storage-upload-url/index.ts supabase/functions/storage-upload-url/storage_test.ts supabase/functions/storage-upload-url/signing_test.ts
deno check --frozen --config supabase/functions/storage-download-url/deno.json supabase/functions/storage-download-url/index.ts
deno test --frozen --config supabase/functions/storage-upload-url/deno.json '--allow-env=AWS_*,SMITHY_*,HOME,USERPROFILE,HOMEPATH,HOMEDRIVE,_X_AMZN_TRACE_ID' --allow-sys=osRelease supabase/functions/storage-upload-url/signing_test.ts
node --test supabase/tests/invite_member.test.mjs
```

The general function suite (including storage HTTP/validator tests) runs without
runtime permissions. Only `signing_test.ts` imports the AWS SDK and runs separately
with the scoped frozen upload config. CI checks both locked entrypoints and a
Node regression test asserts this separation and the exact SDK permission flags.

Tests receive **no network, filesystem read, or subprocess permissions**.
Environment access is limited to the listed AWS/Smithy namespaces and home/trace
names; do not run with real AWS credentials in the environment. No Supabase or
`STORAGE_*` secret access is granted. The SDK uses environment/OS release for
configuration and user-agent construction; signing uses explicit fake credentials
and endpoint.
The HTTP cases cover CORS/OPTIONS/methods, unauthenticated and denied active roles,
MIME/prefix/size boundaries, payload validation, per-request lesson authorization,
invalid/private key boundaries, frame limits/deduplication, configuration failure,
and 15-minute PUT / one-hour GET expiration. Real SDK offline tests check signed
Content-Type and Content-Length headers and signatures changing with each value.

## Operator checklist (not executed here)

Only perform these in an explicitly authorized non-production environment:

- [ ] Configure `STORAGE_S3_ENDPOINT`, `STORAGE_S3_REGION`,
  `STORAGE_S3_ACCESS_KEY_ID`, `STORAGE_S3_SECRET_ACCESS_KEY`,
  `STORAGE_BUCKET_PUBLIC`, `STORAGE_BUCKET_PRIVATE` as function configuration/secrets.
  Never put credentials in Flutter, logs, source control, or screenshots.
- [ ] Confirm Supabase-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
  `SUPABASE_SERVICE_ROLE_KEY` exist. Service-role is used by the existing Auth
  verifier only, never for the lesson authorization query.
- [ ] Set `ALLOWED_APP_ORIGINS` (comma-separated exact origins), or fallback
  `APP_ORIGIN`. Confirm permitted preflight advertises POST/OPTIONS and
  `authorization, x-client-info, apikey, content-type`; untrusted origins receive
  no allow-origin. CORS is browser policy, not authentication; non-browser
  requests without Origin must still authenticate.
- [ ] Configure bucket/S3 endpoint CORS independently: exact application origins,
  PUT/GET/HEAD as required, allow Content-Type and relevant browser headers.
  Function CORS does not configure S3 CORS. Do not wildcard credentials/origins.
- [ ] Test real Flutter web and mobile PUT with unchanged Content-Type and exact
  byte length. Verify wrong MIME, wrong length, missing signed headers, altered
  URL/key and expired signatures are rejected by the endpoint. Confirm no
  automatically injected checksum header is needed for these simple PUTs.
- [ ] Browser code cannot set Content-Length (a forbidden header); the browser
  derives it from bytes. HTTP/2/proxies/endpoints may handle it differently.
  Signing proves declared header values are bound, **not** browser interoperability,
  file MIME sniffing, or a universal server-enforced upload size limit. Verify
  endpoint behavior and retain bucket/provider per-object limits. Do not silently
  remove binding to make a failing browser test pass.
- [ ] Test missing/expired/forged JWT and missing active context; active gestor
  upload succeeds, employee/manager upload fails. For downloads test assigned
  employee, unrelated user/company, manager, and every course release/audience/
  company pause gate using actual deployed RLS. Verify multiple frames are signed
  in one function request, all under `lessons/`, maximum 100 keys and one-hour TTL.
- [ ] Confirm private objects cannot be read unsigned and public covers are cached.
  Treat signed URLs as bearer credentials; never log full URLs or JWTs.
- [ ] Verify revocation expectations: a previously issued URL can remain valid
  until expiry even after role/course access is revoked. Signing is not encryption
  and does not validate actual file contents or prevent URL replay/overwrite.

## Deferred dependency follow-ups

Multipart upload changes are deliberately out of scope. Review multipart support,
provider-enforced size constraints, interrupted uploads and cleanup separately.
Real S3-compatible (Supabase now, R2 after endpoint/credential swap) signature,
CORS and browser acceptance remain explicit release gates, not claims made by
these mocked/offline tests. SQL policy hardening is owned by the security stream.
