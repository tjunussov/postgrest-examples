- raw level security

ALTER TABLE sp_users ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_users_policy ON sp_users;
CREATE POLICY sp_users_policy ON sp_users
USING (
  (coalesce(current_setting('sp.login.email', TRUE)::VARCHAR, '') = email
   AND pass = crypt(coalesce(current_setting('sp.login.pass', TRUE)::VARCHAR, ''), pass))
  OR "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_groups ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_groups_policy ON sp_groups;
CREATE POLICY sp_groups_policy ON sp_groups
USING (
  coalesce(current_setting('sp.login.host', TRUE)::VARCHAR, '') = host OR
  code = any(sp_get_groups()) OR
  parent = coalesce(current_setting('sp.current.group', TRUE)::VARCHAR, '')
)
WITH CHECK (code = any(sp_get_groups()));



ALTER TABLE sp_assets ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_assets_policy ON sp_assets;
CREATE POLICY sp_assets_policy ON sp_assets
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_goods ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_goods_policy ON sp_goods;
CREATE POLICY sp_goods_policy ON sp_goods
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_sales ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_sales_policy ON sp_sales;
CREATE POLICY sp_sales_policy ON sp_sales
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_clients ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_clients_policy ON sp_clients;
CREATE POLICY sp_clients_policy ON sp_clients
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_discounts ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_discounts_policy ON sp_discounts;
CREATE POLICY sp_discounts_policy ON sp_discounts
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_resources ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_resources_policy ON sp_resources;
CREATE POLICY sp_resources_policy ON sp_resources
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);



ALTER TABLE sp_certificates ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_certificates_policy ON sp_certificates;
CREATE POLICY sp_certificates_policy ON sp_certificates
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);

ALTER TABLE sp_apps ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_apps_policy ON sp_apps;
CREATE POLICY sp_apps_policy ON sp_apps
USING (
  "group" = any(sp_get_groups())
)
WITH CHECK (
  "group" = any(sp_get_groups())
);


ALTER TABLE sp_updatelist ENABLE ROW LEVEL SECURITY;

--DROP POLICY IF EXISTS sp_updatelist_policy ON sp_updatelist;
CREATE POLICY sp_updatelist_policy ON sp_updatelist
USING (
  current_setting('request.jwt.claim.email', TRUE) is not null
)
WITH CHECK (
  current_setting('request.jwt.claim.email', TRUE) is not null
);

