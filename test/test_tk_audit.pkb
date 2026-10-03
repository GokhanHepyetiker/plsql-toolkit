create or replace package body test_tk_audit as

  function log_count (p_table in varchar2 default 'TK_T_ITEM') return number is
    l_count number;
  begin
    select count(*) into l_count from tk_audit_log where table_owner = user and table_name = p_table;
    return l_count;
  end log_count;

  function last_log (p_table in varchar2 default 'TK_T_ITEM') return tk_audit_log%rowtype is
    l_row tk_audit_log%rowtype;
  begin
    select *
      into l_row
      from tk_audit_log
     where table_owner = user and table_name = p_table
     order by audit_id desc
     fetch first 1 row only;
    return l_row;
  end last_log;

  function has_key (p_json in clob, p_key in varchar2) return boolean is
  begin
    return p_json is not null and json_object_t.parse(p_json).has(p_key);
  end has_key;

  function json_val (p_json in clob, p_key in varchar2) return varchar2 is
  begin
    return json_object_t.parse(p_json).get_string(p_key);
  end json_val;

  procedure clear_logs is
  begin
    delete from tk_audit_log where table_owner = user and table_name in ('TK_T_ITEM', 'TK_T_STOCK');
    commit;
  end clear_logs;

  procedure insert_item (p_id in number default 1, p_price in number default 12.5) is
  begin
    insert into tk_t_item (item_id, item_code, name, price, created_on, notes, last_update_user)
    values (p_id, 'P-' || p_id, 'Pen', p_price, date '2026-01-15', 'long text', 'erp');
  end insert_item;

  procedure cleanup is
  begin
    tk_audit.disable_audit('TK_T_ITEM');
    tk_audit.disable_audit('TK_T_STOCK');
    delete from tk_t_item;
    delete from tk_t_stock;
    clear_logs;
    dbms_session.clear_identifier;
  end cleanup;

  procedure reset is
  begin
    cleanup;
    tk_audit.enable_audit('TK_T_ITEM');
  end reset;

  procedure generates_ddl is
    l_ddl clob := tk_audit.generate_trigger('tk_t_item');
  begin
    ut.expect(dbms_lob.instr(l_ddl, 'after insert or update or delete on "' || user || '"."TK_T_ITEM"')).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_ddl, 'l_new.put(''PRICE''')).to_be_greater_than(0);
    ut.expect(dbms_lob.instr(l_ddl, 'l_new.put(''CREATED_ON''')).to_be_greater_than(0);
    -- CLOB columns are not supported and must be skipped
    ut.expect(dbms_lob.instr(l_ddl, 'NOTES')).to_equal(0);
  end generates_ddl;

  procedure enable_creates_trigger is
    l_status varchar2(30);
  begin
    ut.expect(tk_audit.is_enabled('tk_t_item')).to_equal('Y');
    select status into l_status from user_objects where object_name = tk_audit.trigger_name('TK_T_ITEM') and object_type = 'TRIGGER';
    ut.expect(l_status).to_equal('VALID');
  end enable_creates_trigger;

  procedure logs_insert is
    l_log tk_audit_log%rowtype;
  begin
    insert_item;
    ut.expect(log_count).to_equal(1);
    l_log := last_log;
    ut.expect(l_log.operation).to_equal('I');
    ut.expect(l_log.pk_value).to_equal('1');
    ut.expect(l_log.old_values).to_be_null();
    ut.expect(json_val(l_log.new_values, 'NAME')).to_equal('Pen');
    ut.expect(json_object_t.parse(l_log.new_values).get_number('PRICE')).to_equal(12.5);
    ut.expect(has_key(l_log.new_values, 'NOTES')).to_be_false();
    ut.expect(l_log.transaction_id).not_to_be_null();
  end logs_insert;

  procedure logs_update_changed_only is
    l_log tk_audit_log%rowtype;
  begin
    insert_item;
    update tk_t_item set price = 15, notes = 'not audited' where item_id = 1;
    ut.expect(log_count).to_equal(2);
    l_log := last_log;
    ut.expect(l_log.operation).to_equal('U');
    ut.expect(json_object_t.parse(l_log.old_values).get_number('PRICE')).to_equal(12.5);
    ut.expect(json_object_t.parse(l_log.new_values).get_number('PRICE')).to_equal(15);
    ut.expect(json_object_t.parse(l_log.new_values).get_size()).to_equal(1);
    ut.expect(has_key(l_log.new_values, 'NAME')).to_be_false();
  end logs_update_changed_only;

  procedure skips_noop_update is
  begin
    insert_item;
    update tk_t_item set name = name, price = 12.5 where item_id = 1;
    ut.expect(log_count).to_equal(1);
  end skips_noop_update;

  procedure null_safe_comparison is
    l_log tk_audit_log%rowtype;
  begin
    insert_item(p_price => null);
    update tk_t_item set price = 10 where item_id = 1;
    l_log := last_log;
    ut.expect(has_key(l_log.old_values, 'PRICE')).to_be_true();
    ut.expect(json_object_t.parse(l_log.old_values).get('PRICE').is_null()).to_be_true();

    update tk_t_item set price = null where item_id = 1;
    l_log := last_log;
    ut.expect(json_object_t.parse(l_log.new_values).get('PRICE').is_null()).to_be_true();
    ut.expect(log_count).to_equal(3);
  end null_safe_comparison;

  procedure logs_delete is
    l_log tk_audit_log%rowtype;
  begin
    insert_item;
    delete from tk_t_item where item_id = 1;
    l_log := last_log;
    ut.expect(l_log.operation).to_equal('D');
    ut.expect(l_log.pk_value).to_equal('1');
    ut.expect(l_log.new_values).to_be_null();
    ut.expect(json_val(l_log.old_values, 'ITEM_CODE')).to_equal('P-1');
  end logs_delete;

  procedure iso_dates is
    l_log tk_audit_log%rowtype;
  begin
    insert into tk_t_item (item_id, item_code, created_on, updated_at)
    values (2, 'P-2', to_date('2026-01-15 13:45:00', 'YYYY-MM-DD HH24:MI:SS'), timestamp '2026-01-15 13:45:00.123456');
    l_log := last_log;
    ut.expect(json_val(l_log.new_values, 'CREATED_ON')).to_equal('2026-01-15T13:45:00');
    ut.expect(json_val(l_log.new_values, 'UPDATED_AT')).to_equal('2026-01-15T13:45:00.123456');
  end iso_dates;

  procedure exclude_columns is
  begin
    tk_audit.enable_audit('TK_T_ITEM', p_exclude_columns => 'last_update_user, updated_at');
    insert_item;
    ut.expect(has_key(last_log().new_values, 'LAST_UPDATE_USER')).to_be_false();
    ut.expect(has_key(last_log().new_values, 'NAME')).to_be_true();

    update tk_t_item set last_update_user = 'someone else', updated_at = systimestamp where item_id = 1;
    ut.expect(log_count).to_equal(1);
  end exclude_columns;

  procedure include_columns is
  begin
    tk_audit.enable_audit('TK_T_ITEM', p_columns => 'PRICE');
    ut.expect(dbms_lob.instr(tk_audit.generate_trigger('TK_T_ITEM', p_columns => 'PRICE'), 'update of "PRICE"')).to_be_greater_than(0);
    insert_item;
    ut.expect(json_object_t.parse(last_log().new_values).get_size()).to_equal(1);

    update tk_t_item set name = 'Pencil' where item_id = 1;
    ut.expect(log_count).to_equal(1);
    update tk_t_item set price = 20 where item_id = 1;
    ut.expect(log_count).to_equal(2);
  end include_columns;

  procedure composite_pk is
  begin
    tk_audit.enable_audit('TK_T_STOCK');
    insert into tk_t_stock (warehouse_code, item_id, qty) values ('W01', 7, 100);
    ut.expect(last_log('TK_T_STOCK').pk_value).to_equal('W01|7');
  end composite_pk;

  procedure client_identifier is
    l_log tk_audit_log%rowtype;
  begin
    dbms_session.set_identifier('erp.user42');
    insert_item;
    dbms_session.clear_identifier;
    l_log := last_log;
    ut.expect(l_log.changed_by).to_equal('erp.user42');
    ut.expect(l_log.db_user).to_equal(user);

    insert_item(p_id => 2);
    ut.expect(last_log().changed_by).to_equal(user);
  end client_identifier;

  procedure rollback_removes_audit is
  begin
    commit;
    savepoint before_change;
    insert_item;
    ut.expect(log_count).to_equal(1);
    rollback to savepoint before_change;
    ut.expect(log_count).to_equal(0);
  end rollback_removes_audit;

  procedure disable_stops_logging is
  begin
    tk_audit.disable_audit('TK_T_ITEM');
    ut.expect(tk_audit.is_enabled('TK_T_ITEM')).to_equal('N');
    insert_item;
    ut.expect(log_count).to_equal(0);
    tk_audit.disable_audit('TK_T_ITEM');
  end disable_stops_logging;

  procedure history_cursor is
    l_cursor sys_refcursor;
    l_ops    varchar2(10);
  begin
    insert_item(p_id => 1);
    insert_item(p_id => 2);
    update tk_t_item set price = 1 where item_id = 1;
    delete from tk_t_item where item_id = 1;

    tk_audit.history('tk_t_item', l_cursor, p_pk_value => '1');
    ut.expect(l_cursor).to_have_count(3);

    select listagg(operation) within group (order by audit_id)
      into l_ops
      from tk_audit_log
     where table_owner = user and table_name = 'TK_T_ITEM' and pk_value = '1';
    ut.expect(l_ops).to_equal('IUD');
  end history_cursor;

  procedure purge_old_rows is
    l_deleted pls_integer;
  begin
    insert_item(p_id => 1);
    update tk_audit_log set changed_at = systimestamp - interval '40' day
     where table_owner = user and table_name = 'TK_T_ITEM';
    insert_item(p_id => 2);

    tk_audit.purge(30, l_deleted);
    ut.expect(l_deleted).to_equal(1);
    ut.expect(log_count).to_equal(1);
  end purge_old_rows;

  procedure unknown_table is
    l_ddl clob;
  begin
    l_ddl := tk_audit.generate_trigger('NO_SUCH_TABLE');
  end unknown_table;

  procedure unknown_column is
    l_ddl clob;
  begin
    l_ddl := tk_audit.generate_trigger('TK_T_ITEM', p_columns => 'PRICE, NO_SUCH_COLUMN');
  end unknown_column;

  procedure unsupported_column is
    l_ddl clob;
  begin
    l_ddl := tk_audit.generate_trigger('TK_T_ITEM', p_columns => 'NOTES');
  end unsupported_column;

end test_tk_audit;
/
