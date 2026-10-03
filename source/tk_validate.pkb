create or replace package body tk_validate as

  function yn (p_condition in boolean) return varchar2 is
  begin
    return case when p_condition then c_valid else c_invalid end;
  end yn;

  function digit (p_value in varchar2, p_pos in pls_integer) return pls_integer is
  begin
    return to_number(substr(p_value, p_pos, 1));
  end digit;

  function is_tckn (p_value in varchar2) return varchar2 deterministic is
    l_odd  pls_integer := 0;
    l_even pls_integer := 0;
  begin
    if p_value is null then
      return null;
    end if;
    if not regexp_like(p_value, '^[1-9][0-9]{10}$') then
      return c_invalid;
    end if;

    for i in 1 .. 9 loop
      if mod(i, 2) = 1 then
        l_odd := l_odd + digit(p_value, i);
      else
        l_even := l_even + digit(p_value, i);
      end if;
    end loop;

    -- 10th digit: ((sum of odd positions * 7) - sum of even positions) mod 10
    if mod(mod(l_odd * 7 - l_even, 10) + 10, 10) != digit(p_value, 10) then
      return c_invalid;
    end if;
    -- 11th digit: sum of the first 10 digits mod 10
    return yn(mod(l_odd + l_even + digit(p_value, 10), 10) = digit(p_value, 11));
  end is_tckn;

  function is_vkn (p_value in varchar2) return varchar2 deterministic is
    l_tmp pls_integer;
    l_val pls_integer;
    l_sum pls_integer := 0;
  begin
    if p_value is null then
      return null;
    end if;
    if not regexp_like(p_value, '^[0-9]{10}$') then
      return c_invalid;
    end if;

    for i in 1 .. 9 loop
      l_tmp := mod(digit(p_value, i) + (10 - i), 10);
      if l_tmp = 0 then
        l_val := 0;
      else
        l_val := mod(l_tmp * power(2, 10 - i), 9);
        if l_val = 0 then
          l_val := 9;
        end if;
      end if;
      l_sum := l_sum + l_val;
    end loop;

    return yn(mod(10 - mod(l_sum, 10), 10) = digit(p_value, 10));
  end is_vkn;

  function is_tax_id (p_value in varchar2) return varchar2 deterministic is
  begin
    if p_value is null then
      return null;
    end if;
    return case length(p_value)
             when 11 then is_tckn(p_value)
             when 10 then is_vkn(p_value)
             else c_invalid
           end;
  end is_tax_id;

  function iban_length (p_country in varchar2) return pls_integer is
  begin
    return case p_country
             when 'TR' then 26 when 'DE' then 22 when 'GB' then 22 when 'FR' then 27
             when 'IT' then 27 when 'ES' then 24 when 'NL' then 18 when 'BE' then 16
             when 'AT' then 20 when 'CH' then 21 when 'PL' then 28 when 'SE' then 24
             when 'FI' then 18 when 'DK' then 18 when 'NO' then 15 when 'PT' then 25
             when 'IE' then 22 when 'GR' then 27 when 'AZ' then 28 when 'GE' then 22
             when 'AE' then 23 when 'SA' then 24 when 'BG' then 22 when 'RO' then 24
             else null
           end;
  end iban_length;

  function compact_iban (p_value in varchar2) return varchar2 is
  begin
    return upper(regexp_replace(p_value, '\s', ''));
  end compact_iban;

  function is_iban (p_value in varchar2) return varchar2 deterministic is
    l_iban      varchar2(100);
    l_expected  pls_integer;
    l_rearr     varchar2(100);
    l_remainder pls_integer := 0;
    l_char      varchar2(1);
  begin
    if p_value is null then
      return null;
    end if;
    if length(p_value) > 100 then
      return c_invalid;
    end if;

    l_iban := compact_iban(p_value);
    if not regexp_like(l_iban, '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$') then
      return c_invalid;
    end if;

    l_expected := iban_length(substr(l_iban, 1, 2));
    if l_expected is not null and length(l_iban) != l_expected then
      return c_invalid;
    end if;
    -- Turkish IBANs: 5-digit bank code, a reserved '0', then 16 account characters
    if substr(l_iban, 1, 2) = 'TR' and not regexp_like(l_iban, '^TR[0-9]{2}[0-9]{5}0[A-Z0-9]{16}$') then
      return c_invalid;
    end if;

    -- mod-97 over the rearranged IBAN, letters mapped to 10..35, computed digit by digit
    l_rearr := substr(l_iban, 5) || substr(l_iban, 1, 4);
    for i in 1 .. length(l_rearr) loop
      l_char := substr(l_rearr, i, 1);
      if l_char between '0' and '9' then
        l_remainder := mod(l_remainder * 10 + to_number(l_char), 97);
      else
        l_remainder := mod(l_remainder * 100 + (ascii(l_char) - 55), 97);
      end if;
    end loop;

    return yn(l_remainder = 1);
  end is_iban;

  function is_email (p_value in varchar2) return varchar2 deterministic is
  begin
    if p_value is null then
      return null;
    end if;
    return yn(
      length(p_value) <= 254
      and regexp_like(p_value, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$')
      and instr(p_value, '..') = 0
      and substr(p_value, 1, 1) != '.'
      and instr(p_value, '.@') = 0
    );
  end is_email;

  function compact_phone (p_value in varchar2) return varchar2 is
  begin
    return regexp_replace(p_value, '[ ().-]', '');
  end compact_phone;

  function is_tr_mobile (p_value in varchar2) return varchar2 deterministic is
  begin
    if p_value is null then
      return null;
    end if;
    return yn(regexp_like(compact_phone(p_value), '^(\+90|0090|90|0)?5[0-9]{9}$'));
  end is_tr_mobile;

  function compact_plate (p_value in varchar2) return varchar2 is
  begin
    return upper(regexp_replace(p_value, '\s', ''));
  end compact_plate;

  function is_tr_plate (p_value in varchar2) return varchar2 deterministic is
    -- province 01..81; letters exclude Q, W, X and Turkish-specific characters
    c_province constant varchar2(30) := '^(0[1-9]|[1-7][0-9]|8[01])';
    c_letter   constant varchar2(20) := '[A-PR-VYZ]';
    l_plate    varchar2(100);
  begin
    if p_value is null then
      return null;
    end if;
    if length(p_value) > 20 then
      return c_invalid;
    end if;
    l_plate := compact_plate(p_value);
    return yn(
         regexp_like(l_plate, c_province || c_letter || '[0-9]{4,5}$')
      or regexp_like(l_plate, c_province || c_letter || '{2}[0-9]{3,4}$')
      or regexp_like(l_plate, c_province || c_letter || '{3}[0-9]{2,3}$')
    );
  end is_tr_plate;

  function is_date (p_value in varchar2, p_format in varchar2 default 'YYYY-MM-DD') return varchar2 deterministic is
    l_date date;
  begin
    if p_value is null then
      return null;
    end if;
    l_date := to_date(p_value, 'FX' || p_format);
    return c_valid;
  exception
    when others then
      return c_invalid;
  end is_date;

  function normalize_iban (p_value in varchar2) return varchar2 deterministic is
  begin
    return case when is_iban(p_value) = c_valid then compact_iban(p_value) end;
  end normalize_iban;

  function format_iban (p_value in varchar2) return varchar2 deterministic is
  begin
    return trim(regexp_replace(normalize_iban(p_value), '(.{4})', '\1 '));
  end format_iban;

  function normalize_tr_mobile (p_value in varchar2) return varchar2 deterministic is
    l_digits varchar2(100);
  begin
    if is_tr_mobile(p_value) = c_valid then
      l_digits := compact_phone(p_value);
      return '+90' || substr(l_digits, -10);
    end if;
    return null;
  end normalize_tr_mobile;

  function normalize_tr_plate (p_value in varchar2) return varchar2 deterministic is
  begin
    if is_tr_plate(p_value) = c_valid then
      return regexp_replace(compact_plate(p_value), '^([0-9]{2})([A-Z]+)([0-9]+)$', '\1 \2 \3');
    end if;
    return null;
  end normalize_tr_plate;

  function raise_unknown (p_type in varchar2) return varchar2 is
  begin
    raise_application_error(-20100, 'Unknown validator: ' || p_type);
    return null;
  end raise_unknown;

  function check_value (p_type in varchar2, p_value in varchar2) return varchar2 deterministic is
    l_type varchar2(200) := upper(trim(p_type));
  begin
    if l_type like 'DATE:%' then
      return is_date(p_value, substr(trim(p_type), 6));
    end if;
    return case l_type
             when 'TCKN'      then is_tckn(p_value)
             when 'VKN'       then is_vkn(p_value)
             when 'TAX_ID'    then is_tax_id(p_value)
             when 'IBAN'      then is_iban(p_value)
             when 'EMAIL'     then is_email(p_value)
             when 'TR_MOBILE' then is_tr_mobile(p_value)
             when 'TR_PLATE'  then is_tr_plate(p_value)
             when 'DATE'      then is_date(p_value)
             else raise_unknown(p_type)
           end;
  end check_value;

  function is_known_validator (p_type in varchar2) return boolean is
    l_type varchar2(200) := upper(trim(p_type));
  begin
    return l_type in ('TCKN', 'VKN', 'TAX_ID', 'IBAN', 'EMAIL', 'TR_MOBILE', 'TR_PLATE', 'DATE')
        or (l_type like 'DATE:_%');
  end is_known_validator;

end tk_validate;
/
