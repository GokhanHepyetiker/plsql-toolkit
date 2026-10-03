create or replace package body tk_dq as

  c_owner constant varchar2(128) := $$plsql_unit_owner;

  function get_rule (p_rule_name in varchar2) return tk_dq_rules%rowtype is
    l_rule tk_dq_rules%rowtype;
  begin
    select * into l_rule from tk_dq_rules where rule_name = upper(trim(p_rule_name));
    return l_rule;
  exception
    when no_data_found then
      raise_application_error(-20124, 'Data quality rule ' || p_rule_name || ' does not exist');
  end get_rule;

  /** Parses 'min..max' into two numbers (either may be null). */
  procedure parse_range (p_param in varchar2, o_min out number, o_max out number) is
    l_pos pls_integer := instr(p_param, '..');
  begin
    if p_param is null or l_pos = 0 then
      raise_application_error(-20123, 'RANGE parameter must look like "min..max", got: ' || p_param);
    end if;
    begin
      o_min := to_number(trim(substr(p_param, 1, l_pos - 1)), '9999999999999999999999D9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
      o_max := to_number(trim(substr(p_param, l_pos + 2)), '9999999999999999999999D9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');
    exception
      when value_error or invalid_number then
        raise_application_error(-20123, 'RANGE bounds must be numbers with "." as decimal separator: ' || p_param);
    end;
    if o_min is null and o_max is null then
      raise_application_error(-20123, 'RANGE needs at least one bound: ' || p_param);
    end if;
    if o_min > o_max then
      raise_application_error(-20123, 'RANGE minimum is greater than maximum: ' || p_param);
    end if;
  end parse_range;

  function build_predicate (p_rule in tk_dq_rules%rowtype) return varchar2 is
    l_col   varchar2(200);
    l_min   number;
    l_max   number;
    l_items tk_util.t_strings;
    l_list  varchar2(32767);
  begin
    if p_rule.column_name is not null then
      l_col := dbms_assert.enquote_name(p_rule.column_name, false);
    end if;

    case p_rule.rule_type
      when 'NOT_NULL' then
        return l_col || ' is null';

      when 'UNIQUE' then
        return l_col || ' in (select ' || l_col || ' from '
            || tk_util.qualified_name(p_rule.table_owner, p_rule.table_name)
            || ' where ' || l_col || ' is not null group by ' || l_col || ' having count(*) > 1)';

      when 'REGEX' then
        return l_col || ' is not null and not regexp_like(' || l_col || ', ' || tk_util.quote_literal(p_rule.rule_param) || ')';

      when 'RANGE' then
        parse_range(p_rule.rule_param, l_min, l_max);
        return l_col || ' is not null and ('
            || case when l_min is not null then l_col || ' < ' || tk_util.number_literal(l_min) end
            || case when l_min is not null and l_max is not null then ' or ' end
            || case when l_max is not null then l_col || ' > ' || tk_util.number_literal(l_max) end
            || ')';

      when 'IN_LIST' then
        l_items := tk_util.split(p_rule.rule_param);
        for i in 1 .. l_items.count loop
          l_list := l_list || case when i > 1 then ', ' end || tk_util.quote_literal(l_items(i));
        end loop;
        return l_col || ' is not null and ' || l_col || ' not in (' || l_list || ')';

      when 'VALIDATOR' then
        return l_col || ' is not null and ' || dbms_assert.enquote_name(c_owner, false)
            || '.tk_validate.check_value(' || tk_util.quote_literal(p_rule.rule_param) || ', ' || l_col || ') = ''N''';

      when 'CUSTOM' then
        return '(' || p_rule.rule_param || ')';
    end case;
  end build_predicate;

  procedure validate_rule (p_rule in tk_dq_rules%rowtype) is
    l_count pls_integer;
    l_min   number;
    l_max   number;
  begin
    select count(*) into l_count
      from all_tables
     where owner = p_rule.table_owner and table_name = p_rule.table_name;
    if l_count = 0 then
      select count(*) into l_count
        from all_views
       where owner = p_rule.table_owner and view_name = p_rule.table_name;
    end if;
    if l_count = 0 then
      raise_application_error(-20120, 'Table ' || p_rule.table_owner || '.' || p_rule.table_name || ' does not exist or is not accessible');
    end if;

    if p_rule.rule_type not in ('NOT_NULL', 'UNIQUE', 'REGEX', 'RANGE', 'IN_LIST', 'VALIDATOR', 'CUSTOM') or p_rule.rule_type is null then
      raise_application_error(-20122, 'Unknown rule type: ' || p_rule.rule_type);
    end if;

    if p_rule.rule_type = 'CUSTOM' then
      if p_rule.rule_param is null then
        raise_application_error(-20123, 'CUSTOM rules need a predicate in p_rule_param');
      end if;
      if instr(p_rule.rule_param, ';') > 0 then
        raise_application_error(-20123, 'CUSTOM predicate must not contain ";"');
      end if;
    else
      if p_rule.column_name is null then
        raise_application_error(-20121, p_rule.rule_type || ' rules need a column');
      end if;
      select count(*) into l_count
        from all_tab_columns
       where owner = p_rule.table_owner and table_name = p_rule.table_name and column_name = p_rule.column_name;
      if l_count = 0 then
        raise_application_error(-20121, 'Column ' || p_rule.column_name || ' does not exist in ' || p_rule.table_name);
      end if;
    end if;

    case p_rule.rule_type
      when 'REGEX' then
        if p_rule.rule_param is null then
          raise_application_error(-20123, 'REGEX rules need a pattern');
        end if;
        begin
          -- compiles the pattern; ORA-12722 etc. for invalid expressions
          if regexp_like('x', p_rule.rule_param) then null; end if;
        exception
          when others then
            raise_application_error(-20123, 'Invalid regular expression: ' || sqlerrm);
        end;
      when 'RANGE' then
        parse_range(p_rule.rule_param, l_min, l_max);
      when 'IN_LIST' then
        if tk_util.split(p_rule.rule_param).count = 0 then
          raise_application_error(-20123, 'IN_LIST rules need at least one value');
        end if;
      when 'VALIDATOR' then
        if not tk_validate.is_known_validator(p_rule.rule_param) then
          raise_application_error(-20123, 'Unknown validator: ' || p_rule.rule_param);
        end if;
      else
        null;
    end case;
  end validate_rule;

  procedure add_rule (
    p_rule_name   in varchar2,
    p_table_name  in varchar2,
    p_rule_type   in varchar2,
    p_column_name in varchar2 default null,
    p_rule_param  in varchar2 default null,
    p_severity    in varchar2 default 'ERROR',
    p_description in varchar2 default null,
    p_owner       in varchar2 default user
  ) is
    l_rule tk_dq_rules%rowtype;
  begin
    if trim(p_rule_name) is null then
      raise_application_error(-20123, 'Rule name is required');
    end if;
    l_rule.rule_name   := upper(trim(p_rule_name));
    l_rule.table_owner := tk_util.schema_name(p_owner);
    l_rule.table_name  := upper(trim(p_table_name));
    l_rule.column_name := upper(trim(p_column_name));
    l_rule.rule_type   := upper(trim(p_rule_type));
    l_rule.rule_param  := p_rule_param;
    l_rule.severity    := upper(trim(p_severity));
    l_rule.description := p_description;
    l_rule.is_active   := 'Y';

    validate_rule(l_rule);

    merge into tk_dq_rules r
    using (select l_rule.rule_name as rule_name from dual) s
       on (r.rule_name = s.rule_name)
     when matched then update set
          r.description = l_rule.description, r.table_owner = l_rule.table_owner,
          r.table_name  = l_rule.table_name,  r.column_name = l_rule.column_name,
          r.rule_type   = l_rule.rule_type,   r.rule_param  = l_rule.rule_param,
          r.severity    = l_rule.severity,    r.is_active   = 'Y'
     when not matched then insert
          (rule_name, description, table_owner, table_name, column_name, rule_type, rule_param, severity, is_active)
          values (l_rule.rule_name, l_rule.description, l_rule.table_owner, l_rule.table_name,
                  l_rule.column_name, l_rule.rule_type, l_rule.rule_param, l_rule.severity, 'Y');
  end add_rule;

  procedure remove_rule (p_rule_name in varchar2) is
  begin
    delete from tk_dq_rules where rule_name = upper(trim(p_rule_name));
    if sql%rowcount = 0 then
      raise_application_error(-20124, 'Data quality rule ' || p_rule_name || ' does not exist');
    end if;
  end remove_rule;

  procedure set_active (p_rule_name in varchar2, p_active in boolean) is
  begin
    update tk_dq_rules
       set is_active = case when p_active then 'Y' else 'N' end
     where rule_name = upper(trim(p_rule_name));
    if sql%rowcount = 0 then
      raise_application_error(-20124, 'Data quality rule ' || p_rule_name || ' does not exist');
    end if;
  end set_active;

  function violation_predicate (p_rule_name in varchar2) return varchar2 is
  begin
    return build_predicate(get_rule(p_rule_name));
  end violation_predicate;

  function run_checks (p_table_name in varchar2 default null, p_owner in varchar2 default user) return number is
    l_run_id   number;
    l_from     varchar2(300);
    l_total    number;
    l_bad      number;
    l_started  timestamp;
    l_status   varchar2(10);
    l_error    varchar2(4000);
    l_checked  pls_integer := 0;
    l_failed   pls_integer := 0;
    l_errored  pls_integer := 0;
  begin
    insert into tk_dq_runs (started_at) values (systimestamp) returning run_id into l_run_id;

    for r in (select *
                from tk_dq_rules
               where is_active = 'Y'
                 and (p_table_name is null
                      or (table_name = upper(trim(p_table_name)) and table_owner = upper(trim(p_owner))))
               order by rule_name)
    loop
      l_started := systimestamp;
      l_total   := null;
      l_bad     := null;
      l_error   := null;
      begin
        l_from := ' from ' || tk_util.qualified_name(r.table_owner, r.table_name);
        execute immediate 'select count(*)' || l_from into l_total;
        execute immediate 'select count(*)' || l_from || ' where ' || build_predicate(r) into l_bad;
        l_status := case when l_bad = 0 then 'PASSED' else 'FAILED' end;
      exception
        when others then
          l_status := 'ERROR';
          l_error  := substr(sqlerrm, 1, 4000);
      end;

      l_checked := l_checked + 1;
      l_failed  := l_failed  + case when l_status = 'FAILED' then 1 else 0 end;
      l_errored := l_errored + case when l_status = 'ERROR'  then 1 else 0 end;

      insert into tk_dq_results (
        run_id, rule_name, table_owner, table_name, column_name, severity,
        checked_rows, violation_count, status, error_message, elapsed_ms
      ) values (
        l_run_id, r.rule_name, r.table_owner, r.table_name, r.column_name, r.severity,
        l_total, l_bad, l_status, l_error,
        round(extract(second from (systimestamp - l_started)) * 1000
              + extract(minute from (systimestamp - l_started)) * 60000)
      );
    end loop;

    update tk_dq_runs
       set finished_at = systimestamp, rules_checked = l_checked, rules_failed = l_failed, rules_errored = l_errored
     where run_id = l_run_id;

    return l_run_id;
  end run_checks;

  procedure run_summary (p_run_id in number, p_result out sys_refcursor) is
  begin
    open p_result for
      select r.rule_name, r.table_name, r.column_name, q.rule_type, r.severity, r.status,
             r.checked_rows, r.violation_count,
             case when r.checked_rows > 0 then round(100 * r.violation_count / r.checked_rows, 2) end as violation_pct,
             r.error_message, q.description
        from tk_dq_results r
        left join tk_dq_rules q on q.rule_name = r.rule_name
       where r.run_id = p_run_id
       order by case r.status when 'ERROR' then 0 when 'FAILED' then 1 else 2 end,
                case r.severity when 'ERROR' then 0 else 1 end,
                r.violation_count desc nulls last,
                r.rule_name;
  end run_summary;

  procedure violations (p_rule_name in varchar2, p_result out sys_refcursor, p_max_rows in pls_integer default 100) is
    l_rule tk_dq_rules%rowtype := get_rule(p_rule_name);
  begin
    open p_result for
      'select rowidtochar(t.rowid) as row_id, t.* from '
      || tk_util.qualified_name(l_rule.table_owner, l_rule.table_name) || ' t'
      || ' where ' || build_predicate(l_rule)
      || ' fetch first :max_rows rows only'
      using greatest(nvl(p_max_rows, 100), 1);
  end violations;

end tk_dq;
/
