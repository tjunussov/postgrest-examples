-- SECURITY

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION encrypt_pass() RETURNS TRIGGER
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


CREATE OR REPLACE FUNCTION algorithm_sign(signables text, secret text, algorithm text) RETURNS text
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


CREATE OR REPLACE FUNCTION sign(payload json, secret text, algorithm text DEFAULT 'HS256') RETURNS text
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
