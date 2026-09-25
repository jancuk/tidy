# Tidy Data: filtering, sorting, and larger CSVs

Import a CSV with **Add CSV**, then open **Filter & sort** above the table. These controls work on source previews and workflow results.

- Search all columns, or add column conditions with **All conditions** / **Any condition**. Search is combined with the condition group using AND. Text matches are literal (including `%`, `_`, and quotes) and case insensitive unless the condition enables **Case sensitive**. Empty conditions include both missing values and empty strings.
- Add sort levels in priority order. Choose **Text**, **Number**, or **Date / time** for each level, then ascending or descending. The up arrow moves a sort earlier. Date sorting expects year-month-day values, optionally with a time. Empty values and invalid numeric/date values sort last.
- Click a column header to sort its text values; click again to reverse. Shift-click adds or reverses a secondary sort. Use **Filter & sort** to change the interpretation to numbers or dates.
- Hide columns in **Visible columns**, drag headers to rearrange them, or drag header boundaries to resize. The native table keeps its headers visible while scrolling. Right-click to copy a cell; select rows and press Command-C to copy their visible columns as tab-separated text.
- Use the previous/next buttons to browse 250 rows at a time. Filtering and sorting use the complete dataset, including rows beyond the current page.
- **Export CSV** includes every matching row in the selected sort order. It includes all columns in their original order, including hidden columns. **Use result as a table** also keeps the filtered, sorted result. **Reset view** clears search, filters, sorts, and hidden columns.

Applying invalid controls leaves the last successful view and export available. Selecting a source or running a new workflow resets the table controls. Saved workflow recipes continue to save workflow configuration; they do not save these table controls. Workflow summary counts describe the result before table filters.

## Performance changes

CSV format detection samples up to 20,480 rows instead of inspecting the full file for detection. Import still reads every row with strict error handling and preserves CSV values as text, including leading zeros. Import and queries run on the DuckDB actor, away from the main actor.

The grid uses AppKit table cells that can be reused, with a bounded page of data and constant-time column lookup. UI status changes do not reload the grid. Very long cells display at most 2,000 characters, with up to 10,000 in the tooltip; copying, filtering, and exporting retain the full value.

Source previews reuse the imported row count. Paging and sorting reuse the current count. Workflow results are materialized once per run so paging, filtering, and export do not repeat joins or aggregations. The workspace retains one workflow snapshot, replaced on the next workflow run. Imported tables and that snapshot remain in memory for the workspace session.

A local debug test with a 12,768,751-byte CSV containing 60,000 rows measured about 0.85 s for import, 13 ms for first-page retrieval, 0.51 s for filtering/sorting, and 0.25 s for the next sorted page. These are data-engine timings from one run, not a UI frame-rate benchmark or a comparison with Google Sheets. Wider tables, larger files, and complex workflows can have different costs.

## Verification

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TidyTests/DataWorkspaceTests \
  -only-testing:TidyTests/DataTableBrowsingTests

xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' -xcconfig Local.xcconfig \
  -only-testing:TidyUITests/DataWorkspaceUITests
```
