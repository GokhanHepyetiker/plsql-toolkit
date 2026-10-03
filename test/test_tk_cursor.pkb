create or replace package body test_tk_cursor as

  c_lf constant varchar2(1) := chr(10);

  procedure reset_nls is
  begin
    execute immediate q'[alter session set nls_numeric_characters = '.,']';
  end reset_nls;

  procedure csv_basic is
    l_cursor sys_refcursor;
  begin
    open l_cursor for
      select 1 as id, 'Pen' as name from dual
      union all
      select 2, 'Book' from dual;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob('ID,NAME' || c_lf || '1,Pen' || c_lf || '2,Book' || c_lf));
  end csv_basic;

  procedure csv_quoting is
    l_cursor sys_refcursor;
  begin
    open l_cursor for
      select 'a,b' as x, 'say "hi"' as y, 'line1' || chr(10) || 'line2' as z from dual;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob(
      'X,Y,Z' || c_lf || '"a,b","say ""hi""","line1' || c_lf || 'line2"' || c_lf));
  end csv_quoting;

  procedure csv_numbers_nls is
    l_cursor sys_refcursor;
  begin
    execute immediate q'[alter session set nls_numeric_characters = ',.']';
    open l_cursor for select 1234.5 as n, 0.25 as m, -0.5 as k, 1e-3 as s from dual;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob('N,M,K,S' || c_lf || '1234.5,0.25,-0.5,0.001' || c_lf));
  end csv_numbers_nls;

  procedure csv_dates is
    l_cursor sys_refcursor;
  begin
    open l_cursor for
      select date '2026-01-15' as d,
             to_date('2026-01-15 13:45:10', 'YYYY-MM-DD HH24:MI:SS') as dt,
             timestamp '2026-01-15 13:45:00.5' as ts
        from dual;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob(
      'D,DT,TS' || c_lf || '2026-01-15T00:00:00,2026-01-15T13:45:10,2026-01-15T13:45:00.500000' || c_lf));
  end csv_dates;

  procedure csv_delimiter_nulls is
    l_cursor sys_refcursor;
  begin
    open l_cursor for select cast(null as varchar2(10)) as a, 'x;y' as b, cast(null as number) as c from dual;
    ut.expect(tk_cursor.to_csv(l_cursor, p_delimiter => ';', p_header => 'N')).to_equal(to_clob(';"x;y";' || c_lf));
  end csv_delimiter_nulls;

  procedure csv_empty is
    l_cursor sys_refcursor;
  begin
    open l_cursor for select 1 as x from dual where 1 = 0;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob('X' || c_lf));
  end csv_empty;

  procedure csv_clob is
    l_cursor sys_refcursor;
  begin
    open l_cursor for select to_clob('abc') as c from dual;
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob('C' || c_lf || 'abc' || c_lf));
  end csv_clob;

  procedure csv_large is
    l_cursor sys_refcursor;
    l_csv    clob;
  begin
    open l_cursor for select level as n, rpad('x', 100, 'x') as filler from dual connect by level <= 1000;
    l_csv := tk_cursor.to_csv(l_cursor);
    -- header "N,FILLER\n" (9) + 1000 rows of "<n>,<100 x>\n"; digits of 1..1000 = 9*1 + 90*2 + 900*3 + 4 = 2893
    ut.expect(dbms_lob.getlength(l_csv)).to_equal(9 + 1000 * 102 + 2893);
    ut.expect(dbms_lob.substr(l_csv, 10, dbms_lob.getlength(l_csv) - 9)).to_equal(rpad('x', 9, 'x') || c_lf);
  end csv_large;

  procedure csv_invalid_delimiter is
    l_cursor sys_refcursor;
    l_csv    clob;
  begin
    open l_cursor for select 1 from dual;
    l_csv := tk_cursor.to_csv(l_cursor, p_delimiter => '"');
  end csv_invalid_delimiter;

  procedure csv_closed_cursor is
    l_cursor sys_refcursor;
    l_csv    clob;
  begin
    l_csv := tk_cursor.to_csv(l_cursor);
  end csv_closed_cursor;

  procedure json_basic is
    l_cursor sys_refcursor;
  begin
    open l_cursor for
      select 1 as id, 'Pen' as name, 12.5 as price from dual
      union all
      select 2, 'Book', 0.5 from dual;
    ut.expect(tk_cursor.to_json(l_cursor)).to_equal(to_clob(
      '[{"ID":1,"NAME":"Pen","PRICE":12.5},{"ID":2,"NAME":"Book","PRICE":0.5}]'));
  end json_basic;

  procedure json_types is
    l_cursor sys_refcursor;
  begin
    open l_cursor for
      select cast(null as varchar2(10)) as s, date '2026-01-15' as d, 'say "hi"' as q from dual;
    ut.expect(tk_cursor.to_json(l_cursor)).to_equal(to_clob(
      '[{"S":null,"D":"2026-01-15T00:00:00","Q":"say \"hi\""}]'));
  end json_types;

  procedure json_empty is
    l_cursor sys_refcursor;
  begin
    open l_cursor for select 1 as x from dual where 1 = 0;
    ut.expect(tk_cursor.to_json(l_cursor)).to_equal(to_clob('[]'));
  end json_empty;

  procedure order_by_valid is
  begin
    ut.expect(tk_cursor.safe_order_by('name desc, price', 'ITEM_CODE, NAME, PRICE')).to_equal('order by NAME desc, PRICE');
    ut.expect(tk_cursor.safe_order_by('Price ASC', 'ITEM_CODE,NAME,PRICE')).to_equal('order by PRICE asc');
    ut.expect(tk_cursor.safe_order_by('i.name', 'i.name, i.price')).to_equal('order by i.name');
  end order_by_valid;

  procedure order_by_default is
  begin
    ut.expect(tk_cursor.safe_order_by(null, 'ITEM_CODE,NAME', 'item_code desc')).to_equal('order by ITEM_CODE desc');
    ut.expect(tk_cursor.safe_order_by(null, 'ITEM_CODE,NAME')).to_be_null();
  end order_by_default;

  procedure order_by_not_allowed is
    l_sql varchar2(4000);
  begin
    l_sql := tk_cursor.safe_order_by('cost', 'ITEM_CODE,NAME');
  end order_by_not_allowed;

  procedure order_by_injection is
    l_sql varchar2(4000);
  begin
    l_sql := tk_cursor.safe_order_by('name; drop table tk_audit_log', 'NAME');
  end order_by_injection;

  procedure report_pattern is
    l_cursor sys_refcursor;
    l_sql    varchar2(4000);
  begin
    -- typical report procedure body: filters are bound, sorting comes from a whitelist
    l_sql := 'select item_code, qty from ('
          || '  select ''A-1'' as item_code, 5 as qty, ''RAW'' as category from dual union all'
          || '  select ''B-2'', 9, ''RAW'' from dual union all'
          || '  select ''C-3'', 1, ''FINISHED'' from dual)'
          || ' where category = :category '
          || tk_cursor.safe_order_by('qty desc', 'ITEM_CODE,QTY', 'ITEM_CODE');
    open l_cursor for l_sql using 'RAW';
    ut.expect(tk_cursor.to_csv(l_cursor)).to_equal(to_clob('ITEM_CODE,QTY' || c_lf || 'B-2,9' || c_lf || 'A-1,5' || c_lf));
  end report_pattern;

end test_tk_cursor;
/
