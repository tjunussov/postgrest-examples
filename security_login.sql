------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sign_up(
  email character varying,
  pass character varying,
  host character varying,
  groupName character varying,
  groupCode character varying)
  RETURNS void AS
$BODY$

BEGIN
  INSERT INTO sp_groups (code, name, host) VALUES (groupCode, groupName, host);
  INSERT INTO sp_users ("group",email, pass, role, name, configs) VALUES (groupCode, email, pass,'sp_superadmin', email, '{"register": true}');
END
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100;
ALTER FUNCTION public.sign_up(character varying, character varying, character varying, character varying, character varying)
OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.sign_up(character varying, character varying, character varying, character varying, character varying) TO public;
GRANT EXECUTE ON FUNCTION public.sign_up(character varying, character varying, character varying, character varying, character varying) TO postgres;
GRANT EXECUTE ON FUNCTION public.sign_up(character varying, character varying, character varying, character varying, character varying) TO sp_anon;

