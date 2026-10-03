create or replace package body test_tk_validate as

  procedure expect_all (p_type in varchar2, p_values in tk_util.t_strings, p_expected in varchar2) is
  begin
    for i in 1 .. p_values.count loop
      ut.expect(tk_validate.check_value(p_type, p_values(i)), p_type || ' "' || p_values(i) || '"').to_equal(p_expected);
    end loop;
  end expect_all;

  procedure tckn_valid is
  begin
    expect_all('TCKN', tk_util.t_strings('10000000146', '12345678950', '98765432150', '55555555550'), 'Y');
  end;

  procedure tckn_invalid is
  begin
    expect_all('TCKN', tk_util.t_strings(
      '10000000147',   -- wrong 11th digit
      '10000000136',   -- wrong 10th digit
      '02345678950',   -- leading zero
      '1234567895',    -- 10 digits
      '123456789501',  -- 12 digits
      '1234567895A',   -- non-digit
      ' 10000000146'   -- whitespace is a data quality issue too
    ), 'N');
  end;

  procedure vkn_valid is
  begin
    expect_all('VKN', tk_util.t_strings('1234567890', '9876543217', '4720000003', '0000000001', '1111111114'), 'Y');
  end;

  procedure vkn_invalid is
  begin
    expect_all('VKN', tk_util.t_strings('1234567891', '9876543210', '123456789', '12345678901', 'ABCDEFGHIJ'), 'N');
  end;

  procedure tax_id is
  begin
    expect_all('TAX_ID', tk_util.t_strings('10000000146', '1234567890'), 'Y');
    expect_all('TAX_ID', tk_util.t_strings('10000000147', '1234567891', '12345'), 'N');
  end;

  procedure iban_valid is
  begin
    expect_all('IBAN', tk_util.t_strings(
      'TR330006100519786457841326',
      'TR33 0006 1005 1978 6457 8413 26',
      'tr330006100519786457841326',
      'TR320010009999901234567890',
      'DE89370400440532013000',
      'GB82WEST12345698765432'
    ), 'Y');
  end;

  procedure iban_invalid is
  begin
    expect_all('IBAN', tk_util.t_strings(
      'TR330006100519786457841327',  -- checksum
      'TR33000610051978645784132',   -- too short for TR
      'TR3300061005197864578413261', -- too long for TR
      'DE8937040044053201300',       -- too short for DE
      'TR33-0006-1005-1978-6457-8413-26',
      'TR',
      'NOT AN IBAN'
    ), 'N');
  end;

  procedure iban_format is
  begin
    ut.expect(tk_validate.normalize_iban('tr33 0006 1005 1978 6457 8413 26')).to_equal('TR330006100519786457841326');
    ut.expect(tk_validate.format_iban('TR330006100519786457841326')).to_equal('TR33 0006 1005 1978 6457 8413 26');
    ut.expect(tk_validate.normalize_iban('TR330006100519786457841327')).to_be_null();
  end;

  procedure email is
  begin
    expect_all('EMAIL', tk_util.t_strings('gokhan@example.com', 'first.last+erp@sub.domain.com.tr', 'a_b-c@x-y.io'), 'Y');
    expect_all('EMAIL', tk_util.t_strings(
      'no-at.example.com', 'a@b', 'a..b@example.com', '.a@example.com', 'a.@example.com', 'a@exa mple.com', 'a@@example.com'
    ), 'N');
  end;

  procedure tr_mobile is
  begin
    expect_all('TR_MOBILE', tk_util.t_strings(
      '05321234567', '+90 (532) 123-45-67', '5321234567', '0090 532 123 45 67', '905321234567', '0532.123.45.67'
    ), 'Y');
    expect_all('TR_MOBILE', tk_util.t_strings(
      '02121234567',          -- landline
      '0532123456',           -- too short
      '+90 532 123 45 678',   -- too long
      '+49 532 123 45 67',    -- other country
      'abc'
    ), 'N');
    ut.expect(tk_validate.normalize_tr_mobile('0532 123 45 67')).to_equal('+905321234567');
    ut.expect(tk_validate.normalize_tr_mobile('0212 123 45 67')).to_be_null();
  end;

  procedure tr_plate is
  begin
    expect_all('TR_PLATE', tk_util.t_strings(
      '46 ABC 123', '34 A 1234', '34 A 12345', '06AB123', '06 AB 1234', '01 abc 12', '81 ZZ 999'
    ), 'Y');
    expect_all('TR_PLATE', tk_util.t_strings(
      '00 ABC 123',   -- province 00
      '82 ABC 123',   -- province 82
      '34 QWX 123',   -- Q, W, X are not used
      '34 ABCD 12',   -- 4 letters
      '34 ABC 1234',  -- 3 letters need 2-3 digits
      '34 A 123',     -- 1 letter needs 4-5 digits
      '3A ABC 12'
    ), 'N');
    ut.expect(tk_validate.normalize_tr_plate('46abc123')).to_equal('46 ABC 123');
    ut.expect(tk_validate.normalize_tr_plate(' 34  a 1234 ')).to_equal('34 A 1234');
  end;

  procedure is_date is
  begin
    ut.expect(tk_validate.is_date('2026-02-28')).to_equal('Y');
    ut.expect(tk_validate.is_date('2024-02-29')).to_equal('Y');
    ut.expect(tk_validate.is_date('2026-02-29')).to_equal('N');
    ut.expect(tk_validate.is_date('2026-2-5')).to_equal('N');
    ut.expect(tk_validate.is_date('15.01.2026', 'DD.MM.YYYY')).to_equal('Y');
    ut.expect(tk_validate.is_date('2026-01-15', 'DD.MM.YYYY')).to_equal('N');
  end;

  procedure null_input is
  begin
    for t in (select column_value as name
                from table(sys.odcivarchar2list('TCKN', 'VKN', 'TAX_ID', 'IBAN', 'EMAIL', 'TR_MOBILE', 'TR_PLATE', 'DATE')))
    loop
      ut.expect(tk_validate.check_value(t.name, null), t.name).to_be_null();
    end loop;
  end;

  procedure check_value_dispatch is
  begin
    ut.expect(tk_validate.check_value('iban', 'TR330006100519786457841326')).to_equal('Y');
    ut.expect(tk_validate.check_value(' Tckn ', '10000000146')).to_equal('Y');
    ut.expect(tk_validate.check_value('DATE:DD.MM.YYYY', '15.01.2026')).to_equal('Y');
    ut.expect(tk_validate.is_known_validator('tr_plate')).to_be_true();
    ut.expect(tk_validate.is_known_validator('DATE:YYYYMMDD')).to_be_true();
    ut.expect(tk_validate.is_known_validator('DATE:')).to_be_false();
    ut.expect(tk_validate.is_known_validator('SSN')).to_be_false();
  end;

  procedure check_value_unknown is
    l_result varchar2(1);
  begin
    l_result := tk_validate.check_value('SSN', '123');
  end;

  procedure usable_in_sql is
    l_invalid number;
  begin
    select count(*)
      into l_invalid
      from (select '10000000146' as tckn from dual
            union all select '10000000147' from dual
            union all select null from dual)
     where tk_validate.is_tckn(tckn) = 'N';
    ut.expect(l_invalid).to_equal(1);
  end;

end test_tk_validate;
/
