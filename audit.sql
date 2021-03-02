---------------------------------------------------------------
-- View: public.audit_logged_actions

--DROP VIEW public.sp_audit;

CREATE OR REPLACE VIEW public.sp_audit AS
  SELECT logged_actions."group",
    logged_actions."user",
    logged_actions.table_name,
    logged_actions.action,
    logged_actions.action_tstamp_stm AS date,
    logged_actions.row_data,
    logged_actions.changed_fields,
    logged_actions.client_query,
    sp_users.name
  FROM audit.logged_actions,
    sp_users
  WHERE logged_actions."user"::text = sp_users.email::text AND
        logged_actions."group" = current_setting('request.jwt.claim.group', TRUE)
  ORDER BY logged_actions.action_tstamp_stm;

ALTER TABLE public.sp_audit OWNER TO postgres;
GRANT ALL ON TABLE public.sp_audit TO postgres;
GRANT SELECT ON TABLE public.sp_audit TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_audit TO sp_superadmin;
