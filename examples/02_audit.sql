-- tk_audit: audit a table with one call and read the JSON change log.
whenever sqlerror exit failure
set define off
set feedback off
set linesize 250
set pagesize 100
set long 2000
set longchunksize 2000
column operation format a2 heading OP
column pk_value format a3 heading PK
column changed_by format a10
column old_values format a70 word_wrapped
column new_values format a160 word_wrapped

begin
  -- LAST_UPDATE_DATE changes on every save in most ERPs: don't let it create noise
  tk_audit.enable_audit('DEMO_CUSTOMERS', p_exclude_columns => 'LAST_UPDATE_DATE');
end;
/

begin
  -- ERP applications usually connect with one database user; the application user goes here
  dbms_session.set_identifier('ayse.kaya');

  insert into demo_customers (customer_id, customer_code, name, city, credit_limit, status)
  values (6, 'C-006', 'Konya Ambalaj', 'KONYA', 10000, 'ACTIVE');

  update demo_customers set credit_limit = 15000, last_update_date = sysdate where customer_id = 6;
  update demo_customers set last_update_date = sysdate where customer_id = 6;   -- not logged: excluded column only
  delete from demo_customers where customer_id = 6;

  dbms_session.clear_identifier;
  commit;
end;
/

prompt
prompt === tk_audit_log ===
select operation, pk_value, changed_by, old_values, new_values
  from tk_audit_log
 where table_name = 'DEMO_CUSTOMERS'
 order by audit_id;

begin
  tk_audit.disable_audit('DEMO_CUSTOMERS');
end;
/
