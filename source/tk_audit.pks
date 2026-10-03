create or replace package tk_audit authid definer as
  /**
   * Generates row-level audit triggers from the data dictionary.
   *
   * Every INSERT / UPDATE / DELETE on an audited table writes one row to TK_AUDIT_LOG:
   *   - old_values / new_values are JSON objects of the audited columns
   *   - UPDATEs only log the columns that actually changed (null-safe comparison);
   *     an UPDATE that changes no audited column is not logged at all
   *   - changed_by is the application user (CLIENT_IDENTIFIER) when the ERP sets it,
   *     otherwise the database session user
   *
   * Supported column types: character, numeric, DATE, TIMESTAMP (all variants) and RAW.
   * LOBs, LONG, XMLTYPE, object and virtual columns are skipped.
   *
   * The audit row is written in the same transaction as the change, so a rollback
   * removes both.
   *
   * Errors: -20110 table not found, -20111 invalid column list, -20112 trigger compilation failed,
   *         -20113 invalid purge argument.
   */

  /** Name of the generated trigger for a table: TK_AUD_<TABLE>. */
  function trigger_name (p_table_name in varchar2) return varchar2;

  /**
   * Returns the CREATE TRIGGER statement without executing it (for review or deployment scripts).
   * p_columns:         comma separated list of columns to audit (default: all supported columns)
   * p_exclude_columns: comma separated list of columns to ignore (e.g. LAST_UPDATE_DATE)
   */
  function generate_trigger (
    p_table_name      in varchar2,
    p_owner           in varchar2 default user,
    p_columns         in varchar2 default null,
    p_exclude_columns in varchar2 default null
  ) return clob;

  /** Generates and compiles the audit trigger (replacing an existing one). */
  procedure enable_audit (
    p_table_name      in varchar2,
    p_owner           in varchar2 default user,
    p_columns         in varchar2 default null,
    p_exclude_columns in varchar2 default null
  );

  /** Drops the audit trigger. Does nothing if the table is not audited. */
  procedure disable_audit (p_table_name in varchar2, p_owner in varchar2 default user);

  /** 'Y' if an enabled audit trigger exists for the table, otherwise 'N'. */
  function is_enabled (p_table_name in varchar2, p_owner in varchar2 default user) return varchar2;

  /** Called by the generated triggers. Not intended to be called directly. */
  procedure log_change (
    p_owner      in varchar2,
    p_table_name in varchar2,
    p_operation  in varchar2,
    p_pk_value   in varchar2,
    p_old_values in clob,
    p_new_values in clob
  );

  /** Change history of a table, optionally for one primary key value, oldest first. */
  procedure history (
    p_table_name in varchar2,
    p_result     out sys_refcursor,
    p_pk_value   in varchar2 default null,
    p_owner      in varchar2 default user
  );

  /** Deletes audit rows older than the given number of days. Does not commit. */
  procedure purge (p_older_than_days in pls_integer, p_deleted out pls_integer);
end tk_audit;
/
