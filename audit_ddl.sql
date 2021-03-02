--AUDIT------------------------------------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS hstore;

CREATE SCHEMA audit;
REVOKE ALL ON SCHEMA audit FROM public;

COMMENT ON SCHEMA audit IS 'Out-of-table audit/history logging tables and trigger functions';

CREATE TABLE audit.logged_actions (
  event_id bigserial primary key,
  schema_name text not null,
  table_name text not null,
  relid oid not null,
  session_user_name text,
  action_tstamp_tx TIMESTAMP WITH TIME ZONE NOT NULL,
  action_tstamp_stm TIMESTAMP WITH TIME ZONE NOT NULL,
  action_tstamp_clk TIMESTAMP WITH TIME ZONE NOT NULL,
  transaction_id bigint,
  application_name text,
  client_addr inet,
  client_port integer,
  client_query text,
  action TEXT NOT NULL CHECK (action IN ('I','D','U', 'T')),
  row_data hstore,
  changed_fields hstore,
  statement_only boolean not null,
  "user" character varying(30),
  "group" character varying(30)
);

REVOKE ALL ON audit.logged_actions FROM public;

COMMENT ON TABLE audit.logged_actions IS 'History of auditable actions on audited tables, from audit.if_modified_func()';
COMMENT ON COLUMN audit.logged_actions.event_id IS 'Unique identifier for each auditable event';
COMMENT ON COLUMN audit.logged_actions.schema_name IS 'Database schema audited table for this event is in';
COMMENT ON COLUMN audit.logged_actions.table_name IS 'Non-schema-qualified table name of table event occured in';
COMMENT ON COLUMN audit.logged_actions.relid IS 'Table OID. Changes with drop/create. Get with ''tablename''::regclass';
COMMENT ON COLUMN audit.logged_actions.session_user_name IS 'Login / session user whose statement caused the audited event';
COMMENT ON COLUMN audit.logged_actions.action_tstamp_tx IS 'Transaction start timestamp for tx in which audited event occurred';
COMMENT ON COLUMN audit.logged_actions.action_tstamp_stm IS 'Statement start timestamp for tx in which audited event occurred';
COMMENT ON COLUMN audit.logged_actions.action_tstamp_clk IS 'Wall clock time at which audited event''s trigger call occurred';
COMMENT ON COLUMN audit.logged_actions.transaction_id IS 'Identifier of transaction that made the change. May wrap, but unique paired with action_tstamp_tx.';
COMMENT ON COLUMN audit.logged_actions.client_addr IS 'IP address of client that issued query. Null for unix domain socket.';
COMMENT ON COLUMN audit.logged_actions.client_port IS 'Remote peer IP port address of client that issued query. Undefined for unix socket.';
COMMENT ON COLUMN audit.logged_actions.client_query IS 'Top-level query that caused this auditable event. May be more than one statement.';
COMMENT ON COLUMN audit.logged_actions.application_name IS 'Application name set when this audit event occurred. Can be changed in-session by client.';
COMMENT ON COLUMN audit.logged_actions.action IS 'Action type; I = insert, D = delete, U = update, T = truncate';
COMMENT ON COLUMN audit.logged_actions.row_data IS 'Record value. Null for statement-level trigger. For INSERT this is the new tuple. For DELETE and UPDATE it is the old tuple.';
COMMENT ON COLUMN audit.logged_actions.changed_fields IS 'New values of fields changed by UPDATE. Null except for row-level UPDATE events.';
COMMENT ON COLUMN audit.logged_actions.statement_only IS '''t'' if audit event is from an FOR EACH STATEMENT trigger, ''f'' for FOR EACH ROW';

CREATE INDEX logged_actions_relid_idx ON audit.logged_actions(relid);
CREATE INDEX logged_actions_action_tstamp_tx_stm_idx ON audit.logged_actions(action_tstamp_stm);
CREATE INDEX logged_actions_action_idx ON audit.logged_actions(action);

CREATE OR REPLACE FUNCTION audit.if_modified_func()
  RETURNS trigger AS
$BODY$
DECLARE
  audit_row audit.logged_actions;
  include_values boolean;
  log_diffs boolean;
  h_old hstore;
  h_new hstore;
  excluded_cols text[] = ARRAY[]::text[];
BEGIN
  IF TG_WHEN <> 'AFTER' THEN
    RAISE EXCEPTION 'audit.if_modified_func() may only run as an AFTER trigger';
  END IF;

  audit_row = ROW(
              nextval('audit.logged_actions_event_id_seq'), -- event_id
                                                            TG_TABLE_SCHEMA::text,                        -- schema_name
                                                            TG_TABLE_NAME::text,                          -- table_name
                                                            TG_RELID,                                     -- relation OID for much quicker searches
                                                            session_user::text,                           -- session_user_name
                                                            current_timestamp,                            -- action_tstamp_tx
                                                            statement_timestamp(),                        -- action_tstamp_stm
                                                            clock_timestamp(),                            -- action_tstamp_clk
                                                            txid_current(),                               -- transaction ID
                                                            current_setting('application_name'),          		-- client application
                                                            current_setting('request.header.remote_addr',true), 	-- client_addr
              null,                           -- client_port
              current_query(),                              -- top-level query or queries (if multistatement) from client
              substring(TG_OP,1,1),                         -- action
              NULL, NULL,                                   -- row_data, changed_fields
              'f',                                          -- statement_only,
              current_setting('request.jwt.claim.email',true),         -- username actual,
              current_setting('request.jwt.claim.group',true)         -- group actual
  );

  IF NOT TG_ARGV[0]::boolean IS DISTINCT FROM 'f'::boolean THEN
    audit_row.client_query = NULL;
  END IF;

  IF TG_ARGV[1] IS NOT NULL THEN
    excluded_cols = TG_ARGV[1]::text[];
  END IF;

  IF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW') THEN
    audit_row.row_data = hstore(OLD.*) - excluded_cols;
    audit_row.changed_fields =  (hstore(NEW.*) - audit_row.row_data) - excluded_cols;
    IF audit_row.changed_fields = hstore('') THEN
      -- All changed fields are ignored. Skip this update.
      RETURN NULL;
    END IF;
  ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW') THEN
    audit_row.row_data = hstore(OLD.*) - excluded_cols;
  ELSIF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW') THEN
    audit_row.row_data = hstore(NEW.*) - excluded_cols;
  ELSIF (TG_LEVEL = 'STATEMENT' AND TG_OP IN ('INSERT','UPDATE','DELETE','TRUNCATE')) THEN
    audit_row.statement_only = 't';
  ELSE
    RAISE EXCEPTION '[audit.if_modified_func] - Trigger func added as trigger for unhandled case: %, %',TG_OP, TG_LEVEL;
    RETURN NULL;
  END IF;
  INSERT INTO audit.logged_actions VALUES (audit_row.*);
  RETURN NULL;
END;
$BODY$
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
COST 100;
ALTER FUNCTION audit.if_modified_func() SET search_path=pg_catalog, public;

ALTER FUNCTION audit.if_modified_func()
OWNER TO postgres;
COMMENT ON FUNCTION audit.if_modified_func() IS '
Track changes to a table at the statement and/or row level.

Optional parameters to trigger in CREATE TRIGGER call:

param 0: boolean, whether to log the query text. Default ''t''.

param 1: text[], columns to ignore in updates. Default [].

         Updates to ignored cols are omitted from changed_fields.

         Updates with only ignored cols changed are not inserted
         into the audit log.

         Almost all the processing work is still done for updates
         that ignored. If you need to save the load, you need to use
         WHEN clause on the trigger instead.

         No warning or error is issued if ignored_cols contains columns
         that do not exist in the target table. This lets you specify
         a standard set of ignored columns.

There is no parameter to disable logging of values. Add this trigger as
a ''FOR EACH STATEMENT'' rather than ''FOR EACH ROW'' trigger if you do not
want to log row values.

Note that the user name logged is the login role for the session. The audit trigger
cannot obtain the active role because it is reset by the SECURITY DEFINER invocation
of the audit trigger its self.';



CREATE OR REPLACE FUNCTION audit.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean, ignored_cols text[]) RETURNS void AS $body$
DECLARE
  stm_targets text = 'INSERT OR UPDATE OR DELETE OR TRUNCATE';
  _q_txt text;
  _ignored_cols_snip text = '';
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_row ON ' || quote_ident(target_table::TEXT);
  EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_stm ON ' || quote_ident(target_table::TEXT);

  IF audit_rows THEN
    IF array_length(ignored_cols,1) > 0 THEN
      _ignored_cols_snip = ', ' || quote_literal(ignored_cols);
    END IF;
    _q_txt = 'CREATE TRIGGER audit_trigger_row AFTER INSERT OR UPDATE OR DELETE ON ' ||
             quote_ident(target_table::TEXT) ||
             ' FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func(' ||
             quote_literal(audit_query_text) || _ignored_cols_snip || ');';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;
    stm_targets = 'TRUNCATE';
  ELSE
  END IF;

  _q_txt = 'CREATE TRIGGER audit_trigger_stm AFTER ' || stm_targets || ' ON ' ||
           target_table ||
           ' FOR EACH STATEMENT EXECUTE PROCEDURE audit.if_modified_func('||
           quote_literal(audit_query_text) || ');';
  RAISE NOTICE '%',_q_txt;
  EXECUTE _q_txt;

END;
$body$
language 'plpgsql';

COMMENT ON FUNCTION audit.audit_table(regclass, boolean, boolean, text[]) IS $body$
Add auditing support to a table.

Arguments:
   target_table:     Table name, schema qualified if not on search_path
   audit_rows:       Record each row change, or only audit at a statement level
   audit_query_text: Record the text of the client query that triggered the audit event?
   ignored_cols:     Columns to exclude from update diffs, ignore updates that change only ignored cols.
$body$;

-- Pg doesn't allow variadic calls with 0 params, so provide a wrapper
CREATE OR REPLACE FUNCTION audit.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean) RETURNS void AS $body$
SELECT audit.audit_table($1, $2, $3, ARRAY[]::text[]);
$body$ LANGUAGE SQL;

-- And provide a convenience call wrapper for the simplest case
-- of row-level logging with no excluded cols and query logging enabled.
--
CREATE OR REPLACE FUNCTION audit.audit_table(target_table regclass) RETURNS void AS $body$
SELECT audit.audit_table($1, BOOLEAN 't', BOOLEAN 't');
$body$ LANGUAGE 'sql';

COMMENT ON FUNCTION audit.audit_table(regclass) IS $body$
Add auditing support to the given table. Row-level changes will be logged with full client query text. No cols are ignored.
$body$;


---------------------
-- You can enable loging with this statement,
-- The table will now have audit events recorded at a row level for every insert/update/delete, and at a statement level for truncate. Query text will always be logged.
-- SELECT audit.audit_table('sp_sales');
---------

CREATE TRIGGER sp_sales_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_sales
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_clients_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_clients
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_certificates_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_certificates
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_users_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_users
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_resources_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_resources
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_assets_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_assets
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();

CREATE TRIGGER sp_goods_audit
AFTER INSERT OR UPDATE OR DELETE ON sp_goods
FOR EACH ROW EXECUTE PROCEDURE audit.if_modified_func();
