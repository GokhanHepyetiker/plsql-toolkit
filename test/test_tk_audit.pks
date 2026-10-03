create or replace package test_tk_audit as
  --%suite(tk_audit - generated audit triggers)
  --%suitepath(toolkit)
  --%rollback(manual)

  --%afterall
  procedure cleanup;

  --%beforeeach
  procedure reset;

  --%test(generate_trigger returns DDL covering supported columns only)
  procedure generates_ddl;

  --%test(enable_audit creates an enabled trigger)
  procedure enable_creates_trigger;

  --%test(INSERT logs the new values as JSON)
  procedure logs_insert;

  --%test(UPDATE logs only the changed columns with old and new values)
  procedure logs_update_changed_only;

  --%test(UPDATE without a real change is not logged)
  procedure skips_noop_update;

  --%test(NULL to value and value to NULL are detected as changes)
  procedure null_safe_comparison;

  --%test(DELETE logs the old values)
  procedure logs_delete;

  --%test(DATE and TIMESTAMP values are stored in ISO-8601 format)
  procedure iso_dates;

  --%test(Excluded columns are neither logged nor trigger a log row)
  procedure exclude_columns;

  --%test(A column list restricts auditing and uses UPDATE OF)
  procedure include_columns;

  --%test(Composite primary keys are logged as A|B)
  procedure composite_pk;

  --%test(changed_by is the CLIENT_IDENTIFIER set by the ERP application)
  procedure client_identifier;

  --%test(A rollback removes the audit row together with the change)
  procedure rollback_removes_audit;

  --%test(disable_audit drops the trigger, stops logging and is idempotent)
  procedure disable_stops_logging;

  --%test(history returns the changes of one row in order)
  procedure history_cursor;

  --%test(purge deletes only rows older than the given days)
  procedure purge_old_rows;

  --%test(Unknown table raises -20110)
  --%throws(-20110)
  procedure unknown_table;

  --%test(Unknown column raises -20111)
  --%throws(-20111)
  procedure unknown_column;

  --%test(Unsupported column type in the column list raises -20111)
  --%throws(-20111)
  procedure unsupported_column;
end test_tk_audit;
/
