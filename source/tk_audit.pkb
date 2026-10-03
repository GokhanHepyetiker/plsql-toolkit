create or replace package body tk_audit as

  c_owner constant varchar2(128) := $$plsql_unit_owner;
  c_nl    constant varchar2(1)   := chr(10);

  e_compiled_with_errors exception;
  e_trigger_not_found    exception;
  pragma exception_init(e_compiled_with_errors, -24344);
  pragma exception_init(e_trigger_not_found, -4080);

  type t_column is record (name varchar2(128), data_type varchar2(128));
  type t_columns is table of t_column;

  function contains (p_list in tk_util.t_strings, p_value in varchar2) return boolean is
  begin
    for i in 1 .. p_list.count loop
      if upper(p_list(i)) = p_value then
        return true;
      end if;
    end loop;
    return false;
  end contains;

  function is_supported (p_data_type in varchar2) return boolean is
  begin
    return p_data_type in ('NUMBER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE',
                           'VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR', 'DATE', 'RAW')
        or p_data_type like 'TIMESTAMP%';
  end is_supported;

  /** PL/SQL expression that converts :old/:new.<column> into a JSON-friendly scalar. */
  function value_expr (p_ref in varchar2, p_data_type in varchar2) return varchar2 is
  begin
    return case
             when p_data_type in ('NUMBER', 'FLOAT', 'VARCHAR2', 'CHAR') then p_ref
             when p_data_type in ('BINARY_FLOAT', 'BINARY_DOUBLE') then 'to_number(' || p_ref || ')'
             when p_data_type in ('NVARCHAR2', 'NCHAR') then 'to_char(' || p_ref || ')'
             when p_data_type = 'DATE' then 'to_char(' || p_ref || ', ''YYYY-MM-DD"T"HH24:MI:SS'')'
             when p_data_type like 'TIMESTAMP(%) WITH TIME ZONE'
               then 'to_char(' || p_ref || ', ''YYYY-MM-DD"T"HH24:MI:SS.FF6TZH:TZM'')'
             when p_data_type like 'TIMESTAMP%' then 'to_char(' || p_ref || ', ''YYYY-MM-DD"T"HH24:MI:SS.FF6'')'
             when p_data_type = 'RAW' then 'rawtohex(' || p_ref || ')'
           end;
  end value_expr;

  /** String expression used for the pk_value column. */
  function key_expr (p_ref in varchar2, p_data_type in varchar2) return varchar2 is
  begin
    return case
             when p_data_type in ('VARCHAR2', 'CHAR') then p_ref
             when p_data_type in ('NUMBER', 'FLOAT') then 'to_char(' || p_ref || ')'
             else value_expr(p_ref, p_data_type)
           end;
  end key_expr;

  function trigger_name (p_table_name in varchar2) return varchar2 is
    l_table varchar2(128) := upper(trim(p_table_name));
  begin
    if length('TK_AUD_' || l_table) <= 128 then
      return 'TK_AUD_' || l_table;
    end if;
    return substr('TK_AUD_' || l_table, 1, 117) || '_' || lpad(dbms_utility.get_hash_value(l_table, 0, 1e9), 10, '0');
  end trigger_name;

  procedure resolve_table (
    p_table_name in  varchar2,
    p_owner      in  varchar2,
    o_owner      out varchar2,
    o_table      out varchar2
  ) is
    l_count pls_integer;
  begin
    o_owner := tk_util.schema_name(p_owner);
    o_table := upper(trim(p_table_name));
    select count(*) into l_count from all_tables where owner = o_owner and table_name = o_table;
    if l_count = 0 then
      raise_application_error(-20110, 'Table ' || o_owner || '.' || o_table || ' does not exist or is not accessible');
    end if;
  end resolve_table;

  function generate_trigger (
    p_table_name      in varchar2,
    p_owner           in varchar2 default user,
    p_columns         in varchar2 default null,
    p_exclude_columns in varchar2 default null
  ) return clob is
    l_owner     varchar2(128);
    l_table     varchar2(128);
    l_include   tk_util.t_strings := tk_util.split(upper(p_columns));
    l_exclude   tk_util.t_strings := tk_util.split(upper(p_exclude_columns));
    l_all       t_columns;
    l_audited   t_columns := t_columns();
    l_pk        t_columns;
    l_pk_new    varchar2(32767);
    l_pk_old    varchar2(32767);
    l_ref_old   varchar2(200);
    l_ref_new   varchar2(200);
    l_key       varchar2(200);
    l_update_of varchar2(32767);
    l_sql       clob;
  begin
    resolve_table(p_table_name, p_owner, l_owner, l_table);

    select column_name, data_type
      bulk collect into l_all
      from all_tab_cols
     where owner = l_owner
       and table_name = l_table
       and hidden_column = 'NO'
       and virtual_column = 'NO'
     order by column_id;

    -- validate the include / exclude lists against the table definition
    for i in 1 .. l_include.count loop
      declare
        l_found boolean := false;
      begin
        for j in 1 .. l_all.count loop
          if l_all(j).name = l_include(i) then
            l_found := true;
            if not is_supported(l_all(j).data_type) then
              raise_application_error(-20111, 'Column ' || l_include(i) || ' has unsupported type ' || l_all(j).data_type);
            end if;
          end if;
        end loop;
        if not l_found then
          raise_application_error(-20111, 'Column ' || l_include(i) || ' does not exist in ' || l_table);
        end if;
      end;
    end loop;
    for i in 1 .. l_exclude.count loop
      declare
        l_found boolean := false;
      begin
        for j in 1 .. l_all.count loop
          l_found := l_found or l_all(j).name = l_exclude(i);
        end loop;
        if not l_found then
          raise_application_error(-20111, 'Excluded column ' || l_exclude(i) || ' does not exist in ' || l_table);
        end if;
      end;
    end loop;

    for j in 1 .. l_all.count loop
      if is_supported(l_all(j).data_type)
         and (l_include.count = 0 or contains(l_include, l_all(j).name))
         and not contains(l_exclude, l_all(j).name)
      then
        l_audited.extend;
        l_audited(l_audited.count) := l_all(j);
      end if;
    end loop;
    if l_audited.count = 0 then
      raise_application_error(-20111, 'No auditable columns left for ' || l_table);
    end if;

    -- primary key -> pk_value ('A|1' for composite keys)
    select c.column_name, c.data_type
      bulk collect into l_pk
      from all_constraints k
      join all_cons_columns kc on kc.owner = k.owner and kc.constraint_name = k.constraint_name
      join all_tab_cols c on c.owner = k.owner and c.table_name = k.table_name and c.column_name = kc.column_name
     where k.owner = l_owner
       and k.table_name = l_table
       and k.constraint_type = 'P'
     order by kc.position;

    for i in 1 .. l_pk.count loop
      l_key    := dbms_assert.enquote_name(l_pk(i).name, false);
      l_pk_new := l_pk_new || case when i > 1 then ' || ''|'' || ' end || key_expr(':new.' || l_key, l_pk(i).data_type);
      l_pk_old := l_pk_old || case when i > 1 then ' || ''|'' || ' end || key_expr(':old.' || l_key, l_pk(i).data_type);
    end loop;

    if l_include.count > 0 then
      for i in 1 .. l_audited.count loop
        l_update_of := l_update_of || case when i > 1 then ', ' end || dbms_assert.enquote_name(l_audited(i).name, false);
      end loop;
      l_update_of := ' of ' || l_update_of;
    end if;

    l_sql := 'create or replace trigger ' || tk_util.qualified_name(l_owner, trigger_name(l_table)) || c_nl
          || '  after insert or update' || l_update_of || ' or delete on ' || tk_util.qualified_name(l_owner, l_table) || c_nl
          || '  for each row' || c_nl
          || 'declare' || c_nl
          || '  -- generated by tk_audit, do not edit: regenerate with tk_audit.enable_audit' || c_nl
          || '  l_old json_object_t := json_object_t();' || c_nl
          || '  l_new json_object_t := json_object_t();' || c_nl
          || '  l_op  varchar2(1) := case when inserting then ''I'' when updating then ''U'' else ''D'' end;' || c_nl
          || '  l_pk  varchar2(4000);' || c_nl
          || 'begin' || c_nl;

    if l_pk.count > 0 then
      l_sql := l_sql
            || '  l_pk := case when l_op = ''D'' then ' || l_pk_old || ' else ' || l_pk_new || ' end;' || c_nl;
    end if;

    for i in 1 .. l_audited.count loop
      l_key     := tk_util.quote_literal(l_audited(i).name);
      l_ref_old := ':old.' || dbms_assert.enquote_name(l_audited(i).name, false);
      l_ref_new := ':new.' || dbms_assert.enquote_name(l_audited(i).name, false);
      l_sql := l_sql
            || '  if l_op != ''U'' or ' || l_ref_old || ' != ' || l_ref_new
            || ' or (' || l_ref_old || ' is null and ' || l_ref_new || ' is not null)'
            || ' or (' || l_ref_old || ' is not null and ' || l_ref_new || ' is null) then' || c_nl
            || '    if l_op != ''I'' then l_old.put(' || l_key || ', ' || value_expr(l_ref_old, l_audited(i).data_type) || '); end if;' || c_nl
            || '    if l_op != ''D'' then l_new.put(' || l_key || ', ' || value_expr(l_ref_new, l_audited(i).data_type) || '); end if;' || c_nl
            || '  end if;' || c_nl;
    end loop;

    l_sql := l_sql
          || '  if l_op != ''U'' or l_new.get_size() > 0 then' || c_nl
          || '    ' || dbms_assert.enquote_name(c_owner, false) || '.tk_audit.log_change(' || c_nl
          || '      p_owner      => ' || tk_util.quote_literal(l_owner) || ',' || c_nl
          || '      p_table_name => ' || tk_util.quote_literal(l_table) || ',' || c_nl
          || '      p_operation  => l_op,' || c_nl
          || '      p_pk_value   => l_pk,' || c_nl
          || '      p_old_values => case when l_op != ''I'' then l_old.to_clob() end,' || c_nl
          || '      p_new_values => case when l_op != ''D'' then l_new.to_clob() end' || c_nl
          || '    );' || c_nl
          || '  end if;' || c_nl
          || 'end;';
    return l_sql;
  end generate_trigger;

  procedure enable_audit (
    p_table_name      in varchar2,
    p_owner           in varchar2 default user,
    p_columns         in varchar2 default null,
    p_exclude_columns in varchar2 default null
  ) is
    l_ddl    clob := generate_trigger(p_table_name, p_owner, p_columns, p_exclude_columns);
    l_owner  varchar2(128) := tk_util.schema_name(p_owner);
    l_name   varchar2(128) := trigger_name(p_table_name);
    l_errors varchar2(4000);
  begin
    execute immediate l_ddl;
  exception
    when e_compiled_with_errors then
      select substr(listagg(line || ': ' || text, '; ') within group (order by sequence), 1, 3900)
        into l_errors
        from all_errors
       where owner = l_owner and name = l_name and type = 'TRIGGER';
      raise_application_error(-20112, 'Audit trigger ' || l_name || ' compiled with errors: ' || l_errors);
  end enable_audit;

  procedure disable_audit (p_table_name in varchar2, p_owner in varchar2 default user) is
  begin
    execute immediate 'drop trigger ' || tk_util.qualified_name(tk_util.schema_name(p_owner), trigger_name(p_table_name));
  exception
    when e_trigger_not_found then
      null;
  end disable_audit;

  function is_enabled (p_table_name in varchar2, p_owner in varchar2 default user) return varchar2 is
    l_count pls_integer;
  begin
    select count(*)
      into l_count
      from all_triggers
     where owner = upper(trim(p_owner))
       and trigger_name = trigger_name(p_table_name)
       and status = 'ENABLED';
    return case when l_count > 0 then 'Y' else 'N' end;
  end is_enabled;

  procedure log_change (
    p_owner      in varchar2,
    p_table_name in varchar2,
    p_operation  in varchar2,
    p_pk_value   in varchar2,
    p_old_values in clob,
    p_new_values in clob
  ) is
  begin
    insert into tk_audit_log (
      table_owner, table_name, operation, pk_value, old_values, new_values,
      changed_by, db_user, client_host, module, transaction_id
    ) values (
      p_owner, p_table_name, p_operation, p_pk_value, p_old_values, p_new_values,
      coalesce(sys_context('USERENV', 'CLIENT_IDENTIFIER'), sys_context('USERENV', 'SESSION_USER')),
      sys_context('USERENV', 'SESSION_USER'),
      substr(sys_context('USERENV', 'HOST'), 1, 256),
      substr(sys_context('USERENV', 'MODULE'), 1, 64),
      dbms_transaction.local_transaction_id
    );
  end log_change;

  procedure history (
    p_table_name in varchar2,
    p_result     out sys_refcursor,
    p_pk_value   in varchar2 default null,
    p_owner      in varchar2 default user
  ) is
  begin
    open p_result for
      select audit_id, operation, pk_value, changed_by, changed_at, old_values, new_values
        from tk_audit_log
       where table_owner = upper(trim(p_owner))
         and table_name  = upper(trim(p_table_name))
         and (p_pk_value is null or pk_value = p_pk_value)
       order by audit_id;
  end history;

  procedure purge (p_older_than_days in pls_integer, p_deleted out pls_integer) is
  begin
    if p_older_than_days is null or p_older_than_days < 0 then
      raise_application_error(-20113, 'p_older_than_days must be zero or positive');
    end if;
    delete from tk_audit_log where changed_at < systimestamp - numtodsinterval(p_older_than_days, 'DAY');
    p_deleted := sql%rowcount;
  end purge;

end tk_audit;
/
