-- tk_dq: declarative data quality rules and a run summary.
whenever sqlerror exit failure
set define off
set feedback off
set linesize 200
set pagesize 100
column rule_name format a20
column table_name noprint
column column_name format a12
column rule_type format a9
column severity format a8
column status format a7
column checked_rows format 9999 heading ROWS
column violation_count format 9999 heading BAD
column violation_pct format 990.99 heading PCT
column error_message noprint
column description format a45 word_wrapped

begin
  tk_dq.add_rule('CUST_NAME_REQUIRED',  'DEMO_CUSTOMERS', 'NOT_NULL',  'NAME');
  tk_dq.add_rule('CUST_TAX_ID_UNIQUE',  'DEMO_CUSTOMERS', 'UNIQUE',    'TAX_ID');
  tk_dq.add_rule('CUST_TAX_ID_VALID',   'DEMO_CUSTOMERS', 'VALIDATOR', 'TAX_ID', 'TAX_ID');
  tk_dq.add_rule('CUST_IBAN_VALID',     'DEMO_CUSTOMERS', 'VALIDATOR', 'IBAN',   'IBAN');
  tk_dq.add_rule('CUST_EMAIL_VALID',    'DEMO_CUSTOMERS', 'VALIDATOR', 'EMAIL',  'EMAIL', p_severity => 'WARNING');
  tk_dq.add_rule('CUST_MOBILE_VALID',   'DEMO_CUSTOMERS', 'VALIDATOR', 'MOBILE', 'TR_MOBILE', p_severity => 'WARNING');
  tk_dq.add_rule('CUST_CREDIT_RANGE',   'DEMO_CUSTOMERS', 'RANGE',     'CREDIT_LIMIT', '0..1000000');
  tk_dq.add_rule('CUST_CITY_UPPERCASE', 'DEMO_CUSTOMERS', 'REGEX',     'CITY', '^[A-Z ]+$');
  tk_dq.add_rule('CUST_BLOCKED_CREDIT', 'DEMO_CUSTOMERS', 'CUSTOM',    p_rule_param => q'[status = 'BLOCKED' and credit_limit > 0]',
                 p_description => 'Blocked customers must not keep an open credit limit');
  commit;
end;
/

variable run_id number
variable summary refcursor

begin
  :run_id := tk_dq.run_checks('DEMO_CUSTOMERS');
  commit;
  tk_dq.run_summary(:run_id, :summary);
end;
/

prompt
prompt === Data quality summary ===
print summary

variable bad refcursor
begin
  tk_dq.violations('CUST_TAX_ID_VALID', :bad);
end;
/

prompt
prompt === Rows violating CUST_TAX_ID_VALID ===
column row_id noprint
column customer_code format a6
column name format a18
column tax_id format a11
column iban format a27
column email format a16
column mobile format a16
column city format a8
column credit_limit format 9999999
column status noprint
column last_update_date noprint
print bad
