--------------------------------------------------------------------------------------------------------------

-- VIEWS

--DROP VIEW IF EXISTS sp_clients_search;
CREATE VIEW sp_clients_search AS
  SELECT "group", "discount", ("name"||' ('||phone||')')  AS search, "id" FROM sp_clients
  WHERE "group" = current_setting('request.jwt.claim.group', TRUE);


--DROP VIEW IF EXISTS daily_sales;
CREATE VIEW daily_sales AS
  SELECT tt.group AS "group", sum(tt.cnt) AS cnt, sum(tt.total) AS total, tt.sold AS "sold", array_to_json(array_agg(jsonb_build_object('type', tt.type, 'total', tt.total))) AS payments
  FROM (
         SELECT t.group AS "group", count(1) AS cnt, sum(t.amount) AS total, t.sold AS "sold", t.type AS "type"
         FROM (
                SELECT "group", (closed+'06:00:00'::INTERVAL)::DATE AS sold, jsonb_array_elements(payments)->>'type' AS "type", (jsonb_array_elements(payments)->>'amount')::integer AS amount
                FROM sp_sales WHERE payments IS NOT NULL AND closed IS NOT NULL -- EXTRACTED EACH TYPE FROM PAYMENTS
              ) AS t
         GROUP BY t.group, t.sold, t.type  -- GROUPED BY EACH TYPE
       ) AS tt
  WHERE tt.type = 'Наличными' OR tt.type = 'Карточкой' GROUP BY tt.group, tt.sold;


---------------------------------------------------------------reports
--drop VIEW sp_daily_sales2;

CREATE OR REPLACE VIEW public.sp_daily_sales2 AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.hour::character varying AS hours,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           date_part('hour'::text, t.sold) AS hour,
           t.sold AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         GROUP BY t."group", (date_part('hour'::text, t.sold)), t.type, t.sold
         ORDER BY t.type) tt
  GROUP BY tt."group", (tt.hour::character varying), tt.sold
  ORDER BY (tt.hour::character varying);

ALTER TABLE public.sp_daily_sales2
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales2 TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales2 TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales2 TO sp_superadmin;

--DROP TYPE report1Type CASCADE;

CREATE TYPE report1Type AS (total_nal numeric, total_kar numeric, hours character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report1(group_code character varying, fromdate character varying DEFAULT ('now'::text)::date, todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report1Type AS $$

select sum(r.total_nal), sum(r.total_kar), r.hours, sum(r.cnt ) from sp_daily_sales2 r where r.date::date >= sp_report1.fromDate::date and r.date::date <= sp_report1.toDate::date
                                                                                             and r.group = sp_report1.group_code group by r.hours;
$$ LANGUAGE SQL;

-------------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales2_return AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.hour::character varying AS hours,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           date_part('hour'::text, t.sold) AS hour,
           t.sold::date AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NOT NULL) t
         GROUP BY t."group", (date_part('hour'::text, t.sold)), t.type, t.sold
         ORDER BY t.type) tt
  GROUP BY tt."group", (tt.hour::character varying), tt.sold
  ORDER BY (tt.hour::character varying);

ALTER TABLE public.sp_daily_sales2_return
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales2_return TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales2_return TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales2_return TO sp_superadmin;

