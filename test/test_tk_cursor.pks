create or replace package test_tk_cursor as
  --%suite(tk_cursor - SYS_REFCURSOR helpers)
  --%suitepath(toolkit)

  --%aftereach
  procedure reset_nls;

  --%test(to_csv writes a header and one line per row)
  procedure csv_basic;

  --%test(to_csv quotes delimiters, quotes and line breaks)
  procedure csv_quoting;

  --%test(to_csv numbers do not depend on NLS_NUMERIC_CHARACTERS)
  procedure csv_numbers_nls;

  --%test(to_csv writes dates and timestamps as ISO-8601)
  procedure csv_dates;

  --%test(to_csv supports another delimiter, no header and NULLs)
  procedure csv_delimiter_nulls;

  --%test(to_csv returns only the header for an empty cursor)
  procedure csv_empty;

  --%test(to_csv handles CLOB columns)
  procedure csv_clob;

  --%test(to_csv handles results larger than 32K)
  procedure csv_large;

  --%test(to_csv rejects an invalid delimiter with -20132)
  --%throws(-20132)
  procedure csv_invalid_delimiter;

  --%test(to_csv rejects a cursor that is not open with -20132)
  --%throws(-20132)
  procedure csv_closed_cursor;

  --%test(to_json returns an array of objects with typed values)
  procedure json_basic;

  --%test(to_json writes NULL, dates and escapes strings)
  procedure json_types;

  --%test(to_json returns [] for an empty cursor)
  procedure json_empty;

  --%test(safe_order_by builds the clause from the whitelist)
  procedure order_by_valid;

  --%test(safe_order_by falls back to the default)
  procedure order_by_default;

  --%test(safe_order_by rejects columns that are not whitelisted with -20130)
  --%throws(-20130)
  procedure order_by_not_allowed;

  --%test(safe_order_by rejects SQL injection attempts with -20131)
  --%throws(-20131)
  procedure order_by_injection;

  --%test(Report pattern: dynamic sort + bind variables + CSV export)
  procedure report_pattern;
end test_tk_cursor;
/
