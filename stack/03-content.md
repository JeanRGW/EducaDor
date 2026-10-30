# Courses, modules and lessons

The catalog contains courses. Each course contains ordered modules; each module
contains ordered lessons. New courses start paused, available to all companies
once the gestor releases them in the catalog. Audience and company pause
preferences remain course-level gates. Content edits preserve catalog IDs,
assignments and progress; the pre-production database wipe is a separate operation.

Gestors create a course, edit its metadata, add/rename modules, and add/edit
lessons. Lesson types are YouTube video, MP3 audio, PDF, plain-text reading,
single-answer quizzes, and animation. All lesson formats support optional accompanying plain text; reading
lessons require text. Course management separates course data from the module
list, and each module has a dedicated lesson management screen. Catalog cards
show module and lesson counts, including modules without lessons.

Quizzes contain 1–50 questions with 2–6
options; the editor creates four options per question. Learners must answer all
questions correctly in the UI. As with video, completion is client-reported for
the MVP, not an assessment/anti-cheating guarantee. Changing content preserves
existing completion and points; lesson types cannot change after creation.

Module and lesson cards offer accessible up/down controls to change sibling order.
A gestor-only mutation locks the parent, swaps adjacent items, and normalizes
duplicate legacy positions. It does
not replace content IDs or change progress. Loaded pages refresh after a move;
the last loaded item can move down across a pagination boundary.
Repository reads explicitly order positions and IDs ascending (the Dart client
defaults to descending), matching the mutation order and append-at-end defaults.

Platform gestors can permanently delete courses, modules, or lessons after an
explicit confirmation. The guarded `delete_content` RPC is declared in
`supabase/schemas/public/functions/delete_content.sql`.
Deletes cascade descendants and their progress, and course deletion also removes
assignments and certificates. Derived employee points decrease when completed
lessons are removed (balances may become negative after previous redemptions).
Uploaded objects are retained for operator-managed cleanup. Company managers and
employees cannot invoke the deletion RPC. Pausing remains the non-destructive
alternative.

The visual lesson type (`animation`, labeled “Imagem / Animação”) also accepts a
single PNG/JPEG/WebP image with optional supporting text. Still images display
with zoom and no animation controls. Existing private Storage MIME types and
download authorization are reused unchanged.

Animation accepts either an original GIF (not flattened by cover processing)
or 2–100 PNG/JPEG/WebP frames. Gestors can move frames up/down and set a shared
frame duration of 100–10000 ms. The learner can pause/resume or step through
frames. Reduced-motion preferences start playback paused; leaving the foreground
pauses animation. Audio supports seek/resume and company-scoped checkpoints.

## Storage and deployment

- Content definitions live in `supabase/schemas/public/` (formats, supporting text,
  single images, counts, ordering and deletion). Follow [Database workflow](07-database.md)
  to generate/review migrations; hosted changes still require operator approval.
- Deploy the updated `storage-upload-url` and new `storage-download-url` functions.
  Both authenticate the caller. Only the selected gestor context can upload.
- Configure `STORAGE_BUCKET_PRIVATE=educador-private` along with the existing
  `STORAGE_S3_ENDPOINT`, `STORAGE_S3_REGION`, `STORAGE_S3_ACCESS_KEY_ID`, and
  `STORAGE_S3_SECRET_ACCESS_KEY` function secrets. Keep them out of Flutter.
- Configure the S3 endpoint's CORS for the deployed app origins and PUT/GET,
  including the Content-Type header, as required for existing cover uploads.
- PDFs, MP3s, GIFs and frames use private `lessons/<uuid>.<extension>` objects.
  The file cap remains 50 MiB. GIF/image MIME types are added to the private bucket.
- Downloads authorize the lesson using the caller's JWT and RLS before signing
  its stored keys. Company managers cannot request lesson files. A whole frame
  sequence is signed in one call; URLs expire after one hour and are cached for
  55 minutes per Auth token/selected context in memory. Like all bearer URLs,
  already-issued URLs remain valid until expiry after access is revoked.
- Unattached uploads from cancelled/failed edits can remain in private Storage;
  include them in operator quota reviews. There is no automatic deletion job.

Verification: `flutter analyze`, `flutter test`, release web build, and
`supabase/tests/lesson_formats.sql` on an isolated database after migrations.
