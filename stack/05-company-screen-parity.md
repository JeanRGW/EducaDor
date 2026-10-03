# Company-manager screen parity

Visual comparison against `../Figma_Educador/screens/ca-*.png`. Presentation uses
company-scoped repositories/views. The follow-up data integration adds guarded
RPCs in `20261002000001_company_data.sql` without new tables or product rules.

| Prototype | App entry point | Changes |
|---|---|---|
| `ca-dashboard.png` | Início (`/empresa/home`) | White identity header, teal initials/bell treatment, exact metric counts, six-month participation chart and company-wide employee highlights. |
| `ca-employees.png` | Funcionários (`/empresa/funcionarios`) | White search/filter header, compact Outfit names, teal badges, progress above its caption, circular invite action. Pending invitations remain visible. |
| `ca-add-employee.png` | Funcionários → + (`/empresa/employee/add`) | Compact uppercase labels, rounded fields, teal action, shared typography and spacing. |
| `ca-reports.png` | Relatórios (`/empresa/relatorios`) | Header context strip, department-completion bars inside a card, regulatory placeholder panel and deferred export actions. |
| `ca-profile.png` | Perfil (`/empresa/perfil`) | White company header, 72px outlined avatar, live company name/CNPJ, employee-count badge, compact menu and red logout action. |

The existing content catalog and the company-gestor directory also use the same
compact teal treatment. Company-gestor management stays under Profile, not a main
tab. Catalog switches still control employee availability; managers never read
lessons or write learning progress. Platform and employee experiences retain
their own screens.

## Intentional differences from the static prototype

* `company_employees` searches names/departments server-side before deterministic
  50-row pagination and returns exact total/matching counts. The list stays lazy
  and loads additional pages on request. Dashboard/profile counts are not derived
  from a visible page. Highlights cover the whole company, not a limited list or
  fictional recent activity.
* Leave status has no business rule/schema and remains unavailable. Repository
  responses map to unknown status: cards omit status badges and the directory
  shows a total enrollment count, not an active-employee filter/count. Last activity
  comes from the employee's latest progress update in the active company; absent
  activity says "Nenhuma atividade registrada". A null completion is "Sem dados",
  not a completed or zero-percent training result.
* Completion is the existing current snapshot, not a monthly engagement delta.
  Active courses respect all three content gates; certificate totals are actual
  retained issued rows in the company. Monthly participation counts distinct
  current employees with latest progress updates in each São Paulo calendar month,
  zero-filling six months. The current month is partial; there is no immutable
  activity history. No prototype numbers or chart samples are shown as live data.
* Reports use the existing guarded `completion_by_dept` view with 50-row pages.
  The context strip says "Conclusão atual", not "Últimos 30 dias": a date selector
  would falsely imply a period filter on that view. Regulatory/renewal indicators
  and PDF/CSV exports remain unavailable and exports are disabled.
* Adding an employee remains invitation-only: name, e-mail, department and job
  title are sent to `invite-member`. Phone, birth date and address from the
  prototype are omitted because the invite contract does not accept them.
* Profile retains company-gestor management and role switching. Unimplemented
  menu items report their availability instead of silently doing nothing. No
  24/7 support promise, notifications or settings backend is introduced.

Company providers track signed-in identity and active context; switching company
discards old results, search and page state. Reads stay in repositories and existing
database authorization remains the security boundary. Failed reads require an
explicit retry, with no automatic polling.

## Scalability follow-up

Before supporting large companies, benchmark both RPCs in an isolated database
with representative employee, lesson and progress volumes. Use
`EXPLAIN (ANALYZE, BUFFERS)` on their underlying queries in the validated manager
context; a top-level PL/pgSQL function call alone does not expose inner plans.
The directory computes completion for up to 50 employees per request, but exact
counts/search scan all company members and dashboard aggregates cover the whole
company. Small response sizes do not bound database work.

Existing indexes cover company/role memberships and progress timestamps; the
progress primary key covers user/company/lesson lookups. If measured plans justify
it, evaluate progress indexes on `(company_id, updated_at)` for participation and
`(user_id, company_id, updated_at desc)` for latest activity, then consider reusing
the eligible lesson set/denominator in completion queries. Literal substring
search using `strpos(lower(...))` cannot use an ordinary B-tree index; any indexed
search replacement must preserve case-insensitive literal `%`/`_` matching.
Do not add speculative indexes, extensions or query rewrites without measurement.

## Verification

`test/company_screen_parity_test.dart` covers hierarchy, invitation/navigation
preservation, null/exact-count data, server search, employee/report pagination, context switching,
explicit retry and layouts at 320/418/1000px with 1.0/1.8 text scaling.
`test/company_parity_repositories_test.dart` verifies RPC response shapes,
company filters, page bounds and role guards. `supabase/tests/company_data.sql`
verifies isolation, gates, historical completion, scoped activity, zero-filled
months, literal search, stable pages, revoked/inactive contexts and empty states.

Deployment order: obtain operator approval, apply the new migration to staging,
then deploy Flutter. Until applied, the new dashboard/directory requests show an
explicit retryable error rather than falling back to mocks. No staging changes
or deployment are implied by source changes or isolated local SQL tests.
