create or replace package body tk_util as

  function split (
    p_list      in varchar2,
    p_delimiter in varchar2 default ','
  ) return t_strings is
    l_result t_strings := t_strings();
    l_start  pls_integer := 1;
    l_pos    pls_integer;
    l_item   varchar2(4000);
  begin
    if p_list is null then
      return l_result;
    end if;
    loop
      l_pos  := instr(p_list, p_delimiter, l_start);
      l_item := trim(case when l_pos = 0 then substr(p_list, l_start)
                          else substr(p_list, l_start, l_pos - l_start) end);
      if l_item is not null then
        l_result.extend;
        l_result(l_result.count) := l_item;
      end if;
      exit when l_pos = 0;
      l_start := l_pos + length(p_delimiter);
    end loop;
    return l_result;
  end split;

  function quote_literal (p_value in varchar2) return varchar2 is
  begin
    return '''' || replace(p_value, '''', '''''') || '''';
  end quote_literal;

  function number_literal (p_value in number) return varchar2 is
  begin
    if p_value is null then
      return 'null';
    end if;
    return to_char(p_value, 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''');
  end number_literal;

  function simple_name (p_name in varchar2) return varchar2 is
  begin
    return dbms_assert.simple_sql_name(upper(trim(p_name)));
  end simple_name;

  function schema_name (p_owner in varchar2) return varchar2 is
  begin
    return dbms_assert.schema_name(upper(trim(p_owner)));
  end schema_name;

  function qualified_name (p_owner in varchar2, p_object in varchar2) return varchar2 is
  begin
    return dbms_assert.enquote_name(p_owner, false) || '.' || dbms_assert.enquote_name(p_object, false);
  end qualified_name;

end tk_util;
/
