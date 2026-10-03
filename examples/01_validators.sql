-- tk_validate: Turkish master data checks directly in SQL.
whenever sqlerror exit failure
set define off
set feedback off
set linesize 200
set pagesize 100
column customer_code format a6
column tax_id format a11
column tax_ok format a6
column iban_ok format a7
column email_ok format a8
column mobile format a17
column mobile_e164 format a14
column iban_formatted format a33
column plate format a10

prompt
prompt === Validation status per customer ===
select customer_code,
       tax_id,
       tk_validate.is_tax_id(tax_id)        as tax_ok,
       tk_validate.is_iban(iban)            as iban_ok,
       tk_validate.is_email(email)          as email_ok,
       mobile,
       tk_validate.normalize_tr_mobile(mobile) as mobile_e164
  from demo_customers
 order by customer_code;

prompt
prompt === Formatting helpers ===
select tk_validate.format_iban('tr330006100519786457841326') as iban_formatted,
       tk_validate.normalize_tr_plate('46abc123')            as plate
  from dual;
