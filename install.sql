-- PL/SQL Toolkit installer. Run as the schema that should own the toolkit:
--   sqlplus user/password@//host:1521/service @install.sql
whenever sqlerror exit failure
whenever oserror exit failure
set define off
set feedback off
set serveroutput on

set define on
prompt Installing PL/SQL Toolkit into schema &_USER ...
set define off

prompt - tables
@@source/tables.sql
prompt - tk_util
@@source/tk_util.pks
@@source/tk_util.pkb
prompt - tk_validate
@@source/tk_validate.pks
@@source/tk_validate.pkb
prompt - tk_audit
@@source/tk_audit.pks
@@source/tk_audit.pkb
prompt - tk_dq
@@source/tk_dq.pks
@@source/tk_dq.pkb
prompt - tk_cursor
@@source/tk_cursor.pks
@@source/tk_cursor.pkb

-- SQL*Plus only warns about compilation errors; turn them into a failed install.
declare
  l_errors varchar2(32767);
begin
  for e in (select name, type, line, position, text
              from user_errors
             where name like 'TK\_%' escape '\'
               and attribute = 'ERROR'
             order by name, type, sequence)
  loop
    l_errors := substr(l_errors || chr(10) || e.type || ' ' || e.name || ' ' || e.line || ':' || e.position || ' ' || e.text, 1, 30000);
  end loop;
  if l_errors is not null then
    dbms_output.put_line('Compilation errors:' || l_errors);
    raise_application_error(-20000, 'PL/SQL Toolkit installation failed, see compilation errors above');
  end if;
end;
/

prompt PL/SQL Toolkit installed successfully.
