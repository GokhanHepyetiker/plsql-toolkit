create or replace package body test_tk_dq as

  function result_of (p_run_id in number, p_rule in varchar2) return tk_dq_results%rowtype is
    l_row tk_dq_results%rowtype;
  begin
    select * into l_row from tk_dq_results where run_id = p_run_id and rule_name = p_rule;
    return l_row;
  end result_of;

  procedure create_table is
  begin
    drop_table;
    execute immediate q'[
      create table tk_t_customer (
        customer_id   number constraint tk_t_customer_pk primary key,
        name          varchar2(100),
        tax_id        varchar2(20),
        iban          varchar2(40),
        email         varchar2(100),
        city          varchar2(50),
        credit_limit  number,
        status        varchar2(10)
      )]';
    -- one row per kind of problem; see counts_violations for the expected results
    execute immediate q'[insert into tk_t_customer values (1, 'Anadolu Kagit', '1234567890', 'TR330006100519786457841326', 'info@anadolu.com', 'ANKARA', 50000, 'ACTIVE')]';
    execute immediate q'[insert into tk_t_customer values (2, 'Ege Ambalaj', '1234567891', 'TR330006100519786457841327', 'ege@', 'IZMIR', -5, 'ACTIVE')]';
    execute immediate q'[insert into tk_t_customer values (3, null, '10000000146', null, 'x@y.com', 'ankara', 2000000, 'PASSIVE')]';
    execute immediate q'[insert into tk_t_customer values (4, 'Marmara Recycling', '1234567890', null, null, 'ISTANBUL', 1000, 'BLOCKED')]';
    commit;
  end create_table;

  procedure drop_table is
  begin
    execute immediate 'drop table tk_t_customer purge';
  exception
    when others then
      if sqlcode != -942 then raise; end if;
  end drop_table;

  procedure add_rules is
  begin
    tk_dq.add_rule('T_NAME_REQUIRED',   'TK_T_CUSTOMER', 'NOT_NULL',  'NAME');
    tk_dq.add_rule('T_ID_REQUIRED',     'TK_T_CUSTOMER', 'NOT_NULL',  'CUSTOMER_ID');
    tk_dq.add_rule('T_TAX_ID_UNIQUE',   'TK_T_CUSTOMER', 'UNIQUE',    'TAX_ID');
    tk_dq.add_rule('T_TAX_ID_VALID',    'TK_T_CUSTOMER', 'VALIDATOR', 'TAX_ID', 'TAX_ID');
    tk_dq.add_rule('T_IBAN_VALID',      'TK_T_CUSTOMER', 'VALIDATOR', 'IBAN',   'IBAN', 'WARNING');
    tk_dq.add_rule('T_EMAIL_FORMAT',    'TK_T_CUSTOMER', 'REGEX',     'EMAIL',  '^[^@]+@[^@]+\.[a-z]{2,}$');
    tk_dq.add_rule('T_CREDIT_RANGE',    'TK_T_CUSTOMER', 'RANGE',     'CREDIT_LIMIT', '0..1000000');
    tk_dq.add_rule('T_CITY_LIST',       'TK_T_CUSTOMER', 'IN_LIST',   'CITY', 'ANKARA, IZMIR, ISTANBUL');
    tk_dq.add_rule('T_BLOCKED_CREDIT',  'TK_T_CUSTOMER', 'CUSTOM',    null, q'[status = 'BLOCKED' and credit_limit > 0]',
                   p_description => 'Blocked customers must not have an open credit limit');
    commit;
  end add_rules;

  procedure cleanup is
  begin
    delete from tk_dq_runs
     where run_id in (select run_id from tk_dq_results where rule_name like 'T\_%' escape '\')
        or run_id not in (select run_id from tk_dq_results);
    delete from tk_dq_rules where rule_name like 'T\_%' escape '\';
    execute immediate q'[alter session set nls_numeric_characters = '.,']';
    commit;
  end cleanup;

  procedure counts_violations is
    l_run number := tk_dq.run_checks('TK_T_CUSTOMER');
  begin
    ut.expect(result_of(l_run, 'T_NAME_REQUIRED').violation_count, 'NOT_NULL').to_equal(1);
    ut.expect(result_of(l_run, 'T_TAX_ID_UNIQUE').violation_count, 'UNIQUE').to_equal(2);
    ut.expect(result_of(l_run, 'T_TAX_ID_VALID').violation_count, 'VALIDATOR TAX_ID').to_equal(1);
    ut.expect(result_of(l_run, 'T_IBAN_VALID').violation_count, 'VALIDATOR IBAN').to_equal(1);
    ut.expect(result_of(l_run, 'T_EMAIL_FORMAT').violation_count, 'REGEX').to_equal(1);
    ut.expect(result_of(l_run, 'T_CREDIT_RANGE').violation_count, 'RANGE').to_equal(2);
    ut.expect(result_of(l_run, 'T_CITY_LIST').violation_count, 'IN_LIST').to_equal(1);
    ut.expect(result_of(l_run, 'T_BLOCKED_CREDIT').violation_count, 'CUSTOM').to_equal(1);
    ut.expect(result_of(l_run, 'T_CREDIT_RANGE').checked_rows).to_equal(4);
    ut.expect(result_of(l_run, 'T_IBAN_VALID').severity).to_equal('WARNING');
  end counts_violations;

  procedure run_header is
    l_run number := tk_dq.run_checks('TK_T_CUSTOMER');
    l_hdr tk_dq_runs%rowtype;
  begin
    ut.expect(result_of(l_run, 'T_ID_REQUIRED').status).to_equal('PASSED');
    ut.expect(result_of(l_run, 'T_NAME_REQUIRED').status).to_equal('FAILED');
    select * into l_hdr from tk_dq_runs where run_id = l_run;
    ut.expect(l_hdr.rules_checked).to_equal(9);
    ut.expect(l_hdr.rules_failed).to_equal(8);
    ut.expect(l_hdr.rules_errored).to_equal(0);
    ut.expect(l_hdr.finished_at).not_to_be_null();
  end run_header;

  procedure broken_rule_does_not_stop_run is
    l_run number;
  begin
    tk_dq.add_rule('T_BROKEN', 'TK_T_CUSTOMER', 'CUSTOM', p_rule_param => 'no_such_column > 0');
    l_run := tk_dq.run_checks('TK_T_CUSTOMER');
    ut.expect(result_of(l_run, 'T_BROKEN').status).to_equal('ERROR');
    ut.expect(result_of(l_run, 'T_BROKEN').error_message).to_be_like('%ORA-00904%');
    ut.expect(result_of(l_run, 'T_NAME_REQUIRED').status).to_equal('FAILED');
  end broken_rule_does_not_stop_run;

  procedure inactive_rules_skipped is
    l_run   number;
    l_count number;
  begin
    tk_dq.set_active('t_name_required', false);
    l_run := tk_dq.run_checks('TK_T_CUSTOMER');
    select count(*) into l_count from tk_dq_results where run_id = l_run and rule_name = 'T_NAME_REQUIRED';
    ut.expect(l_count).to_equal(0);
  end inactive_rules_skipped;

  procedure filter_by_table is
    l_run   number := tk_dq.run_checks('SOME_OTHER_TABLE');
    l_count number;
  begin
    select count(*) into l_count from tk_dq_results where run_id = l_run and rule_name like 'T\_%' escape '\';
    ut.expect(l_count).to_equal(0);
  end filter_by_table;

  procedure violations_cursor is
    l_cursor sys_refcursor;
  begin
    tk_dq.violations('T_CREDIT_RANGE', l_cursor);
    ut.expect(l_cursor).to_have_count(2);
    tk_dq.violations('T_TAX_ID_UNIQUE', l_cursor, p_max_rows => 1);
    ut.expect(l_cursor).to_have_count(1);
  end violations_cursor;

  procedure summary_cursor is
    l_cursor sys_refcursor;
    l_run    number := tk_dq.run_checks('TK_T_CUSTOMER');
  begin
    tk_dq.run_summary(l_run, l_cursor);
    ut.expect(l_cursor).to_have_count(9);
  end summary_cursor;

  procedure range_predicate_nls is
    l_run number;
  begin
    execute immediate q'[alter session set nls_numeric_characters = ',.']';
    tk_dq.add_rule('T_DECIMAL_RANGE', 'TK_T_CUSTOMER', 'RANGE', 'CREDIT_LIMIT', '-5.5..1000.25');
    ut.expect(tk_dq.violation_predicate('T_DECIMAL_RANGE'))
      .to_equal('"CREDIT_LIMIT" is not null and ("CREDIT_LIMIT" < -5.5 or "CREDIT_LIMIT" > 1000.25)');
    l_run := tk_dq.run_checks('TK_T_CUSTOMER');
    -- 50000 and 2000000 are above the maximum
    ut.expect(result_of(l_run, 'T_DECIMAL_RANGE').violation_count).to_equal(2);
  end range_predicate_nls;

  procedure add_rule_upserts is
    l_param tk_dq_rules.rule_param%type;
  begin
    tk_dq.add_rule('T_CITY_LIST', 'TK_T_CUSTOMER', 'IN_LIST', 'CITY', 'ANKARA');
    select rule_param into l_param from tk_dq_rules where rule_name = 'T_CITY_LIST';
    ut.expect(l_param).to_equal('ANKARA');
  end add_rule_upserts;

  procedure unknown_table is
  begin
    tk_dq.add_rule('T_X', 'NO_SUCH_TABLE', 'NOT_NULL', 'X');
  end;

  procedure unknown_column is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'NOT_NULL', 'NO_SUCH_COLUMN');
  end;

  procedure unknown_rule_type is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'LOOKS_GOOD', 'NAME');
  end;

  procedure invalid_range is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'RANGE', 'CREDIT_LIMIT', '10..1');
  end;

  procedure unknown_validator is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'VALIDATOR', 'TAX_ID', 'SSN');
  end;

  procedure invalid_regex is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'REGEX', 'EMAIL', '([a-z');
  end;

  procedure custom_with_semicolon is
  begin
    tk_dq.add_rule('T_X', 'TK_T_CUSTOMER', 'CUSTOM', p_rule_param => '1 = 1; drop table tk_t_customer');
  end;

  procedure remove_unknown_rule is
  begin
    tk_dq.remove_rule('T_DOES_NOT_EXIST');
  end;

end test_tk_dq;
/
