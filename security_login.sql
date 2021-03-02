CREATE OR REPLACE FUNCTION check_role_exists() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
begin
  IF NOT exists (SELECT 1 FROM pg_roles AS r WHERE r.rolname = new.role) THEN
    RAISE foreign_key_violation USING MESSAGE = 'unknown user role: ' || new.role;
    RETURN NULL;
  END IF;
  RETURN new;
END
$$;

--DROP TRIGGER IF EXISTS ensure_user_role_exists ON sp_users;
CREATE CONSTRAINT TRIGGER ensure_user_role_exists
AFTER INSERT OR UPDATE ON sp_users
FOR EACH ROW
EXECUTE PROCEDURE check_role_exists();

-----------------------------------------

CREATE OR REPLACE FUNCTION login(email VARCHAR, pass VARCHAR, host VARCHAR) RETURNS jwt_token
LANGUAGE plpgsql
AS $$
declare
  _role NAME;
  _group VARCHAR;
  _groups VARCHAR[];
  _id INTEGER;
  result jwt_token;
begin
  PERFORM set_config('sp.login.email', login.email, TRUE);
  PERFORM set_config('sp.login.pass', login.pass, TRUE);
  PERFORM set_config('sp.login.host', login.host, TRUE);


  SELECT "role", "group" FROM sp_users
  WHERE sp_users.email = login.email
        AND sp_users.pass = crypt(login.pass, sp_users.pass) INTO _role, _group;
  IF _role IS NULL OR _group IS NULL THEN
    RAISE invalid_password USING MESSAGE = 'invalid email or password';
  END IF;

  SELECT sp_groups.code FROM sp_groups
  WHERE sp_groups.host = login.host AND sp_groups.code = _group INTO _group;

  IF _group IS NULL THEN
    RAISE invalid_password USING MESSAGE = 'invalid email or password (or domain)';
  END IF;

  SELECT sp_init_groups(_group) INTO _groups;

  IF _role = 'sp_superadmin' THEN
    _groups := _groups || sp_get_neighbors(_group);
  END IF;

  SELECT sign(
             row_to_json(t), 'smartpos_is_very_smart'
         ) AS token
  FROM (
         SELECT login.email AS email, _role AS role, _group AS group, _groups AS groups,
                extract(epoch FROM now())::INTEGER+600*60 AS exp
       ) t INTO result;

  RETURN result;
END
$$;

-----------------------------------------
    
CREATE OR REPLACE FUNCTION sp_init_groups(group_code VARCHAR) RETURNS VARCHAR[]
LANGUAGE plpgsql
AS $$
DECLARE
  code VARCHAR;
  childs VARCHAR[];
  result VARCHAR[];
BEGIN
  result := result || group_code;

  PERFORM set_config('sp.current.group', group_code, TRUE);

  FOR code IN SELECT sp_groups.code FROM sp_groups WHERE sp_groups.parent=group_code
  LOOP
    result := result || sp_init_groups(code);
  END LOOP;

  RETURN result;
END
$$;
    
-----------------------------------------

CREATE OR REPLACE FUNCTION sp_get_neighbors(group_code VARCHAR) RETURNS VARCHAR[]
LANGUAGE plpgsql
AS $$
DECLARE
  result VARCHAR[];
BEGIN

  SELECT array_agg(nbrs.code) FROM
    (SELECT jsonb_array_elements(neighbors)->>'code' AS code FROM sp_groups WHERE code = group_code) AS nbrs
  INTO result;

  RETURN result;

END
$$;

-----------------------------------------

CREATE OR REPLACE FUNCTION sp_get_groups() RETURNS VARCHAR[]
LANGUAGE plpgsql
AS $$
DECLARE
  result VARCHAR[];
BEGIN
  SELECT array_agg(t.res::VARCHAR)
  FROM (SELECT json_array_elements_text(
                   coalesce((CASE
                             WHEN current_setting('request.jwt.claim.groups', TRUE) = '' THEN '[]'
                             ELSE current_setting('request.jwt.claim.groups', TRUE)
                             END), '[]')::JSON
               ) AS res) AS t
  INTO result;
  RETURN result;
END
$$;

-----------------------------------------

CREATE OR REPLACE FUNCTION update_password(oldpass VARCHAR, newpass1 VARCHAR, newpass2 VARCHAR) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  _email VARCHAR;
BEGIN
  SELECT email FROM sp_users
  WHERE sp_users.email = current_setting('request.jwt.claim.email')::VARCHAR
        AND sp_users.pass = crypt(update_password.oldpass, sp_users.pass) INTO _email;
  IF _email IS NULL THEN
    RAISE invalid_password USING MESSAGE = 'Old password is not correct';
  END IF;

  IF update_password.newpass1 <> update_password.newpass2 THEN
    RAISE invalid_password USING MESSAGE = 'New passwords does not match';
  END IF;

  UPDATE sp_users set pass = update_password.newpass1 WHERE sp_users.email = _email;

  RETURN found;

END
$$;

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

