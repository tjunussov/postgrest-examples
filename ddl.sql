\connect "smartpos"

-- TABLEs
CREATE TABLE IF NOT EXISTS sp_groups (
  id SERIAL NOT NULL,
  code varchar(30) PRIMARY KEY,
  parent VARCHAR(30),
  "name" VARCHAR(255) NOT NULL,
  host VARCHAR(255),
  web VARCHAR(255),
  address VARCHAR(500),
  neighbors JSONB,
  configs JSONB,
  active BOOLEAN DEFAULT TRUE,
  sales_code_seq INTEGER
);

ALTER TABLE sp_groups ADD COLUMN IF NOT EXISTS sales_code_seq INTEGER;

CREATE TABLE IF NOT EXISTS sp_users (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  email VARCHAR(255),
  pass VARCHAR(255) NOT NULL,
  "role" NAME NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  phone VARCHAR(30),
  active BOOLEAN DEFAULT TRUE,
  configs jsonb,
  PRIMARY KEY ("group", email)
);

CREATE TABLE IF NOT EXISTS sp_assets (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code varchar(30),
  "name" VARCHAR(255),
  types JSONB,
  active BOOLEAN DEFAULT TRUE,
  PRIMARY KEY ("group", code)
);

CREATE TABLE IF NOT EXISTS sp_goods (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code varchar(30),
  "name" VARCHAR(255),
  types JSONB,
  active BOOLEAN DEFAULT TRUE,
  PRIMARY KEY ("group", code)
);

CREATE TABLE IF NOT EXISTS sp_clients (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  phone VARCHAR(30),
  "name" VARCHAR(255),
  gender VARCHAR(10),
  email VARCHAR(255),
  discount INTEGER,
  deposit INTEGER,
  created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  note TEXT,
  cardnumber VARCHAR(100),
  visits INTEGER,
  active BOOLEAN DEFAULT TRUE,
  PRIMARY KEY ("group", phone)
);

CREATE TABLE IF NOT EXISTS sp_appeal (

  id SERIAL NOT NULL,
  created TIMESTAMP with time zone NOT NULL,
  chanel VARCHAR(30),
  phone VARCHAR(100),
  email VARCHAR(100),
  otherApplicantInfo VARCHAR(100),
  category VARCHAR(30),
  note TEXT,
  status VARCHAR(10),
  updated TIMESTAMP with time zone NOT NULL,
  "group" VARCHAR(10),
  PRIMARY KEY (id)
);


CREATE TABLE IF NOT EXISTS sp_sales (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code VARCHAR(30),
  created TIMESTAMP WITH TIME ZONE,
  starts TIMESTAMP WITH TIME ZONE,
  ends TIMESTAMP WITH TIME ZONE,
  closed TIMESTAMP WITH TIME ZONE,
  edited TIMESTAMP WITH TIME ZONE,
  payed TIMESTAMP WITH TIME ZONE,
  total INTEGER,
  status VARCHAR(50),
  creator VARCHAR(255),
  performer VARCHAR(255),
  type VARCHAR(50),
  client JSONB,
  assets JSONB,
  goods JSONB,
  payments JSONB,
  configs JSONB,
  fiskal JSONB,
  returned TIMESTAMP WITH TIME ZONE,
  deleted TIMESTAMP WITH TIME ZONE,
  "effectiveDate" DATE,
  "year" INTEGER,
  PRIMARY KEY ("group", code)
);
ALTER TABLE sp_sales ADD COLUMN IF NOT EXISTS "effectiveDate" DATE;
ALTER TABLE sp_sales ADD COLUMN IF NOT EXISTS "year" INTEGER;

CREATE TABLE IF NOT EXISTS sp_discounts (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code VARCHAR(30),
  "name" VARCHAR(255),
  percentage INTEGER,
  created TIMESTAMP WITH TIME ZONE NOT NULL,
  finish TIMESTAMP WITH TIME ZONE,
  note TEXT,
  active BOOLEAN DEFAULT TRUE,
  PRIMARY KEY ("group", code)
);

CREATE TABLE IF NOT EXISTS sp_resources (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code varchar(30),
  "name" VARCHAR(255),
  active BOOLEAN DEFAULT TRUE,
  disabled BOOLEAN DEFAULT FALSE,
  PRIMARY KEY ("group", code)
);

CREATE TABLE IF NOT EXISTS sp_certificates (
  id SERIAL NOT NULL,
  "group" VARCHAR(30),
  code VARCHAR(30),
  created TIMESTAMP WITH TIME ZONE,
  sold TIMESTAMP WITH TIME ZONE,
  used TIMESTAMP WITH TIME ZONE,
  duration INTEGER,
  price INTEGER,
  creator VARCHAR(255),
  client JSONB,
  seller JSONB,
  assets JSONB,
  note TEXT,
  exception BOOLEAN DEFAULT FALSE,
  "initPrice" INTEGER,
  PRIMARY KEY ("group", code)
);

CREATE TABLE IF NOT EXISTS sp_apps_all (
  id SERIAL NOT NULL,
  "name" VARCHAR(30),
  created TIMESTAMP,
  updated TIMESTAMP,
  creator VARCHAR(255),
  "data" JSONB,
  note TEXT
);

CREATE TABLE IF NOT EXISTS sp_apps (
  id SERIAL NOT NULL,
  "app_id" VARCHAR(30),
  "group" VARCHAR(30),
  "user" VARCHAR(30),
  data JSONB,
  PRIMARY KEY ("app_id", "group", "user")
);

CREATE TABLE IF NOT EXISTS sp_updatelist (
  id SERIAL NOT NULL PRIMARY KEY,
  created TIMESTAMP WITH TIME ZONE DEFAULT now(),
  deleted TIMESTAMP WITH TIME ZONE,
  "content" JSONB,
  title TEXT,
  header TEXT,
  footer TEXT,
  "readBy" TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS sp_codes (
  id SERIAL NOT NULL PRIMARY KEY,
  code VARCHAR(100) NOT NULL UNIQUE
);
