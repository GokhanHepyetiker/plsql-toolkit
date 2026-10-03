create or replace package test_tk_validate as
  --%suite(tk_validate - Turkish and generic validators)
  --%suitepath(toolkit)

  --%test(TCKN: accepts valid identity numbers)
  procedure tckn_valid;

  --%test(TCKN: rejects wrong check digits, length, leading zero and non-digits)
  procedure tckn_invalid;

  --%test(VKN: accepts valid tax numbers)
  procedure vkn_valid;

  --%test(VKN: rejects wrong check digit and format)
  procedure vkn_invalid;

  --%test(TAX_ID: dispatches on length to TCKN or VKN)
  procedure tax_id;

  --%test(IBAN: accepts valid IBANs with spaces and lower case)
  procedure iban_valid;

  --%test(IBAN: rejects wrong checksum, length and characters)
  procedure iban_invalid;

  --%test(IBAN: normalizes and formats in groups of four)
  procedure iban_format;

  --%test(E-mail: accepts and rejects typical addresses)
  procedure email;

  --%test(Mobile: accepts all common Turkish notations and normalizes to E.164)
  procedure tr_mobile;

  --%test(Plate: validates Turkish plates and normalizes spacing)
  procedure tr_plate;

  --%test(Date: validates with an exact format mask)
  procedure is_date;

  --%test(All validators return null for null input)
  procedure null_input;

  --%test(check_value dispatches by validator name)
  procedure check_value_dispatch;

  --%test(check_value raises -20100 for an unknown validator)
  --%throws(-20100)
  procedure check_value_unknown;

  --%test(Validators can be used directly in SQL)
  procedure usable_in_sql;
end test_tk_validate;
/
