-- Runs all utPLSQL suites of the current schema.
whenever sqlerror exit failure
set serveroutput on size unlimited format wrapped
set feedback off
set linesize 250
set trimspool on

begin
  ut.run(ut_documentation_reporter(), a_color_console => false);
end;
/
exit
