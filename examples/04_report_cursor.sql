-- tk_cursor: a typical SYS_REFCURSOR report with safe dynamic sorting and CSV / JSON export.
whenever sqlerror exit failure
set define off
set feedback off
set serveroutput on
set long 5000
set longchunksize 5000
set linesize 200
set pagesize 0

create or replace package demo_reports authid definer as
  /**
   * Customers of a city (or all), sortable by the caller.
   * p_sort example: 'credit_limit desc, name'
   */
  procedure customers_by_city (
    p_city   in  varchar2,
    p_sort   in  varchar2,
    p_result out sys_refcursor
  );
end demo_reports;
/

create or replace package body demo_reports as

  procedure customers_by_city (
    p_city   in  varchar2,
    p_sort   in  varchar2,
    p_result out sys_refcursor
  ) is
  begin
    -- filters are bind variables; ORDER BY text comes from the whitelist, never from p_sort itself
    open p_result for
      'select customer_code, name, city, credit_limit
         from demo_customers
        where (:city is null or city = upper(:city)) '
      || tk_cursor.safe_order_by(p_sort, 'CUSTOMER_CODE, NAME, CITY, CREDIT_LIMIT', 'CUSTOMER_CODE')
      using p_city, p_city;
  end customers_by_city;

end demo_reports;
/

variable csv clob
variable json clob

declare
  l_cursor sys_refcursor;
begin
  demo_reports.customers_by_city(null, 'credit_limit desc', l_cursor);
  :csv := tk_cursor.to_csv(l_cursor, p_delimiter => ';');

  demo_reports.customers_by_city('izmir', null, l_cursor);
  :json := tk_cursor.to_json(l_cursor);
end;
/

prompt
prompt === CSV (semicolon for Excel with Turkish regional settings) ===
print csv
prompt === JSON ===
print json

prompt === Sorting by a column that is not whitelisted is rejected ===
declare
  l_cursor sys_refcursor;
begin
  demo_reports.customers_by_city(null, 'tax_id; drop table demo_customers', l_cursor);
exception
  when others then
    dbms_output.put_line(sqlerrm);
end;
/
