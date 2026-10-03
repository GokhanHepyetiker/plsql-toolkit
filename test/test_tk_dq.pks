create or replace package test_tk_dq as
  --%suite(tk_dq - data quality rules)
  --%suitepath(toolkit)
  --%rollback(manual)

  --%beforeall
  procedure create_table;

  --%afterall
  procedure drop_table;

  --%beforeeach
  procedure add_rules;

  --%aftereach
  procedure cleanup;

  --%test(Each rule type counts the expected violations)
  procedure counts_violations;

  --%test(Rules without violations pass and the run header is summarised)
  procedure run_header;

  --%test(A broken CUSTOM rule is recorded as ERROR and the run continues)
  procedure broken_rule_does_not_stop_run;

  --%test(Inactive rules are skipped)
  procedure inactive_rules_skipped;

  --%test(run_checks can be limited to one table)
  procedure filter_by_table;

  --%test(violations returns the offending rows)
  procedure violations_cursor;

  --%test(run_summary returns one row per rule)
  procedure summary_cursor;

  --%test(RANGE predicates are NLS independent)
  procedure range_predicate_nls;

  --%test(add_rule updates an existing rule with the same name)
  procedure add_rule_upserts;

  --%test(Unknown table raises -20120)
  --%throws(-20120)
  procedure unknown_table;

  --%test(Unknown column raises -20121)
  --%throws(-20121)
  procedure unknown_column;

  --%test(Unknown rule type raises -20122)
  --%throws(-20122)
  procedure unknown_rule_type;

  --%test(Invalid RANGE parameter raises -20123)
  --%throws(-20123)
  procedure invalid_range;

  --%test(Unknown validator raises -20123)
  --%throws(-20123)
  procedure unknown_validator;

  --%test(Invalid regular expression raises -20123)
  --%throws(-20123)
  procedure invalid_regex;

  --%test(CUSTOM predicate with a semicolon raises -20123)
  --%throws(-20123)
  procedure custom_with_semicolon;

  --%test(Removing an unknown rule raises -20124)
  --%throws(-20124)
  procedure remove_unknown_rule;
end test_tk_dq;
/
