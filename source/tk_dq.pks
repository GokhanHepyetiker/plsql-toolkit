create or replace package tk_dq authid definer as
  /**
   * Declarative data quality rules for ERP tables.
   *
   * Rules are stored in TK_DQ_RULES; run_checks evaluates them and stores one result per
   * rule in TK_DQ_RESULTS. A failing rule never stops the run: SQL errors are recorded
   * with status ERROR.
   *
   * Rule types (p_rule_param in brackets):
   *   NOT_NULL                      column must not be null
   *   UNIQUE                        non-null values must be unique
   *   REGEX     [pattern]           non-null values must match the regular expression
   *   RANGE     [min..max]          numeric values must be within the range (either bound may be empty)
   *   IN_LIST   [A,B,C]             non-null values must be one of the listed values
   *   VALIDATOR [TCKN|VKN|IBAN|...] non-null values must pass tk_validate.check_value
   *   CUSTOM    [sql predicate]     predicate that identifies BAD rows, e.g. "received_qty > quantity".
   *                                 Treated as trusted configuration: only administrators should add rules.
   *
   * Errors: -20120 table not found, -20121 column not found, -20122 invalid rule type,
   *         -20123 invalid rule parameter, -20124 rule not found.
   */

  procedure add_rule (
    p_rule_name   in varchar2,
    p_table_name  in varchar2,
    p_rule_type   in varchar2,
    p_column_name in varchar2 default null,
    p_rule_param  in varchar2 default null,
    p_severity    in varchar2 default 'ERROR',
    p_description in varchar2 default null,
    p_owner       in varchar2 default user
  );

  procedure remove_rule (p_rule_name in varchar2);

  procedure set_active (p_rule_name in varchar2, p_active in boolean);

  /** WHERE-clause predicate that selects the rows violating the rule. */
  function violation_predicate (p_rule_name in varchar2) return varchar2;

  /**
   * Runs all active rules (optionally only for one table) and returns the run id.
   * Results are inserted but not committed.
   */
  function run_checks (p_table_name in varchar2 default null, p_owner in varchar2 default user) return number;

  /** One row per rule of a run, failed and errored rules first. */
  procedure run_summary (p_run_id in number, p_result out sys_refcursor);

  /** Offending rows (ROW_ID plus all columns of the table) for a rule. */
  procedure violations (p_rule_name in varchar2, p_result out sys_refcursor, p_max_rows in pls_integer default 100);
end tk_dq;
/