CREATE OR REPLACE FUNCTION public.sp_report1_return(group_code character varying, fromdate character varying DEFAULT ('now'::text)::date, todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report1Type AS $$

select sum(r.total_nal), sum(r.total_kar), r.hours, sum(r.cnt ) from sp_daily_sales2_return r where r.date::date >= sp_report1_return.fromDate::date and r.date::date <= sp_report1_return.toDate::date
                                                                                                    and r.group = sp_report1_return.group_code group by r.hours;
$$ LANGUAGE SQL;

-------------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales2_certs AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(tt.total) AS total,
    sum(
        CASE
        WHEN tt.type != 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_buy,
    sum(
        CASE
        WHEN tt.type = 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_cell,
    tt.hour::character varying AS hours,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           date_part('hour'::text, t.sold) AS hour,
           t.sold::date AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  sp_sales.goods AS goods,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL) t
         where (t.goods is not null OR t.type = 'Сертификат')
         GROUP BY t."group", (date_part('hour'::text, t.sold)), t.type, t.sold
         ORDER BY t.type) tt
  GROUP BY tt."group", (tt.hour::character varying), tt.sold
  ORDER BY (tt.hour::character varying);

ALTER TABLE public.sp_daily_sales2_certs
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales2_certs TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales2_certs TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales2_certs TO sp_superadmin;

CREATE TYPE report1TypeCert AS (total_buy numeric, total_sell numeric, hours character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report1_certs(group_code character varying, fromdate character varying DEFAULT ('now'::text)::date, todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report1TypeCert AS $$

select sum(r.total_buy), sum(r.total_cell), r.hours, sum(r.cnt ) from sp_daily_sales2_certs r where r.date::date >= sp_report1_certs.fromDate::date and r.date::date <= sp_report1_certs.toDate::date
                                                                                                    and r.group = sp_report1_certs.group_code group by r.hours;
$$ LANGUAGE SQL;
------------------------------------

-- drop view sp_daily_sales3;
CREATE OR REPLACE VIEW public.sp_daily_sales3 AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.weekday::character varying AS weekday,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold AS weekday,
           t.day::date AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  date_part('dow'::text, sp_sales.closed::date) AS sold,
                  sp_sales."effectiveDate" AS day,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         GROUP BY t."group", t.sold, t.type, (t.day::date)
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.weekday, tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales3
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales3 TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales3 TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales3 TO sp_superadmin;

CREATE TYPE report2type AS (total_nal numeric, total_kar numeric, weekday character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report2(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report2type AS
$BODY$

select sum(r.total_nal), sum(r.total_kar), r.weekday, sum(r.cnt) from sp_daily_sales3 r where r.date::date >= sp_report2.fromDate::date and r.date::date <= sp_report2.toDate::date
                                                                                              and r.group = sp_report2.group_code group by r.weekday;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report2(character varying, character varying, character varying)
OWNER TO postgres;
--------------------------------------------------

-- View: public.sp_daily_sales3

-- DROP VIEW public.sp_daily_sales3;

CREATE OR REPLACE VIEW public.sp_daily_sales3_return AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.weekday::character varying AS weekday,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold AS weekday,
           t.day::date AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  date_part('dow'::text, sp_sales.closed::date) AS sold,
                  sp_sales."effectiveDate" AS day,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NOT NULL) t
         GROUP BY t."group", t.sold, t.type, (t.day::date)
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.weekday, tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales3_return
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales3_return TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales3_return TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales3_return TO sp_superadmin;

CREATE OR REPLACE FUNCTION public.sp_report2_return(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report2type AS
$BODY$

select sum(r.total_nal), sum(r.total_kar), r.weekday, sum(r.cnt) from sp_daily_sales3_return r where r.date::date >= sp_report2_return.fromDate::date and r.date::date <= sp_report2_return.toDate::date
                                                                                                     and r.group = sp_report2_return.group_code group by r.weekday;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report2_return(character varying, character varying, character varying)
OWNER TO postgres;
--------------------------------------------------

-- View: public.sp_daily_sales3

-- DROP VIEW public.sp_daily_sales3;

CREATE OR REPLACE VIEW public.sp_daily_sales3_certs AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(tt.total) AS total,
    sum(
        CASE
        WHEN tt.type <> 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_buy,
    sum(
        CASE
        WHEN tt.type = 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_cell,
    tt.weekday::character varying AS weekday,
    tt.sold AS date
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold AS weekday,
           t.day::date AS sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  date_part('dow'::text, sp_sales.closed::date) AS sold,
                  sp_sales.goods,
                  sp_sales."effectiveDate" AS day,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         WHERE t.goods IS NOT NULL OR t.type = 'Сертификат'::text
         GROUP BY t."group", t.sold, t.type, (t.day::date)
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.weekday, tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales3_certs
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales3_certs TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales3_certs TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales3_certs TO sp_superadmin;

CREATE TYPE report2TypeCert AS (total_buy numeric, total_sell numeric, weekday character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report2_certs(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report2typecert AS
$BODY$

select sum(r.total_buy), sum(r.total_cell), r.weekday, sum(r.cnt ) from sp_daily_sales3_certs r where r.date::date >= sp_report2_certs.fromDate::date and r.date::date <= sp_report2_certs.toDate::date
                                                                                                      and r.group = sp_report2_certs.group_code group by r.weekday;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report1_certs(character varying, character varying, character varying)
OWNER TO postgres;

--------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales4 AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.sold::character varying AS sold
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         GROUP BY t."group", t.sold, t.type
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales4
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales4 TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales4 TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales4 TO sp_superadmin;


-- drop type report3type cascade;

CREATE TYPE report3type AS (total_nal numeric, total_kar numeric, sold character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report3(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report3type AS
$BODY$

select r.total_nal, r.total_kar, r.sold, r.cnt from sp_daily_sales4 r
where r.sold::date >= sp_report3.fromDate::date and r.sold::date <= sp_report3.toDate::date and r.group = sp_report3.group_code;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report3(character varying, character varying, character varying)
OWNER TO postgres;
----------------------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales4_return AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_nal,
    sum(
        CASE
        WHEN tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_kar,
    tt.sold::character varying AS sold
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NOT NULL) t
         GROUP BY t."group", t.sold, t.type
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales4_return
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales4_return TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales4_return TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales4_return TO sp_superadmin;

CREATE OR REPLACE FUNCTION public.sp_report3_return(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report3type AS
$BODY$

select r.total_nal, r.total_kar, r.sold, r.cnt from sp_daily_sales4_return r
where r.sold::date >= sp_report3_return.fromDate::date and r.sold::date <= sp_report3_return.toDate::date and r.group = sp_report3_return.group_code;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report3_return(character varying, character varying, character varying)
OWNER TO postgres;
----------------------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales4_certs AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(tt.total) AS total,
    sum(
        CASE
        WHEN tt.type <> 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_buy,
    sum(
        CASE
        WHEN tt.type = 'Сертификат'::text THEN tt.total
        ELSE 0::bigint
        END) AS total_cell,
    tt.sold::character varying AS sold
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.amount) AS total,
           t.sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  sp_sales."effectiveDate" AS sold,
                  sp_sales.goods,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         WHERE t.goods IS NOT NULL OR t.type = 'Сертификат'::text
         GROUP BY t."group", t.sold, t.type
         ORDER BY t.type) tt
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales4_certs
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales4_certs TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales4_certs TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales4_certs TO sp_superadmin;

CREATE TYPE report3TypeCert AS (total_buy numeric, total_sell numeric, sold character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report3_certs(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report3TypeCert AS
$BODY$

select r.total_buy, r.total_cell, r.sold, r.cnt from sp_daily_sales4_certs r
where r.sold::date >= sp_report3_certs.fromDate::date and r.sold::date <= sp_report3_certs.toDate::date and r.group = sp_report3_certs.group_code;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report3_certs(character varying, character varying, character varying)
OWNER TO postgres;

----------------------------------------------------------------


CREATE OR REPLACE VIEW public.sp_daily_sales5 AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    tt.name AS name,
    tt.sold AS sold
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.price) AS total,
           t.name,
           t.sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  jsonb_array_elements(sp_sales.assets) ->> 'name'::text AS name,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.assets) ->> 'price'::text)::integer AS price,
                  sp_sales."effectiveDate" AS sold
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
         GROUP BY t."group", t.name, t.sold, t.type
         ORDER BY t.name) tt
  where tt.type in ('Наличными', 'Карточкой')
  GROUP BY tt."group", tt.sold, tt.name
  ORDER BY tt.sold;


ALTER TABLE public.sp_daily_sales5
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales5 TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales5 TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales5 TO sp_superadmin;

CREATE TYPE report4Type AS (total numeric, name character, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report4(group_code character varying, fromdate character varying DEFAULT ('now'::text)::date, todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report4Type AS $$

select sum(r.total), r.name, sum(r.cnt) from sp_daily_sales5 r
where r.sold::date >= sp_report4.fromDate::date and r.sold::date <= sp_report4.toDate::date
      and r.group = sp_report4.group_code group by r.name;
$$ LANGUAGE SQL;

---------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales5_deleted AS
  SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
        WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
        ELSE 0::bigint
        END) AS total,
    tt.name,
    tt.sold
  FROM ( SELECT t."group",
           count(1) AS cnt,
           sum(t.price) AS total,
           t.name,
           t.sold,
           t.type
         FROM ( SELECT sp_sales."group",
                  jsonb_array_elements(sp_sales.assets) ->> 'name'::text AS name,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  (jsonb_array_elements(sp_sales.assets) ->> 'price'::text)::integer AS price,
                  sp_sales."effectiveDate" AS sold
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NOT NULL) t
         GROUP BY t."group", t.name, t.sold, t.type
         ORDER BY t.name) tt
  WHERE tt.type = ANY (ARRAY['Наличными'::text, 'Карточкой'::text])
  GROUP BY tt."group", tt.sold, tt.name
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales5_deleted
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales5_deleted TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales5_deleted TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales5_deleted TO sp_superadmin;

CREATE OR REPLACE FUNCTION public.sp_report4_deleted(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report4type AS
$BODY$

select sum(r.total), r.name, sum(r.cnt) from sp_daily_sales5_deleted r
where r.sold::date >= sp_report4_deleted.fromDate::date and r.sold::date <= sp_report4_deleted.toDate::date
      and r.group = sp_report4_deleted.group_code group by r.name;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report4_deleted(character varying, character varying, character varying)
OWNER TO postgres;

---------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales6 AS
  SELECT t."group",
    jsonb_array_elements(t.resources) ->> 'name'::text AS name,
    t.price / NULLIF(t.res_size, 0) AS price,
    t.sold
  FROM ( SELECT sp_sales."group",
           (jsonb_array_elements(sp_sales.assets) ->> 'resources'::text)::jsonb AS resources,
           jsonb_array_elements(sp_sales.payments) ->> 'type'::varchar AS type,
           jsonb_array_length((jsonb_array_elements(sp_sales.assets) ->> 'resources'::text)::jsonb) AS res_size,
           (jsonb_array_elements(sp_sales.assets) ->> 'price'::text)::bigint AS price,
           sp_sales."effectiveDate" AS sold
         FROM sp_sales
         WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL
       ) t where type in ('Наличными', 'Карточкой');

ALTER TABLE public.sp_daily_sales6
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales6 TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales6 TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales6 TO sp_superadmin;

CREATE TYPE report5Type AS (price numeric, name character);

CREATE OR REPLACE FUNCTION public.sp_report5(group_code character varying, fromdate character varying DEFAULT ('now'::text)::date, todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report5Type AS $$

select sum(r.price), r.name from sp_daily_sales6 r
where r.sold::date >= sp_report5.fromDate::date and r.sold::date <= sp_report5.toDate::date
      and r.group = sp_report5.group_code group by r.name;
$$ LANGUAGE SQL;

----------------------------------------------------

CREATE OR REPLACE VIEW public.sp_daily_sales6_manager AS
  SELECT t."group",
    t.name,
    t.type,
    sum(t.price) AS PRICE,
    t.sold
  FROM (SELECT sp_sales."group",
          sp_sales.creator::text as name,
          jsonb_array_elements(sp_sales.payments) ->> 'type'::character varying::text AS type,
          (jsonb_array_elements(sp_sales.assets) ->> 'price'::text)::bigint AS price,
          sp_sales."effectiveDate" AS sold
        FROM sp_sales
        WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.returned IS NULL AND sp_sales.deleted IS NULL) t
  GROUP BY t."group", t.name, t.type, t.sold;

ALTER TABLE public.sp_daily_sales6
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales6_manager TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales6_manager TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_daily_sales6_manager TO sp_superadmin;

CREATE OR REPLACE FUNCTION public.sp_report5_manager(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report5type AS
$BODY$

select sum(r.price), r.name from sp_daily_sales6_manager r
where r.sold::date >= sp_report5_manager.fromDate::date and r.sold::date <= sp_report5_manager.toDate::date
      and r.group = sp_report5_manager.group_code group by r.name;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report5_manager(character varying, character varying, character varying)
OWNER TO postgres;

----------------------------------------------------

CREATE OR REPLACE VIEW public.sp_cert_sales AS
  SELECT tt."group",
    tt.code,
    tt.client,
    tt.amount,
    tt.sold,
    tt.cert_code
  FROM ( SELECT t."group",
           t.code,
           t.client,
           t.amount,
           t.sold,
           t.type,
           t.cert_code
         FROM ( SELECT sp_sales."group",
                  sp_sales.code,
                  sp_sales.client,
                  sp_sales."effectiveDate" AS sold,
                  jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                  jsonb_array_elements(sp_sales.payments) ->> 'code'::text AS cert_code,
                  (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                FROM sp_sales
                WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL) t
         GROUP BY t."group", t.code, t.client, t.amount, t.sold, t.type, t.cert_code) tt
  WHERE tt.type = 'Сертификат'::text AND tt."group" = current_setting('request.jwt.claim.group', TRUE)
  GROUP BY tt."group", tt.code, tt.client, tt.amount, tt.sold, tt.cert_code;

ALTER TABLE public.sp_cert_sales
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_cert_sales TO postgres;
GRANT SELECT ON TABLE public.sp_cert_sales TO sp_admin WITH GRANT OPTION;
GRANT SELECT ON TABLE public.sp_cert_sales TO sp_superadmin;

----------------------------------------------------

CREATE TYPE report6type AS (group_name character, total numeric, cnt numeric);

CREATE OR REPLACE FUNCTION public.sp_report6(
  group_code character varying,
  fromdate character varying DEFAULT ('now'::text)::date,
  todate character varying DEFAULT ('now'::text)::date)
  RETURNS SETOF report6type AS
$BODY$

select (select name from sp_groups where code = r.group) as group_name, sum(r.total) as total, sum(r.cnt) as cnt from sp_daily_sales4 r
where r.group in (select code from sp_groups where parent = sp_report6.group_code)
      and r.sold::date >= sp_report6.fromDate::date and r.sold::date <= sp_report6.toDate::date
group by r.group;
$BODY$
LANGUAGE sql VOLATILE
COST 100
ROWS 1000;
ALTER FUNCTION public.sp_report6(character varying, character varying, character varying)
OWNER TO postgres;

----------------------------------------------------
CREATE TYPE sp_s as (id integer,
                     "group" character varying(30),
                     code character varying(30),
                     created timestamp with time zone,
                     starts timestamp with time zone,
                     ends timestamp with time zone,
                     closed timestamp with time zone,
                     edited timestamp with time zone,
                     payed TIMESTAMP WITH TIME ZONE,
                     total integer,
                     status character varying(50),
                     creator character varying(255),
                     performer character varying(255),
                     type character varying(50),
                     client jsonb,
                     assets jsonb,
                     goods jsonb,
                     payments jsonb,
                     configs jsonb,
                     fiskal jsonb,
                     returned timestamp with time zone,
                     deleted timestamp with time zone,
                     effectiveDate DATE,
                     "year" INTEGER);

CREATE OR REPLACE FUNCTION public.sales("group" character varying, date character varying DEFAULT ('now'::text)::date)
  RETURNS setof sp_s AS $$

select * from sp_sales as s where s.payed::date >= sales.date::date and s.payed::date <= sales.date::date
                                  and s.group in (select g.code from sp_groups as g where g.parent = sales.group)
$$ LANGUAGE SQL;


                             \connect "smartpos"

CREATE OR REPLACE VIEW public.sp_daily_sales AS
 SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
            WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
            ELSE 0::bigint
        END) AS total,
    tt.sold::character varying AS sold,
    array_to_json(array_agg(jsonb_build_object('type', tt.type, 'total', tt.total))) AS payments
   FROM ( SELECT t."group",
            count(1) AS cnt,
            sum(t.amount) AS total,
            t.sold,
            t.type
           FROM ( SELECT sp_sales."group",
                    (sp_sales.closed + '06:00:00'::interval)::date AS sold,
                    jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                    (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                   FROM sp_sales
                  WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.deleted IS NULL) t
          GROUP BY t."group", t.sold, t.type
          ORDER BY t.type) tt
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;

ALTER TABLE public.sp_daily_sales
  OWNER TO postgres;
GRANT ALL ON TABLE public.sp_daily_sales TO postgres;
GRANT SELECT ON TABLE public.sp_daily_sales TO sp_superadmin;
GRANT SELECT ON TABLE public.sp_daily_sales TO sp_admin;

--------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sp_dately_sales(sold character varying DEFAULT (('now'::text)::date)::text)
  RETURNS SETOF sp_daily_sales AS
$BODY$

 SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
            WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
            ELSE 0::bigint
        END) AS total,
    tt.sold::varchar,
    array_to_json(array_agg(jsonb_build_object('type', tt.type, 'total', tt.total))) AS payments
   FROM ( SELECT t."group",
            count(1) AS cnt,
            sum(t.amount) AS total,
            t.sold,
            t.type
           FROM ( SELECT sp_sales."group",
                    to_char(sp_sales.closed,substring('YYYY-MM-DD',1,char_length(sold))) AS sold,
                    jsonb_array_elements(sp_sales.payments) ->> 'type'::text AS type,
                    (jsonb_array_elements(sp_sales.payments) ->> 'amount'::text)::integer AS amount
                   FROM sp_sales
                  WHERE sp_sales.payments IS NOT NULL AND sp_sales.closed IS NOT NULL AND sp_sales.deleted IS NULL
	  ) t
          GROUP BY t."group", sold, t.type
          ORDER BY t.type) tt
  WHERE tt.sold = sp_dately_sales.sold
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;


$BODY$
  LANGUAGE sql STABLE
  COST 100
  ROWS 1000;
ALTER FUNCTION public.sp_dately_sales(character varying)
  OWNER TO postgres;

----------------------------------------------------

CREATE OR REPLACE VIEW public.sp_v_sales AS
 SELECT sp_sales.id,
    sp_sales."group",
    sp_sales.code,
    sp_sales.created,
    sp_sales.starts,
    sp_sales.ends,
    sp_sales.closed,
    sp_sales.edited,
    sp_sales.total,
    sp_sales.status,
    sp_sales.creator,
    sp_sales.performer,
    sp_sales.client,
    sp_sales.assets,
    sp_sales.goods,
    sp_sales.payments,
    sp_sales.configs,
    sp_sales.deleted,
    sp_sales.returned
   FROM sp_sales;

ALTER TABLE public.sp_v_sales
  OWNER TO postgres;

------------------------------------

CREATE OR REPLACE FUNCTION public.sp_dately_sales(
    "group" character varying,
    sold character varying DEFAULT (('now'::text)::date)::text)
  RETURNS SETOF sp_daily_sales AS
$BODY$

 SELECT tt."group",
    sum(tt.cnt) AS cnt,
    sum(
        CASE
            WHEN tt.type = 'Наличными'::text OR tt.type = 'Карточкой'::text THEN tt.total
            ELSE 0::bigint
        END) AS total,
    tt.sold::varchar,
    array_to_json(array_agg(jsonb_build_object('type', tt.type, 'total', tt.total))) AS payments
   FROM ( SELECT t."group",
            count(1) AS cnt,
            sum(t.amount) AS total,
            t.sold,
            t.type
           FROM ( SELECT sp_v_sales."group",
                    to_char(sp_v_sales.closed,substring('YYYY-MM-DD',1,char_length(sp_dately_sales.sold))) AS sold,
                    jsonb_array_elements(sp_v_sales.payments) ->> 'type'::text AS type,
                    (jsonb_array_elements(sp_v_sales.payments) ->> 'amount'::text)::integer AS amount
                   FROM sp_v_sales
                  WHERE ( sp_dately_sales.group IS NULL OR sp_dately_sales.group = sp_v_sales.group )
			AND sp_v_sales.payments IS NOT NULL
			AND sp_v_sales.closed IS NOT NULL
			AND sp_v_sales.deleted IS NULL
	  ) t
          GROUP BY t."group", sold, t.type
          ORDER BY t.type) tt
  WHERE tt.sold = sp_dately_sales.sold
  GROUP BY tt."group", tt.sold
  ORDER BY tt.sold;


$BODY$
  LANGUAGE sql STABLE
  COST 100
  ROWS 1000;
ALTER FUNCTION public.sp_dately_sales(character varying, character varying)
  OWNER TO postgres;

-------------------------------------
