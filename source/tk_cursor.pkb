create or replace package body tk_cursor as

  c_date_fmt   constant varchar2(30) := 'YYYY-MM-DD"T"HH24:MI:SS';
  c_ts_fmt     constant varchar2(40) := 'YYYY-MM-DD"T"HH24:MI:SS.FF6';
  c_tstz_fmt   constant varchar2(40) := 'YYYY-MM-DD"T"HH24:MI:SS.FF6TZH:TZM';
  c_num_nls    constant varchar2(40) := 'NLS_NUMERIC_CHARACTERS=''.,''';

  type t_kind is table of varchar2(10) index by pls_integer;

  -- Buffered CLOB writer: avoids one DBMS_LOB call per value.
  type t_writer is record (lob clob, buf varchar2(32767));

  procedure w_init (w in out nocopy t_writer) is
  begin
    dbms_lob.createtemporary(w.lob, true, dbms_lob.call);
    w.buf := null;
  end w_init;

  procedure w_append (w in out nocopy t_writer, p_text in varchar2) is
  begin
    if lengthb(w.buf) + lengthb(p_text) > 32000 then
      dbms_lob.writeappend(w.lob, length(w.buf), w.buf);
      w.buf := null;
    end if;
    if lengthb(p_text) > 32000 then
      dbms_lob.writeappend(w.lob, length(p_text), p_text);
    else
      w.buf := w.buf || p_text;
    end if;
  end w_append;

  procedure w_append_clob (w in out nocopy t_writer, p_text in clob) is
  begin
    if p_text is null or dbms_lob.getlength(p_text) = 0 then
      return;
    end if;
    if w.buf is not null then
      dbms_lob.writeappend(w.lob, length(w.buf), w.buf);
      w.buf := null;
    end if;
    dbms_lob.append(w.lob, p_text);
  end w_append_clob;

  function w_finish (w in out nocopy t_writer) return clob is
  begin
    if w.buf is not null then
      dbms_lob.writeappend(w.lob, length(w.buf), w.buf);
      w.buf := null;
    end if;
    return w.lob;
  end w_finish;

  /** Opens a DBMS_SQL cursor for the ref cursor and defines every column by its kind. */
  procedure describe (
    p_cursor in out sys_refcursor,
    o_cur    out integer,
    o_cols   out dbms_sql.desc_tab3,
    o_kinds  out t_kind
  ) is
    l_count  integer;
    l_num    number;
    l_date   date;
    l_ts     timestamp_unconstrained;
    l_tstz   timestamp_tz_unconstrained;
    l_clob   clob;
    l_blob   blob;
    l_str    varchar2(32767);
  begin
    if p_cursor is null or not p_cursor%isopen then
      raise_application_error(-20132, 'Cursor is not open');
    end if;
    o_cur := dbms_sql.to_cursor_number(p_cursor);
    dbms_sql.describe_columns3(o_cur, l_count, o_cols);
    for i in 1 .. l_count loop
      case o_cols(i).col_type
        when dbms_sql.number_type        then o_kinds(i) := 'NUMBER';  dbms_sql.define_column(o_cur, i, l_num);
        when dbms_sql.binary_float_type  then o_kinds(i) := 'NUMBER';  dbms_sql.define_column(o_cur, i, l_num);
        when dbms_sql.binary_double_type then o_kinds(i) := 'NUMBER';  dbms_sql.define_column(o_cur, i, l_num);
        when dbms_sql.date_type          then o_kinds(i) := 'DATE';    dbms_sql.define_column(o_cur, i, l_date);
        when dbms_sql.timestamp_type     then o_kinds(i) := 'TS';      dbms_sql.define_column(o_cur, i, l_ts);
        when dbms_sql.timestamp_with_tz_type then o_kinds(i) := 'TSTZ'; dbms_sql.define_column(o_cur, i, l_tstz);
        when dbms_sql.timestamp_with_local_tz_type then o_kinds(i) := 'TS'; dbms_sql.define_column(o_cur, i, l_ts);
        when dbms_sql.clob_type          then o_kinds(i) := 'CLOB';    dbms_sql.define_column(o_cur, i, l_clob);
        when dbms_sql.blob_type          then o_kinds(i) := 'SKIP';    dbms_sql.define_column(o_cur, i, l_blob);
        else                                  o_kinds(i) := 'STRING';  dbms_sql.define_column(o_cur, i, l_str, 32767);
      end case;
    end loop;
  end describe;

  /** Column value as NLS-independent text (null for SQL NULL); numbers also in o_num, CLOBs in o_clob. */
  procedure read_value (
    p_cur    in  integer,
    p_pos    in  pls_integer,
    p_kind   in  varchar2,
    o_text   out varchar2,
    o_num    out number,
    o_clob   out clob
  ) is
    l_date date;
    l_ts   timestamp_unconstrained;
    l_tstz timestamp_tz_unconstrained;
  begin
    o_text := null;
    o_num  := null;
    o_clob := null;
    case p_kind
      when 'NUMBER' then
        dbms_sql.column_value(p_cur, p_pos, o_num);
        o_text := case when o_num is not null then to_char(o_num, 'TM9', c_num_nls) end;
        -- TM9 renders 0.5 as ".5"; JSON and most CSV consumers expect a leading zero
        if o_text like '.%' then o_text := '0' || o_text; end if;
        if o_text like '-.%' then o_text := '-0' || substr(o_text, 2); end if;
      when 'DATE' then
        dbms_sql.column_value(p_cur, p_pos, l_date);
        o_text := to_char(l_date, c_date_fmt);
      when 'TS' then
        dbms_sql.column_value(p_cur, p_pos, l_ts);
        o_text := to_char(l_ts, c_ts_fmt);
      when 'TSTZ' then
        dbms_sql.column_value(p_cur, p_pos, l_tstz);
        o_text := to_char(l_tstz, c_tstz_fmt);
      when 'CLOB' then
        dbms_sql.column_value(p_cur, p_pos, o_clob);
      when 'SKIP' then
        null;
      else
        dbms_sql.column_value(p_cur, p_pos, o_text);
    end case;
  end read_value;

  function csv_field (p_value in varchar2, p_delimiter in varchar2) return varchar2 is
  begin
    if p_value is null then
      return null;
    end if;
    if instr(p_value, p_delimiter) > 0 or instr(p_value, '"') > 0
       or instr(p_value, chr(10)) > 0 or instr(p_value, chr(13)) > 0
    then
      return '"' || replace(p_value, '"', '""') || '"';
    end if;
    return p_value;
  end csv_field;

  function to_csv (
    p_cursor      in out sys_refcursor,
    p_delimiter   in varchar2 default ',',
    p_header      in varchar2 default 'Y',
    p_line_break  in varchar2 default chr(10)
  ) return clob is
    l_cur   integer;
    l_cols  dbms_sql.desc_tab3;
    l_kinds t_kind;
    l_text  varchar2(32767);
    l_num   number;
    l_clob  clob;
    l_w     t_writer;
  begin
    if p_delimiter is null or length(p_delimiter) != 1 or p_delimiter in ('"', chr(10), chr(13)) then
      raise_application_error(-20132, 'Delimiter must be a single character other than quote or line break');
    end if;

    describe(p_cursor, l_cur, l_cols, l_kinds);
    w_init(l_w);
    begin
      if upper(p_header) = 'Y' then
        for i in 1 .. l_cols.count loop
          w_append(l_w, case when i > 1 then p_delimiter end || csv_field(l_cols(i).col_name, p_delimiter));
        end loop;
        w_append(l_w, p_line_break);
      end if;

      while dbms_sql.fetch_rows(l_cur) > 0 loop
        for i in 1 .. l_cols.count loop
          if i > 1 then
            w_append(l_w, p_delimiter);
          end if;
          read_value(l_cur, i, l_kinds(i), l_text, l_num, l_clob);
          if l_kinds(i) = 'CLOB' then
            l_text := dbms_lob.substr(l_clob, 32000, 1);
          end if;
          w_append(l_w, csv_field(l_text, p_delimiter));
        end loop;
        w_append(l_w, p_line_break);
      end loop;
      dbms_sql.close_cursor(l_cur);
    exception
      when others then
        if dbms_sql.is_open(l_cur) then
          dbms_sql.close_cursor(l_cur);
        end if;
        raise;
    end;
    return w_finish(l_w);
  end to_csv;

  function to_json (p_cursor in out sys_refcursor) return clob is
    l_cur   integer;
    l_cols  dbms_sql.desc_tab3;
    l_kinds t_kind;
    l_text  varchar2(32767);
    l_num   number;
    l_clob  clob;
    l_row   json_object_t;
    l_w     t_writer;
    l_first boolean := true;
  begin
    describe(p_cursor, l_cur, l_cols, l_kinds);
    w_init(l_w);
    w_append(l_w, '[');
    begin
      while dbms_sql.fetch_rows(l_cur) > 0 loop
        l_row := json_object_t();
        for i in 1 .. l_cols.count loop
          read_value(l_cur, i, l_kinds(i), l_text, l_num, l_clob);
          if l_kinds(i) = 'CLOB' then
            l_text := dbms_lob.substr(l_clob, 32767, 1);
          end if;
          if l_text is null then
            l_row.put_null(l_cols(i).col_name);
          elsif l_kinds(i) = 'NUMBER' then
            l_row.put(l_cols(i).col_name, l_num);
          else
            l_row.put(l_cols(i).col_name, l_text);
          end if;
        end loop;
        w_append(l_w, case when not l_first then ',' end);
        w_append_clob(l_w, l_row.to_clob());
        l_first := false;
      end loop;
      dbms_sql.close_cursor(l_cur);
    exception
      when others then
        if dbms_sql.is_open(l_cur) then
          dbms_sql.close_cursor(l_cur);
        end if;
        raise;
    end;
    w_append(l_w, ']');
    return w_finish(l_w);
  end to_json;

  function safe_order_by (
    p_requested in varchar2,
    p_allowed   in varchar2,
    p_default   in varchar2 default null
  ) return varchar2 is
    l_allowed tk_util.t_strings := tk_util.split(p_allowed);
    l_items   tk_util.t_strings := tk_util.split(nvl(p_requested, p_default));
    l_result  varchar2(4000);
    l_col     varchar2(4000);
    l_dir     varchar2(4000);
    l_match   varchar2(4000);
  begin
    if l_allowed.count = 0 then
      raise_application_error(-20132, 'The list of allowed sort columns is empty');
    end if;
    if l_items.count = 0 then
      return null;
    end if;

    for i in 1 .. l_items.count loop
      if not regexp_like(l_items(i), '^[A-Za-z0-9_$#."]+(\s+(asc|desc))?$', 'i') then
        raise_application_error(-20131, 'Invalid sort expression: ' || l_items(i));
      end if;
      l_col := regexp_substr(l_items(i), '^\S+');
      l_dir := lower(regexp_substr(l_items(i), '\s+(asc|desc)$', 1, 1, 'i', 1));

      -- the whitelist entry (not the user input) is what ends up in the SQL text
      l_match := null;
      for j in 1 .. l_allowed.count loop
        if upper(l_allowed(j)) = upper(l_col) then
          l_match := l_allowed(j);
          exit;
        end if;
      end loop;
      if l_match is null then
        raise_application_error(-20130, 'Sorting by "' || substr(l_col, 1, 100) || '" is not allowed');
      end if;

      l_result := l_result || case when i > 1 then ', ' end || l_match || case when l_dir is not null then ' ' || l_dir end;
    end loop;

    return 'order by ' || l_result;
  end safe_order_by;

end tk_cursor;
/
