# Company-manager screen parity

Visual comparison against `../Figma_Educador/screens/ca-*.png`. This branch
changes presentation using existing company-scoped repositories/views; it does
not add migrations or implement deferred product features.

| Prototype | App entry point | Changes |
|---|---|---|
| `ca-dashboard.png` | Início (`/empresa/home`) | White identity header, teal initials/bell treatment, two-column metric cards, participation panel and compact employee highlights. |
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

* The existing `employee_completion` RPC returns at most 50 employees. The list
  searches only that result, explicitly discloses the cap when reached, and
  renders a count of `50+` rather than claiming an exact company total. Highlights
  are the highest current completions within that list, not a company-wide
  ranking or fictional recent activity. Full directory pagination/search remains
  backend work.
* The current RPC has no leave-status or last-activity fields. Leave filtering is
  marked unavailable, and missing activity is not labeled "active now". A null
  completion is "Sem dados", not a completed or zero-percent training result.
* Completion is the existing current snapshot, not a monthly engagement delta.
  Active-course/certificate totals and monthly participation remain clearly
  marked "Em breve"; no prototype numbers or chart samples are shown as live data.
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
discards old results and report pages. Reads stay in repositories and existing
database authorization remains the security boundary. Failed reads require an
explicit retry, with no automatic polling.

## Verification

`test/company_screen_parity_test.dart` covers hierarchy, invitation/navigation
preservation, null/capped data, search, report pagination, context switching,
explicit retry and layouts at 320/418/1000px with 1.0/1.8 text scaling.
`test/company_parity_repositories_test.dart` verifies existing response shapes,
company filters, department page bounds and role guards. No staging migration
or deployment is required or implied by these source changes.
