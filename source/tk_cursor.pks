create or replace package tk_cursor authid definer as
  /**
   * Helpers for SYS_REFCURSOR based reports.
   *
   * to_csv / to_json consume (and close) any ref cursor, regardless of its columns, by describing
   * it with DBMS_SQL. Output is NLS independent: numbers always use '.' as the decimal separator
   * (important for Turkish NLS settings) and dates are ISO-8601.
   *
   * safe_order_by builds an ORDER BY clause for dynamic report sorting from a whitelist, so user
   * input never reaches the SQL text.
   *
   * Errors: -20130 sort column not allowed, -20131 invalid sort expression, -20132 invalid argument.
   */

  /**
   * Converts a cursor to RFC 4180 style CSV.
   * p_delimiter: field separator (',' or ';' for Excel with Turkish regional settings)
   * p_header:    'Y' to include column names as the first line
   */
  function to_csv (
    p_cursor      in out sys_refcursor,
    p_delimiter   in varchar2 default ',',
    p_header      in varchar2 default 'Y',
    p_line_break  in varchar2 default chr(10)
  ) return clob;

  /**
   * Converts a cursor to a JSON array of objects: [{"COL":value,...},...].
   * Numbers stay numbers, NULLs become JSON null, CLOBs are truncated to 32767 characters.
   */
  function to_json (p_cursor in out sys_refcursor) return clob;

  /**
   * Returns 'order by <col> [asc|desc], ...' for a requested sort such as 'name desc, price'.
   * p_allowed: comma separated whitelist of sortable columns/aliases (case-insensitive).
   * p_default: used when p_requested is null; validated the same way.
   */
  function safe_order_by (
    p_requested in varchar2,
    p_allowed   in varchar2,
    p_default   in varchar2 default null
  ) return varchar2;
end tk_cursor;
/
