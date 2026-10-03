-- Removes the PL/SQL Toolkit, its audit triggers and its tables (including audit history!).
whenever sqlerror exit failure
set define off
set feedback off
set serveroutput on

declare
  procedure drop_if_exists (p_sql in varchar2) is
  begin
    execute immediate p_sql;
  exception
    when others then
      -- ORA-00942 table, ORA-04043 object, ORA-04080 trigger does not exist
      if sqlcode not in (-942, -4043, -4080) then
        raise;
      end if;
  end;
begin
  for t in (select trigger_name from user_triggers where trigger_name like 'TK\_AUD\_%' escape '\') loop
    drop_if_exists('drop trigger "' || t.trigger_name || '"');
  end loop;
  for p in (select column_value as name from table(sys.odcivarchar2list('TK_CURSOR', 'TK_DQ', 'TK_AUDIT', 'TK_VALIDATE', 'TK_UTIL'))) loop
    drop_if_exists('drop package ' || p.name);
  end loop;
  for t in (select column_value as name from table(sys.odcivarchar2list('TK_DQ_RESULTS', 'TK_DQ_RUNS', 'TK_DQ_RULES', 'TK_AUDIT_LOG'))) loop
    drop_if_exists('drop table ' || t.name || ' purge');
  end loop;
end;
/

prompt PL/SQL Toolkit removed.
