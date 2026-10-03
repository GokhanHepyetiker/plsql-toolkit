-- Toolkit tables. Idempotent: existing tables (and their data) are kept on re-install.
declare
  procedure ddl (p_sql in varchar2) is
    e_exists       exception;
    e_index_exists exception;
    pragma exception_init(e_exists, -955);
    pragma exception_init(e_index_exists, -1408);
  begin
    execute immediate p_sql;
  exception
    when e_exists or e_index_exists then null;
  end;
begin
  -- tk_audit ------------------------------------------------------------------
  ddl(q'[
    create table tk_audit_log (
      audit_id        number generated always as identity constraint tk_audit_log_pk primary key,
      table_owner     varchar2(128)  not null,
      table_name      varchar2(128)  not null,
      operation       varchar2(1)    not null constraint tk_audit_log_op_ck check (operation in ('I', 'U', 'D')),
      pk_value        varchar2(4000),
      old_values      clob           constraint tk_audit_log_old_json_ck check (old_values is json),
      new_values      clob           constraint tk_audit_log_new_json_ck check (new_values is json),
      changed_by      varchar2(128)  not null,
      db_user         varchar2(128)  not null,
      client_host     varchar2(256),
      module          varchar2(64),
      transaction_id  varchar2(64),
      changed_at      timestamp(6)   default systimestamp not null
    )]');
  ddl('create index tk_audit_log_row_ix on tk_audit_log (table_owner, table_name, pk_value)');
  ddl('create index tk_audit_log_time_ix on tk_audit_log (changed_at)');

  -- tk_dq ---------------------------------------------------------------------
  ddl(q'[
    create table tk_dq_rules (
      rule_name    varchar2(128)  constraint tk_dq_rules_pk primary key,
      description  varchar2(4000),
      table_owner  varchar2(128)  not null,
      table_name   varchar2(128)  not null,
      column_name  varchar2(128),
      rule_type    varchar2(20)   not null constraint tk_dq_rules_type_ck
                     check (rule_type in ('NOT_NULL', 'UNIQUE', 'REGEX', 'RANGE', 'IN_LIST', 'VALIDATOR', 'CUSTOM')),
      rule_param   varchar2(4000),
      severity     varchar2(10)   default 'ERROR' not null constraint tk_dq_rules_sev_ck check (severity in ('ERROR', 'WARNING')),
      is_active    varchar2(1)    default 'Y' not null constraint tk_dq_rules_active_ck check (is_active in ('Y', 'N')),
      created_at   date           default sysdate not null
    )]');
  ddl(q'[
    create table tk_dq_runs (
      run_id         number generated always as identity constraint tk_dq_runs_pk primary key,
      started_at     timestamp(6) default systimestamp not null,
      finished_at    timestamp(6),
      rules_checked  number default 0 not null,
      rules_failed   number default 0 not null,
      rules_errored  number default 0 not null
    )]');
  ddl(q'[
    create table tk_dq_results (
      run_id           number        not null constraint tk_dq_results_run_fk references tk_dq_runs on delete cascade,
      rule_name        varchar2(128) not null,
      table_owner      varchar2(128) not null,
      table_name       varchar2(128) not null,
      column_name      varchar2(128),
      severity         varchar2(10)  not null,
      checked_rows     number,
      violation_count  number,
      status           varchar2(10)  not null constraint tk_dq_results_status_ck check (status in ('PASSED', 'FAILED', 'ERROR')),
      error_message    varchar2(4000),
      elapsed_ms       number,
      constraint tk_dq_results_pk primary key (run_id, rule_name)
    )]');
end;
/
