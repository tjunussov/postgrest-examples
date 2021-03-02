\connect "smartpos"

CREATE OR REPLACE FUNCTION public.sales_insert_notify()
  RETURNS trigger AS
$BODY$

    DECLARE
      R record;
      J jsonb;
    BEGIN
        IF (TG_OP = 'DELETE') THEN
          R = OLD;
          J = to_jsonb(row_to_json(OLD));
        ELSIF (TG_OP = 'UPDATE') THEN
	  R = NEW;
	  J = to_jsonb(row_to_json(NEW));
          J = jsonb_set(J,'{old}',to_jsonb(row_to_json(OLD)),true);
        ELSE
      	  R = NEW;
      	  J = to_jsonb(row_to_json(NEW));
        END IF;

        J = jsonb_set(J,'{pg_operation}',to_jsonb(TG_OP),true);
        
        PERFORM pg_notify('sales_created',J::text);

        RETURN R;
        
        
    exception when others then 
        raise notice '% %', SQLERRM, SQLSTATE;
	RETURN NULL;
    END;  

$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION public.sales_insert_notify()
  OWNER TO postgres;
  
CREATE TRIGGER sales_notify
  BEFORE INSERT OR UPDATE OR DELETE
  ON public.sp_sales
  FOR EACH ROW
  EXECUTE PROCEDURE public.sales_insert_notify();
