create or replace package tk_util authid definer as
  /**
   * Small helpers shared by the toolkit packages.
   */

  type t_strings is table of varchar2(4000);

  /** Splits a delimited list, trimming items and skipping empty ones. */
  function split (
    p_list      in varchar2,
    p_delimiter in varchar2 default ','
  ) return t_strings;

  /** Returns a safely quoted SQL string literal: O'Brien -> 'O''Brien'. */
  function quote_literal (p_value in varchar2) return varchar2;

  /** Returns a NLS-independent SQL number literal (always '.' as decimal separator). */
  function number_literal (p_value in number) return varchar2;

  /** Upper-cases and validates a simple (unquoted) Oracle identifier; raises ORA-44003 otherwise. */
  function simple_name (p_name in varchar2) return varchar2;

  /** Upper-cases and validates a schema name; raises ORA-44001 if it does not exist. */
  function schema_name (p_owner in varchar2) return varchar2;

  /** Returns "OWNER"."OBJECT" for dictionary names. */
  function qualified_name (p_owner in varchar2, p_object in varchar2) return varchar2;
end tk_util;
/
