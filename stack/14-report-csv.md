# CSV report export

CSV uses UTF-8 with BOM, semicolon separators and comma decimal marks for Brazilian spreadsheet defaults. Fields are quoted and spreadsheet formula prefixes are neutralized.

Completion reports use dedicated export RPCs, `gestor_completion_export(p_after)` and `company_completion_export(p_company, p_after)`. Each response contains at most 50 rows, the total matching count and a page ordered by immutable UUID. Aggregates are computed only for the 50 companies or employees in that page, using the same access rules and completion semantics as `completion_by_company` and `employee_completion`. Every page is one database snapshot and re-checks the authorized gestor or own-company manager context, including MFA.

The client reads every page with a strict `id > cursor` cursor, rejects duplicate IDs, changed totals, short non-final pages and missing rows, then reads the complete report a second time. The file is written only when both passes have identical IDs and identical exported field values. Any mismatch aborts with a retry message. Exports are capped at 1,000 companies or 1,000 employees; the cap and the retry behavior are visible in the reports UI.

Two passes detect inserts, deletions and changes that produce different exported values between reads. They are not an atomic snapshot: a value that changes and reverts between both reads is not detectable, and rows changed after the second pass can differ from the saved file. The platform activity section is a separate snapshot with its own explicit period and can reflect changes after the completion passes. Each read is bounded, but function-local `statement_timeout` does not limit the outer request; the cap and fail-closed checks are the practical protection at this scale.

Leaving a report route or changing identity/context cancels a pending export before opening the save dialog. The period picker is disabled while export is in progress. A native save dialog already opened cannot be recalled by the app.
