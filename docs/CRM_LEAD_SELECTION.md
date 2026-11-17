# Lead selection and stable lead IDs (CRM groundwork)

Status: implemented on the results page (`frontend/lib/core/lead_selection.dart`, used by `results_screen.dart`). No CRM is built and no lead data changes. Bigger picture: `CRM_PRODUCT_IMPLEMENTATION_PLAN.md`.

## Selection ids

Each lead gets one selection id, in this order:

| Id | When | Stability |
|---|---|---|
| `lead:<lead_id>` | The lead has `lead_id` (or `id` on admin reads). | The results-row primary key. Stable for the life of the lead and unique across all searches. **The only id a CRM import may use.** |
| `key:<job_id>:<lead_key>` | No `lead_id`, but a `lead_key`. | The per-business dedupe key, unique within one search. Stable across reloads of that search. |
| `row:<job_id>:<maps url>` or `row:<job_id>:<name>\|<phone>\|<address>` | Older servers, or live results before they are stored. | Built from the lead's content. **Not an identity**: it changes if the content changes. If two leads get the same id, the later ones get `#2`, `#3`, … so ticking one never ticks another. |

The selection belongs to **one search**. Opening another search clears it. Filtering, sorting, switching between cards and table, and reloading the same search leave it alone. Leads that disappear on reload are dropped from it. The UI keeps the two counts apart: "3 selected · 12 shown of 40 · 1 not shown". Bulk actions (Export CSV, Export JSON, Copy) work on **all** selected leads, including ones the filters hide. They keep the original website URL.

## Why `lead_id` and not `lead_key`

- `lead_id` points to exactly one stored row, so the server can check ownership (`results.job_id` → `jobs.user_id`) without trusting any business data from the client.
- `lead_key` identifies a *business* inside one search. The same Google place found by two searches has the same key twice, with two different `lead_id`s. That makes it useful for dedupe hints, but it is not an address for a row.
- Content fallbacks exist only so selection and export keep working on older data. A CRM action must be disabled for leads without `lead_id` (`LeadSelection.selectedWithoutLeadId(all) > 0`).

## What a future "Add to CRM" would send

```json
POST /api/crm/import
{ "job_id": "<uuid>", "result_ids": [101, 102, 140], "idempotency_key": "<uuid>" }
```

`result_ids` = `LeadSelection.selectedLeadIds(allLeads)`: numeric, de-duplicated, in list order. The server loads the rows itself and snapshots them. Business fields from the client are never trusted. Note on naming: the CRM plan calls the field `result_id`, while the API now sends `lead_id`. They are the same value, so pick one name before the CRM endpoint exists.

## Open questions for the owner

1. **Dedupe across searches**: if the same place (same `lead_key` / Google place) is added from a second search, should it link to the existing CRM record automatically, be flagged as a possible match (the plan's default), or be added again?
2. **Ownership**: if the same business appears in two users' searches (or two workspaces), is the CRM record per user, per workspace, or shared? The plan says never dedupe across workspaces. Please confirm that this applies to users in the same organisation too.
3. **Deletion**: deleting a search deletes its `results` rows, so their `lead_id`s go away. Should CRM records keep a snapshot with a dangling source link (the plan's choice)? Should deleting a search warn when its leads are in the CRM?
4. **Live results**: should "Add to CRM" stay disabled while a search runs, until every lead has a stored `lead_id`?
5. **Select all leads in a search**: is "all N leads" (a server-side import by `job_id`) wanted next to "selected leads", or only explicit selections?
