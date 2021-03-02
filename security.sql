-- SECURITY

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION
  check_role_exists() RETURNS TRIGGER
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


CREATE OR REPLACE FUNCTION
  encrypt_pass() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF tg_op = 'INSERT' OR new.pass <> old.pass THEN
    new.pass = crypt(new.pass, gen_salt('md5'));
  END IF;
  RETURN new;
END
$$;


--DROP TRIGGER IF EXISTS encrypt_pass ON sp_users;
CREATE TRIGGER encrypt_pass
BEFORE INSERT OR UPDATE ON sp_users
FOR EACH ROW
EXECUTE PROCEDURE encrypt_pass();


-- JWT configurations

CREATE OR REPLACE FUNCTION
  url_encode(data bytea) RETURNS text
LANGUAGE sql
AS $$
SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;


CREATE OR REPLACE FUNCTION
  url_decode(data text) RETURNS bytea
LANGUAGE sql
AS $$
WITH t AS (SELECT translate(data, '-_', '+/')),
    rem AS (SELECT length((SELECT * FROM t)) % 4) -- compute padding size
SELECT decode(
    (SELECT * FROM t) ||
    CASE WHEN (SELECT * FROM rem) > 0
      THEN repeat('=', (4 - (SELECT * FROM rem)))
    ELSE '' END,
    'base64');
$$;


CREATE OR REPLACE FUNCTION
  algorithm_sign(signables text, secret text, algorithm text) RETURNS text
LANGUAGE sql
AS $$
WITH
    alg AS (
      SELECT CASE
             WHEN algorithm = 'HS256' THEN 'sha256'
             WHEN algorithm = 'HS384' THEN 'sha384'
             WHEN algorithm = 'HS512' THEN 'sha512'
             ELSE '' END)  -- hmac throws error
SELECT url_encode(hmac(signables, secret, (select * FROM alg)));
$$;


CREATE OR REPLACE FUNCTION
  sign(payload json, secret text, algorithm text DEFAULT 'HS256') RETURNS text
LANGUAGE sql
AS $$
WITH
    header AS (
      SELECT url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8'))
  ),
    payload AS (
      SELECT url_encode(convert_to(payload::text, 'utf8'))
  ),
    signables AS (
      SELECT (SELECT * FROM header) || '.' || (SELECT * FROM payload)
  )
SELECT
  (SELECT * FROM signables)
  || '.' ||
  algorithm_sign((SELECT * FROM signables), secret, algorithm);
$$;



--DROP TYPE IF EXISTS jwt_token CASCADE;
CREATE TYPE jwt_token AS (token TEXT);

CREATE OR REPLACE FUNCTION
  login(email VARCHAR, pass VARCHAR, host VARCHAR) RETURNS jwt_token
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

CREATE OR REPLACE FUNCTION
  sp_init_groups(group_code VARCHAR) RETURNS VARCHAR[]
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

CREATE OR REPLACE FUNCTION
  sp_get_neighbors(group_code VARCHAR) RETURNS VARCHAR[]
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


CREATE OR REPLACE FUNCTION
  sp_get_groups() RETURNS VARCHAR[]
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

CREATE OR REPLACE FUNCTION
  update_password(oldpass VARCHAR, newpass1 VARCHAR, newpass2 VARCHAR) RETURNS BOOLEAN
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
