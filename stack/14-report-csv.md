# CSV report export

CSV uses UTF-8 with BOM, semicolon separators and comma decimal marks for Brazilian spreadsheet defaults. Fields are quoted and spreadsheet formula prefixes are neutralized.

Exports deliberately use only a single bounded response per report section. The company employee RPC returns a count and at most 50 employees in the same database snapshot; it fails rather than exporting when the count differs. The platform completion RPC returns at most 50 rows without a count, so 50 rows is ambiguous and export fails (up to 49 companies supported). The separate platform activity section is a second snapshot; its period is explicit and it can reflect changes after the completion snapshot. Each section is internally consistent, but the combined file is not an atomic cross-section snapshot. Multi-page exports require new guarded, bounded snapshot infrastructure; deduplication or a second pass cannot ensure consistency under concurrent changes. No schema or database changes are included.

Leaving a report route or changing identity/context cancels a pending export before opening the save dialog. A native save dialog already opened cannot be recalled by the app.
