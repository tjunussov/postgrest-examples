---------------------------------------------------------

-- SALES CODE GENERATING FUNCTIONS

CREATE OR REPLACE FUNCTION
  sp_generate_sales_codes() RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  cods TEXT[];
  cod TEXT;
  tmp TEXT;
  i INTEGER;
  curYear INTEGER = (date_part('year', CURRENT_DATE)::INTEGER);
BEGIN
	FOR i IN 0 .. 1757599 LOOP
    	cod := (chr(65+(i/67600)) || chr(65+((i/2600)%26)) || chr(65+((i/100)%26)) || (((i/10)%10)::text) || ((i%10)::text));
    	cods := cods || cod;
    END LOOP;

    ALTER SEQUENCE sp_codes_id_seq RESTART;

    SELECT array_agg(c ORDER BY random()) FROM unnest(cods) c INTO cods;

    i := 0;
    FOREACH cod IN ARRAY cods LOOP
    	INSERT INTO sp_codes ("code") VALUES (cod);
    	IF i%10000=0 THEN
    		RAISE NOTICE '%', i;
    	END IF;
    	i := i+1;
    END LOOP;

    FOR i, cod IN (SELECT id, code FROM sp_sales WHERE "year" = curYear) LOOP
    	SELECT code FROM sp_codes WHERE id=i INTO tmp;
    	IF tmp != cod THEN
    		UPDATE sp_codes SET code='-' WHERE id=i;
    		UPDATE sp_codes SET code=tmp WHERE code=cod;
    		UPDATE sp_codes SET code=cod WHERE id=i;
    	END IF;
    END LOOP;
END$$;


CREATE OR REPLACE FUNCTION
  sp_init_sales_code_seq() RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  gp TEXT;
  lastId INTEGER;
  curYear INTEGER = (date_part('year', CURRENT_DATE)::INTEGER);
BEGIN
  TRUNCATE sp_codes;
  PERFORM sp_generate_sales_codes();

  FOR gp IN (SELECT code FROM sp_groups) LOOP
    SELECT MAX(id) FROM sp_sales WHERE "group" = gp AND "year" = curYear INTO lastId;
    IF lastId IS NULL THEN lastId := 0; END IF;
    UPDATE sp_groups SET sales_code_seq = (lastId+1) WHERE code = gp;
  END LOOP;
END
$$;


CREATE OR REPLACE FUNCTION
  sp_set_sales_code_seq() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  seq INTEGER;
  gp TEXT = current_setting('request.jwt.claim.group', TRUE);
BEGIN
  IF tg_op = 'INSERT' THEN
    SELECT sales_code_seq FROM sp_groups WHERE code = gp INTO seq;
    IF seq <= 1757600 THEN
      SELECT sp_codes.code FROM sp_codes WHERE id = seq INTO new.code;
      new."year" := (date_part('year', CURRENT_DATE)::INTEGER);
      UPDATE sp_groups SET sales_code_seq=(seq+1) WHERE code = gp;
    ELSE
    --TODO
    END IF;
  END IF;
  RETURN new;
END
$$;


DROP TRIGGER IF EXISTS sp_sales_code_seq ON sp_sales;
CREATE TRIGGER sp_sales_code_seq
BEFORE INSERT ON sp_sales
FOR EACH ROW
EXECUTE PROCEDURE sp_set_sales_code_seq();
