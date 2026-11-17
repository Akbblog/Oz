# Admin work deferred until after CRM

Decided 2026-11-18 (owner). The current admin dashboard stays as it is for this release.
Source plan: `ADMIN_UX_PLAN.md` (kept untracked in the worktree).

## Shipped in this release (feat/user-ux-finishing)
- A1: profile edits never change roles; explicit owner-only `PUT /api/admin/users/{id}/role`.
- A2: staff act only on accounts ranked strictly below them; owners cannot act on other owners.
- Deleting users and toggling live payments are owner-only.
- Credit grants: positive whole number (max 1,000,000) and a reason required; admins grant only to
  support/user accounts; owners also to admins and themselves, never to another owner. The same rule
  applies when approving credit requests (bulk approval skips accounts the actor can't credit).

## Not in this release (do after CRM, in this order)
1. Remove the hard-coded "Active Sessions" / "API Health" tiles; add `/api/admin/system-status` and a status strip.
2. Jobs tab with bookmarkable admin routes.
3. Destructive-action hierarchy (Suspend secondary, Delete behind type-to-confirm), honest error states,
   pricing-tier visibility.
4. Admin jobs API (server search, stuck filter) and job detail page.
5. User detail page; support read-only UI.
6. Time-windowed KPIs, activity CSV export, audit completeness, revenue correctness, admin accessibility.

## Explicitly out of scope until decided again
- Credit deductions (signed adjustments).
- Expanding support permissions (support stays read-only; contact-data masking undecided).
- Admin timezone for "today" and admin navigation redesign.
- Four-eyes approvals (`/api/admin/approvals/*` remains a dormant stub).
