# PL/SQL Toolkit

[![CI](https://github.com/GokhanHepyetiker/plsql-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/GokhanHepyetiker/plsql-toolkit/actions/workflows/ci.yml)
![Oracle](https://img.shields.io/badge/Oracle-19c%20%7C%2021c%20%7C%2023ai-F80000?logo=oracle&logoColor=white)
![Tests](https://img.shields.io/badge/utPLSQL-70%20tests-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

Reusable, tested **Oracle PL/SQL packages** for everyday ERP development. These are the utilities that every ERP team ends up writing again: audit trails, master data validation, data quality checks and report exports. Here they are written once, documented and covered by **utPLSQL** tests.

| Package       | What it does                                                                                              |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| `tk_audit`    | **Generates audit triggers** from the data dictionary. Changes are logged as JSON, and only changed columns are logged on UPDATE. |
| `tk_validate` | **Validators** for TCKN, VKN, IBAN, e-mail, Turkish mobile numbers and vehicle plates, usable directly in SQL. |
| `tk_dq`       | **Data quality rule engine**: declare rules in a table, run them, and get a summary and the offending rows. |
| `tk_cursor`   | **SYS_REFCURSOR helpers**: any cursor to CSV/JSON (NLS independent), and SQL-injection-safe dynamic `ORDER BY`. |

No dependencies, no extra licences. Plain PL/SQL for Oracle Database 19c and later.

---

## Quick tour

### `tk_validate` – Turkish master data checks in SQL

```sql
select customer_code, tax_id,
       tk_validate.is_tax_id(tax_id)           as tax_ok,
       tk_validate.is_iban(iban)               as iban_ok,
       tk_validate.is_email(email)             as email_ok,
       tk_validate.normalize_tr_mobile(mobile) as mobile_e164
  from demo_customers;
```

```
CUSTOM TAX_ID      TAX_OK IBAN_OK EMAIL_OK MOBILE_E164
------ ----------- ------ ------- -------- --------------
C-001  1234567890  Y      Y       Y        +905321234567
C-002  1234567891  N      N       N        +905321234567
C-003  10000000146 Y              Y
C-004  1234567890  Y      Y                +905051234567
C-005  9876543217  Y      Y       Y        +905051234567
```

Validators return `'Y'`, `'N'`, or `NULL` for NULL input, so they work in `WHERE` clauses, check constraints and views. A missing value is a separate concern that `NOT_NULL` rules handle.

| Function                         | Validates                                                                    |
| -------------------------------- | ---------------------------------------------------------------------------- |
| `is_tckn`                        | T.C. Kimlik No (11 digits, both check digits)                                |
| `is_vkn`                         | Vergi Kimlik No (10 digits, check digit)                                     |
| `is_tax_id`                      | TCKN or VKN depending on length                                              |
| `is_iban`                        | ISO 13616 mod-97, country lengths (24 countries), TR reserved digit, spaces allowed |
| `is_email`                       | Pragmatic `local@domain.tld` check                                           |
| `is_tr_mobile`                   | `0532 123 45 67`, `+90 (532) 123-4567`, `5321234567`, …                      |
| `is_tr_plate`                    | `46 ABC 123`, `34 A 1234`, `06AB123` (province 01–81, letter/digit rules)    |
| `is_date(value, format)`         | Exact format match (`FX`), e.g. `DD.MM.YYYY`                                 |
| `normalize_iban` / `format_iban` | `TR330006100519786457841326` / `TR33 0006 1005 1978 6457 8413 26`            |
| `normalize_tr_mobile`            | E.164: `+905321234567`                                                       |
| `normalize_tr_plate`             | `46 ABC 123`                                                                 |

### `tk_audit` – audit trail with one call

```sql
begin
  -- LAST_UPDATE_DATE changes on every save in most ERPs, so leave it out to avoid noise
  tk_audit.enable_audit('DEMO_CUSTOMERS', p_exclude_columns => 'LAST_UPDATE_DATE');
end;
/

exec dbms_session.set_identifier('ayse.kaya')   -- the ERP application user

insert into demo_customers (customer_id, customer_code, name, city, credit_limit, status)
values (6, 'C-006', 'Konya Ambalaj', 'KONYA', 10000, 'ACTIVE');
update demo_customers set credit_limit = 15000, last_update_date = sysdate where customer_id = 6;
update demo_customers set last_update_date = sysdate where customer_id = 6;  -- not logged
delete from demo_customers where customer_id = 6;
```

```
OP PK CHANGED_BY OLD_VALUES                                NEW_VALUES
-- -- ---------- ----------------------------------------- -----------------------------------------------
I  6  ayse.kaya                                            {"CUSTOMER_ID":6,"CUSTOMER_CODE":"C-006",
                                                            "NAME":"Konya Ambalaj",...,"CREDIT_LIMIT":10000}
U  6  ayse.kaya  {"CREDIT_LIMIT":10000}                    {"CREDIT_LIMIT":15000}
D  6  ayse.kaya  {"CUSTOMER_ID":6,...,"CREDIT_LIMIT":15000}
```

- **UPDATEs log only the columns that changed**, using a null-safe comparison. An UPDATE that changes nothing, or only excluded columns, is not logged.
- `changed_by` is the **application user** (`CLIENT_IDENTIFIER`) when the ERP sets it, and the DB user otherwise. `db_user`, `client_host`, `module` and `transaction_id` are stored too.
- Audit rows are written in the **same transaction** as the change, so a rollback removes both.
- `p_columns => 'PRICE, STATUS'` audits only those columns and generates `UPDATE OF` so the trigger doesn't even fire for other columns.
- DATE and TIMESTAMP values are stored as ISO-8601. Numbers stay JSON numbers. LOB, LONG and object columns are skipped.
- `tk_audit.generate_trigger(...)` returns the DDL without running it, for code review or deployment scripts.

<details>
<summary>Generated trigger (<code>p_columns =&gt; 'NAME, CREDIT_LIMIT'</code>)</summary>

```sql
create or replace trigger "TOOLKIT"."TK_AUD_DEMO_CUSTOMERS"
  after insert or update of "NAME", "CREDIT_LIMIT" or delete on "TOOLKIT"."DEMO_CUSTOMERS"
  for each row
declare
  -- generated by tk_audit, do not edit: regenerate with tk_audit.enable_audit
  l_old json_object_t := json_object_t();
  l_new json_object_t := json_object_t();
  l_op  varchar2(1) := case when inserting then 'I' when updating then 'U' else 'D' end;
  l_pk  varchar2(4000);
begin
  l_pk := case when l_op = 'D' then to_char(:old."CUSTOMER_ID") else to_char(:new."CUSTOMER_ID") end;
  if l_op != 'U' or :old."NAME" != :new."NAME" or (:old."NAME" is null and :new."NAME" is not null) or (:old."NAME" is not null and :new."NAME" is null) then
    if l_op != 'I' then l_old.put('NAME', :old."NAME"); end if;
    if l_op != 'D' then l_new.put('NAME', :new."NAME"); end if;
  end if;
  if l_op != 'U' or :old."CREDIT_LIMIT" != :new."CREDIT_LIMIT" or (:old."CREDIT_LIMIT" is null and :new."CREDIT_LIMIT" is not null) or (:old."CREDIT_LIMIT" is not null and :new."CREDIT_LIMIT" is null) then
    if l_op != 'I' then l_old.put('CREDIT_LIMIT', :old."CREDIT_LIMIT"); end if;
    if l_op != 'D' then l_new.put('CREDIT_LIMIT', :new."CREDIT_LIMIT"); end if;
  end if;
  if l_op != 'U' or l_new.get_size() > 0 then
    "TOOLKIT".tk_audit.log_change(
      p_owner      => 'TOOLKIT',
      p_table_name => 'DEMO_CUSTOMERS',
      p_operation  => l_op,
      p_pk_value   => l_pk,
      p_old_values => case when l_op != 'I' then l_old.to_clob() end,
      p_new_values => case when l_op != 'D' then l_new.to_clob() end
    );
  end if;
end;
```

</details>

### `tk_dq` – data quality rules

```sql
begin
  tk_dq.add_rule('CUST_NAME_REQUIRED',  'DEMO_CUSTOMERS', 'NOT_NULL',  'NAME');
  tk_dq.add_rule('CUST_TAX_ID_UNIQUE',  'DEMO_CUSTOMERS', 'UNIQUE',    'TAX_ID');
  tk_dq.add_rule('CUST_TAX_ID_VALID',   'DEMO_CUSTOMERS', 'VALIDATOR', 'TAX_ID', 'TAX_ID');
  tk_dq.add_rule('CUST_IBAN_VALID',     'DEMO_CUSTOMERS', 'VALIDATOR', 'IBAN',   'IBAN');
  tk_dq.add_rule('CUST_CREDIT_RANGE',   'DEMO_CUSTOMERS', 'RANGE',     'CREDIT_LIMIT', '0..1000000');
  tk_dq.add_rule('CUST_CITY_UPPERCASE', 'DEMO_CUSTOMERS', 'REGEX',     'CITY', '^[A-Z ]+$');
  tk_dq.add_rule('CUST_BLOCKED_CREDIT', 'DEMO_CUSTOMERS', 'CUSTOM',
                 p_rule_param  => q'[status = 'BLOCKED' and credit_limit > 0]',
                 p_description => 'Blocked customers must not keep an open credit limit');
end;
/
-- run from a scheduler job every night
:run_id := tk_dq.run_checks('DEMO_CUSTOMERS');
tk_dq.run_summary(:run_id, :summary);
```

```
RULE_NAME            COLUMN_NAME  RULE_TYPE SEVERITY STATUS  ROWS  BAD     PCT
-------------------- ------------ --------- -------- ------- ---- ---- -------
CUST_CREDIT_RANGE    CREDIT_LIMIT RANGE     ERROR    FAILED     5    2   40.00
CUST_TAX_ID_UNIQUE   TAX_ID       UNIQUE    ERROR    FAILED     5    2   40.00
CUST_BLOCKED_CREDIT               CUSTOM    ERROR    FAILED     5    1   20.00
CUST_CITY_UPPERCASE  CITY         REGEX     ERROR    FAILED     5    1   20.00
CUST_IBAN_VALID      IBAN         VALIDATOR ERROR    FAILED     5    1   20.00
CUST_NAME_REQUIRED   NAME         NOT_NULL  ERROR    FAILED     5    1   20.00
CUST_TAX_ID_VALID    TAX_ID       VALIDATOR ERROR    FAILED     5    1   20.00
```

| Rule type   | `p_rule_param`                           | A row violates the rule when …                 |
| ----------- | ---------------------------------------- | ---------------------------------------------- |
| `NOT_NULL`  |                                          | the column is null                             |
| `UNIQUE`    |                                          | a non-null value occurs more than once         |
| `REGEX`     | pattern                                  | the value does not match                       |
| `RANGE`     | `min..max` (either side optional)        | the value is outside the range                 |
| `IN_LIST`   | `A,B,C`                                  | the value is not in the list                   |
| `VALIDATOR` | `TCKN`, `VKN`, `TAX_ID`, `IBAN`, `EMAIL`, `TR_MOBILE`, `TR_PLATE`, `DATE:<format>` | the validator returns `N` |
| `CUSTOM`    | SQL predicate selecting **bad** rows     | the predicate is true                          |

- Rules are validated when they are added: the table, the column, the regex, the range and the validator name must all be valid.
- A broken rule never stops a run. It is stored with status `ERROR` and its Oracle error message.
- `tk_dq.violations('CUST_TAX_ID_VALID', :cur)` returns the offending rows, with their `ROWID`, so they can be fixed.
- Predicates are built with quoted identifiers, escaped literals and NLS-independent numbers. `CUSTOM` predicates are trusted configuration, so only administrators should be able to write to `TK_DQ_RULES`.

### `tk_cursor` – report pattern and export

```sql
procedure customers_by_city (p_city in varchar2, p_sort in varchar2, p_result out sys_refcursor) is
begin
  -- filters are bind variables; the ORDER BY text comes from the whitelist, never from p_sort
  open p_result for
    'select customer_code, name, city, credit_limit from demo_customers
      where (:city is null or city = upper(:city)) '
    || tk_cursor.safe_order_by(p_sort, 'CUSTOMER_CODE, NAME, CITY, CREDIT_LIMIT', 'CUSTOMER_CODE')
    using p_city, p_city;
end;

l_csv  := tk_cursor.to_csv(l_cursor, p_delimiter => ';');
l_json := tk_cursor.to_json(l_cursor);
```

```
CUSTOMER_CODE;NAME;CITY;CREDIT_LIMIT
C-003;;ankara;2000000
C-001;Anadolu Kagit A.S.;ANKARA;250000
C-005;Cukurova Karton;ADANA;75000

[{"CUSTOMER_CODE":"C-002","NAME":"Ege Ambalaj Ltd.","CITY":"IZMIR","CREDIT_LIMIT":-100}]

safe_order_by('tax_id; drop table demo_customers', ...)
ORA-20131: Invalid sort expression: tax_id; drop table demo_customers
```

- Works with **any** cursor: columns are discovered at runtime with `DBMS_SQL.DESCRIBE_COLUMNS3`.
- **NLS independent**: with Turkish settings (`NLS_NUMERIC_CHARACTERS = ',.'`), `TO_CHAR(1234.5)` returns `1234,5` and breaks CSV files. `tk_cursor` always writes `1234.5`, and writes dates as ISO-8601.
- RFC 4180 quoting (delimiters, quotes, line breaks), CLOB columns, and results larger than 32 KB are supported.

## Installation

```bash
sqlplus user/password@//host:1521/service @install.sql
```

`install.sql` is idempotent: existing tables and their data are kept. It fails with a list of errors if anything doesn't compile. `uninstall.sql` removes everything, **including the audit history**.

**Privileges:** the packages use definer rights and run DDL through `EXECUTE IMMEDIATE`. The owning schema therefore needs these privileges granted **directly**, not through a role:

```sql
grant create table, create trigger, create procedure to <toolkit_owner>;
```

Install the toolkit into the schema that owns the ERP tables. To audit or check tables in another schema, the owner also needs `CREATE ANY TRIGGER` and `SELECT` on those tables, or you can install one copy per schema.

## Running the tests

The repository includes a Docker setup. It starts Oracle Database 23ai Free, then downloads utPLSQL, verifies its SHA-256 checksum, and installs it:

```bash
docker compose up -d --wait        # first start: ~2 minutes
./scripts/tk.sh test               # Linux / macOS / Git Bash
./scripts/tk.ps1 test              # Windows PowerShell
./scripts/tk.sh examples           # run examples/*.sql
```

```
toolkit
  tk_validate - Turkish and generic validators
    TCKN: accepts valid identity numbers [.034 sec]
    IBAN: rejects wrong checksum, length and characters [.003 sec]
    ...
  tk_audit - generated audit triggers
    UPDATE logs only the changed columns with old and new values [.042 sec]
    A rollback removes the audit row together with the change [.035 sec]
    ...
70 tests, 0 failed, 0 errored, 0 disabled, 0 warning(s)
```

CI runs the test suite and all examples on **Oracle 23ai Free** and **Oracle 21c XE**. The code avoids 21c/23ai-only syntax and targets **19c**, the most common ERP database version.

## Error codes

| Range           | Package       | Meaning                                                                         |
| --------------- | ------------- | ------------------------------------------------------------------------------- |
| -20100          | `tk_validate` | unknown validator                                                               |
| -20110 … -20113 | `tk_audit`    | table not found, invalid column list, trigger compilation failed, invalid purge |
| -20120 … -20124 | `tk_dq`       | table / column not found, unknown rule type, invalid parameter, unknown rule    |
| -20130 … -20132 | `tk_cursor`   | sort column not allowed, invalid sort expression, invalid argument              |

## Project layout

```
source/      tables.sql, tk_util, tk_validate, tk_audit, tk_dq, tk_cursor (.pks / .pkb)
test/        utPLSQL suites (test_tk_*.pks / .pkb), install_tests.sql, run_tests.sql
examples/    runnable demos on a sample customer table
docker/      Oracle + utPLSQL init script
scripts/     tk.sh / tk.ps1 runner (install | test | examples | uninstall)
install.sql  uninstall.sql
```

## License

[MIT](LICENSE) © Gökhan Hepyetiker
