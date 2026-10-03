create or replace package tk_validate authid definer as
  /**
   * Validators for common ERP master data, with a focus on Turkish formats.
   *
   * Every is_* function returns:
   *   'Y'  - the value is valid
   *   'N'  - the value is invalid
   *   null - the input is null (so "NOT NULL" stays a separate concern)
   *
   * Because they return VARCHAR2 instead of BOOLEAN, they can be used directly in SQL:
   *   select * from customers where tk_validate.is_iban(iban) = 'N';
   */

  c_valid   constant varchar2(1) := 'Y';
  c_invalid constant varchar2(1) := 'N';

  /** Turkish national identity number (T.C. Kimlik No): 11 digits with two check digits. */
  function is_tckn (p_value in varchar2) return varchar2 deterministic;

  /** Turkish tax number (Vergi Kimlik No): 10 digits with a check digit. */
  function is_vkn (p_value in varchar2) return varchar2 deterministic;

  /** TCKN for individuals or VKN for companies. */
  function is_tax_id (p_value in varchar2) return varchar2 deterministic;

  /** IBAN (ISO 13616, mod-97). Spaces are ignored, country specific lengths are checked. */
  function is_iban (p_value in varchar2) return varchar2 deterministic;

  /** Pragmatic e-mail address check (local@domain.tld). */
  function is_email (p_value in varchar2) return varchar2 deterministic;

  /** Turkish mobile number in any common notation: 0532 123 45 67, +90 (532) 123-4567, 5321234567. */
  function is_tr_mobile (p_value in varchar2) return varchar2 deterministic;

  /** Turkish vehicle registration plate, e.g. 46 ABC 123, 34 A 1234, 06AB123. */
  function is_tr_plate (p_value in varchar2) return varchar2 deterministic;

  /** True if the string can be converted to a date with exactly the given format. */
  function is_date (p_value in varchar2, p_format in varchar2 default 'YYYY-MM-DD') return varchar2 deterministic;

  /** Removes spaces and upper-cases an IBAN; returns null if it is not valid. */
  function normalize_iban (p_value in varchar2) return varchar2 deterministic;

  /** Formats a valid IBAN in groups of four: TR33 0006 1005 ... ; null if invalid. */
  function format_iban (p_value in varchar2) return varchar2 deterministic;

  /** Returns a valid Turkish mobile number in E.164 format (+905321234567); null if invalid. */
  function normalize_tr_mobile (p_value in varchar2) return varchar2 deterministic;

  /** Returns a valid plate in canonical form (46 ABC 123); null if invalid. */
  function normalize_tr_plate (p_value in varchar2) return varchar2 deterministic;

  /**
   * Generic dispatcher used by tk_dq rules.
   * p_type: TCKN, VKN, TAX_ID, IBAN, EMAIL, TR_MOBILE, TR_PLATE or DATE[:format] (e.g. DATE:DD.MM.YYYY).
   * Raises -20100 for an unknown validator.
   */
  function check_value (p_type in varchar2, p_value in varchar2) return varchar2 deterministic;

  /** True if p_type is a validator name accepted by check_value. */
  function is_known_validator (p_type in varchar2) return boolean;
end tk_validate;
/
