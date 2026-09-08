# Tidy Data: daily data work without formulas

Tidy Data should earn its place by making a repeated spreadsheet job faster and easier to verify. The initial audience is someone who regularly receives CSV exports and uses lookups, joins, find-and-replace, or reconciliation to prepare another usable file. Willingness to pay is a hypothesis to test with real recurring work, not something a redesigned menu can guarantee.

## The implemented experience

Choose a job → select tables and columns → preview → inspect exceptions → export every result row, or use the result as another table.

| Job | Outcome | Trust behavior |
| --- | --- | --- |
| Lookup | Add a reference value to every main row | Exact keys, unmatched status, rejects duplicate or missing reference keys |
| Replace | Replace an entire value or literal text within a column | Case-sensitive, keeps original value and replacement status |
| Append | Stack all imported tables by column name | Missing columns become null; each row retains its source filename |
| Join | Keep all main rows, matching rows, or all rows from both tables | Explicit file roles and keys; repeated keys produce every matching pair |
| Reconcile | Added, removed, changed, and optionally unchanged records | Unique complete keys, shared fields side by side, main = before and reference = after |
| Analyze | Column quality, row counts, sum, average, minimum, maximum | Full-data calculations; numeric summaries reject nonnumeric values and exclude missing values |

CSV imports are local snapshots, with text values preserved so identifiers such as `001` survive import. Previews show up to 250 rows; counts and exports use the full result. Changing workflow settings marks an existing result out of date and disables export until another preview runs. Failures clear the old result so it cannot be mistaken for the new answer.

Saved workflows persist the operation, column choices, and rules, including find/replace text. They do not persist files, source IDs, datasets, or a multi-step pipeline. Load new tables, load the workflow, verify the table roles, then preview. Saved settings live in local app preferences.

“Use result as a table” creates a full local intermediate table for the next job, with Tidy's generated columns renamed to `result_…` to avoid metadata collisions. The sample workspace demonstrates orders, customers, missing customer matches, and an updated order export for reconciliation.

Custom AI questions remain optional and use the configured provider. The AI flow sends schema, prompts, prior query context, and a result preview of up to 30 rows and 16 columns to that provider. Guided workflows do not call AI.

## Commercial direction

The value proposition is “finish your recurring reconciliation with fewer manual steps and visible exceptions.” Avoid selling AI access as the main reason to subscribe.

A proposed paid edition should center on saved multi-step workflows, replacing source files and rerunning, persistent projects, richer exception resolution, and an exportable run history. The current saved settings and intermediate tables establish the interaction, but do not yet implement those paid capabilities. There is no billing or paywall in this change.

Let users complete a real import-to-export job in evaluation. Ask for payment only after they have experienced a successful result and a repeated use case. Choose a price through interviews and an actual paid pilot; do not infer demand from demo enthusiasm.

## Validate before pricing or expanding scope

Recruit 5–10 people who do the target work at least weekly. Observe them completing one of their current jobs in their spreadsheet, then the same job in Tidy. Record time, manual corrections, confidence in exceptions, and whether the exported result is usable without reopening a spreadsheet.

Suggested decision gates, to be treated as initial targets rather than measured results:

- At least 8 of 10 users finish a real task without coaching.
- Median completion time is at least 50% lower than their existing workflow.
- At least 6 of 10 return with a new export within two weeks.
- At least 3 of 10 accept a paid pilot at the tested price.
- Reconciliation totals agree with the user's independently verified baseline; investigate every discrepancy.

Do not add content analytics or collect imported data to measure this. Start with observed sessions and optional feedback. Instrument operational events only after defining consent and retention.

## Next priorities and current limits

1. Excel workbook and pasted TSV support, including sheet selection. This version accepts CSV files only.
2. Persisted projects with source replacement and reusable multi-step runs. Current datasets disappear when the app closes.
3. Composite keys, explicit whitespace/case normalization, duplicate-resolution policies, and numeric/date reconciliation tolerances. Current matching and comparison are exact and case-sensitive.
4. Searchable/filterable exceptions, richer lookup column selection, and mapping-table replacements. Current lookup returns one column; repeated steps can add more.
5. Charting and large-data performance targets validated against representative files. This version offers tabular analysis and keeps imported tables in memory.

AI-authored queries still use the existing SQL validation approach. Before treating arbitrary AI queries as production-hardened, add engine-level isolation and stronger query validation, with dedicated security tests.
