-- Compiles the utPLSQL test packages.
whenever sqlerror exit failure
set define off
set feedback off
set serveroutput on

prompt Installing tests ...

-- Fixture tables used with static SQL by the test packages (recreated on every install).
declare
  procedure recreate (p_name in varchar2, p_ddl in varchar2) is
  begin
    begin
      execute immediate 'drop table ' || p_name || ' purge';
    exception
      when others then
        if sqlcode != -942 then raise; end if;
    end;
    execute immediate p_ddl;
  end recreate;
begin
  recreate('TK_T_ITEM', q'[
    create table tk_t_item (
      item_id          number(10) constraint tk_t_item_pk primary key,
      item_code        varchar2(30) not null,
      name             varchar2(100),
      price            number(12,2),
      created_on       date,
      updated_at       timestamp(6),
      notes            clob,
      last_update_user varchar2(30)
    )]');
  recreate('TK_T_STOCK', q'[
    create table tk_t_stock (
      warehouse_code varchar2(10),
      item_id        number(10),
      qty            number,
      constraint tk_t_stock_pk primary key (warehouse_code, item_id)
    )]');
end;
/

@@test_tk_validate.pks
@@test_tk_validate.pkb
@@test_tk_audit.pks
@@test_tk_audit.pkb
@@test_tk_dq.pks
@@test_tk_dq.pkb
@@test_tk_cursor.pks
@@test_tk_cursor.pkb

declare
  l_errors varchar2(32767);
begin
  for e in (select name, type, line, position, text
              from user_errors
             where name like 'TEST\_TK\_%' escape '\'
               and attribute = 'ERROR'
             order by name, type, sequence)
  loop
    l_errors := substr(l_errors || chr(10) || e.type || ' ' || e.name || ' ' || e.line || ':' || e.position || ' ' || e.text, 1, 30000);
  end loop;
  if l_errors is not null then
    dbms_output.put_line('Compilation errors:' || l_errors);
    raise_application_error(-20000, 'Test installation failed, see compilation errors above');
  end if;
end;
/
