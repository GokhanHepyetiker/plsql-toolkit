-- Demo data used by the examples: a small customer master with typical ERP data quality problems.
whenever sqlerror exit failure
set define off
set feedback off

begin
  execute immediate 'drop table demo_customers purge';
exception
  when others then
    if sqlcode != -942 then raise; end if;
end;
/

-- leftovers of earlier example runs
delete from tk_audit_log where table_name = 'DEMO_CUSTOMERS';
delete from tk_dq_runs where run_id in (select run_id from tk_dq_results where table_name = 'DEMO_CUSTOMERS');
delete from tk_dq_rules where table_name = 'DEMO_CUSTOMERS';
commit;

create table demo_customers (
  customer_id       number        constraint demo_customers_pk primary key,
  customer_code     varchar2(20)  not null,
  name              varchar2(200),
  tax_id            varchar2(20),
  iban              varchar2(40),
  email             varchar2(200),
  mobile            varchar2(30),
  city              varchar2(50),
  credit_limit      number(14,2),
  status            varchar2(10),
  last_update_date  date
);

insert into demo_customers values (1, 'C-001', 'Anadolu Kagit A.S.',    '1234567890',  'TR330006100519786457841326', 'finans@anadolukagit.com.tr', '0532 123 45 67',   'ANKARA',   250000, 'ACTIVE',  sysdate);
insert into demo_customers values (2, 'C-002', 'Ege Ambalaj Ltd.',      '1234567891',  'TR330006100519786457841327', 'info@egeambalaj',            '+90 532 1234567',  'IZMIR',    -100,   'ACTIVE',  sysdate);
insert into demo_customers values (3, 'C-003', null,                    '10000000146', null,                         'muhasebe@example.com',       '0212 555 44 33',   'ankara',   2000000,'PASSIVE', sysdate);
insert into demo_customers values (4, 'C-004', 'Marmara Geri Donusum',  '1234567890',  'TR320010009999901234567890', null,                         '5051234567',       'ISTANBUL', 50000,  'BLOCKED', sysdate);
insert into demo_customers values (5, 'C-005', 'Cukurova Karton',       '9876543217',  'TR320010009999901234567890', 'satin.alma@cukurovakarton.com', '0(505) 123 45 67', 'ADANA',   75000,  'ACTIVE',  sysdate);
commit;

prompt demo_customers created with 5 rows.
