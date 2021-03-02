-- roles

--DROP ROLE IF EXISTS sp_anon;
CREATE ROLE sp_anon;

--DROP ROLE IF EXISTS sp_auth;
CREATE ROLE sp_auth NOINHERIT LOGIN;
ALTER ROLE sp_auth WITH ENCRYPTED PASSWORD 'smartpos_auth';

GRANT sp_anon TO sp_auth;

GRANT SELECT ON TABLE sp_users, sp_groups TO sp_anon;
GRANT EXECUTE ON FUNCTION
login(VARCHAR, VARCHAR, VARCHAR) TO sp_anon;

--DROP ROLE IF EXISTS sp_admin;
CREATE ROLE sp_admin;

--DROP ROLE IF EXISTS sp_superadmin;
CREATE ROLE sp_superadmin;

GRANT sp_admin, sp_superadmin TO sp_auth;

--DROP ROLE IF EXISTS sp_sale;
CREATE ROLE sp_sale;
GRANT sp_sale TO sp_auth;
GRANT SELECT ON TABLE public.sp_sales TO sp_sale;

GRANT SELECT ON TABLE
sp_users, sp_assets,
sp_goods, sp_clients, sp_clients_search,
sp_discounts, sp_groups, sp_resources, sp_certificates,
sp_apps_all, sp_apps, sp_appeal, sp_updatelist
TO sp_admin, sp_superadmin;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
sp_sales, sp_clients, sp_discounts, sp_users, sp_certificates, sp_apps_all, sp_apps, sp_appeal,
sp_assets, sp_goods, sp_resources
TO sp_admin, sp_superadmin;

GRANT SELECT (sales_code_seq), UPDATE (sales_code_seq) ON TABLE sp_groups TO sp_admin, sp_superadmin;
GRANT SELECT ON TABLE sp_codes TO sp_admin, sp_superadmin;

GRANT USAGE, SELECT ON SEQUENCE
sp_sales_id_seq, sp_discounts_id_seq,
sp_clients_id_seq, sp_users_id_seq, sp_certificates_id_seq, sp_apps_all_id_seq, sp_apps_id_seq, sp_appeal_id_seq,
sp_assets_id_seq, sp_goods_id_seq, sp_resources_id_seq
TO sp_admin, sp_superadmin;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
sp_users TO sp_superadmin;

GRANT USAGE, SELECT ON SEQUENCE
sp_users_id_seq TO sp_superadmin;

GRANT EXECUTE ON FUNCTION
update_password(VARCHAR, VARCHAR, VARCHAR) TO sp_admin, sp_superadmin;


GRANT UPDATE ON TABLE sp_updatelist TO sp_admin, sp_superadmin;


--DROP ROLE IF EXISTS sp_master;
CREATE ROLE sp_master;
GRANT sp_master TO sp_auth;
-- GRANT SELECT ON TABLE
-- sp_users, sp_groups
-- TO sp_master;
