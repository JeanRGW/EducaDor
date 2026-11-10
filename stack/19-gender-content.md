# Gender-specific lesson content

Gender is an optional presentation preference (`profiles.gender`: `male`, `female`,
or null), never an authorization gate. Existing accounts and lessons remain neutral.
The five-argument `update_own_profile` accepts an explicit nullable `p_gender`; the
four-argument overload preserves it. Both retain the own-account and optional-MFA
guards.

## Authoring and selection

Existing lesson columns store the primary/default version. `content_gender` labels
it, or null means universal content. `alternate_content` optionally stores the
opposite-gender version with the same lesson kind, using `video_id`, `file_key`,
`image_keys`, `frame_ms`, `body`, and `questions`. There is no separate title, kind,
points value, progress row, or certificate contribution per version. Only a tagged
primary can have an alternate. Videos remain YouTube IDs, never uploaded MP4s.

`save_content_lesson` validates both versions before mutation. Omitted new fields
preserve existing configuration for older clients; explicit null clears them.
Clearing the primary tag while an alternate exists requires explicitly removing
the alternate too. Both versions retain the existing typed content constraints;
each version has at most 100 private keys and the full incoming JSON is capped at
500,000 bytes. No upload objects are eagerly deleted when editing a version.

Learners use `employee_lesson_content(p_lesson)` for resolved content and
`employee_lessons` for matching video metadata. The server reads the authenticated
account's profile. A matching alternate is selected when present, otherwise the
primary is selected. Unset profiles use primary. A single male or female version
silently serves everyone. Responses contain the actual selected `content_gender`
and normalized `quiz_json`, never the alternate payload. Existing membership,
active-context, MFA, platform-release, company audience and company-pause checks
remain mandatory. Authors retain raw lesson access through existing gestor RLS.

## Progress and files

`lesson_progress.content_gender` records the last played version. The five-argument
`save_employee_progress` accepts `p_content_gender` and validates an available
version; the four-argument legacy overload records an unknown (null) version.
When that tag differs from selected content, the lesson listing returns resume
position zero. Completion and earned points remain shared and are never reset.
Neutral legacy content retains its existing resume position.
Older cached clients cannot identify the version played: their writes still save
completion, but tagged lessons restart at zero on re-entry, including single-version
lessons. Reopen the updated PWA to restore version-aware resume. This deliberate
compatibility limitation avoids applying an unknown position to the wrong video.

The download Function fetches primary and alternate file references under the
verified caller's root-lesson RLS, validates at most 100 keys per version/200 total,
and signs them in one request. Only the selected version's bytes are downloaded by
the client. Gender versions are not separate confidential audiences.

## Release order

Apply the reviewed generated database migration first, deploy
`storage-download-url` with existing JWT verification next, then publish the
matching PWA after generating its static-shell worker. Old profile/progress RPC
signatures remain compatible. Do not deploy individual feature branches. Hosted
migration application remains operator-approved; local fixtures always roll back.
