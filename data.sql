\connect "smartpos"

INSERT INTO public.sp_groups(code, name, host, web, active, configs) VALUES ('local', 'Company', 'localhost', 'localhost', true, '{"startTime": 10, "endTime": 24}');
INSERT INTO public.sp_groups(code, name, parent, host, web, active, neighbors, configs) VALUES ('company-2', 'Company - 2', 'company', 'test.smartpos.io', 'test.smartpos.io', true, '[{"code": "company-1", "name": "Company - 1"}]','{"startTime": 10, "endTime": 24}');
INSERT INTO public.sp_users("group", email, pass, role, name, active) VALUES ('company', 'user', 'user' , 'sp_admin', 'Тест Admin', true);
INSERT INTO sp_resources (id, "group", code, name, active) VALUES (3, 'local-2', 'Vel', 'Вэл', true);

INSERT INTO public.sp_clients("group", phone, name) VALUES ('local-2', '777 444 7777', 'Иванов Иван');
INSERT INTO sp_assets (id, "group", code, name, types, active) VALUES (1, 'company', 'UlibkaKorolevi', 'Улыбка Королевы', '[{"name": "1ч", "price": 7000, "active": true, "duration": 60}]', true);

INSERT INTO sp_discounts (id, "group", code, name, percentage, created, finish, note, active) VALUES (1, 'company', 'Skidka50%', 'Скидка 50%', 50, '2017-01-16 00:00:00+06', NULL, NULL, true);
INSERT INTO sp_assets (id, "group", code, name, types, active) VALUES (82, 'company-1', 'TaiskoeCHudo', 'Тайское Чудо', '[{"name": "1ч", "price": 7000, "active": true, "duration": 60}, {"name": "1ч-30мин", "price": 9000, "active": true, "duration": 90}, {"name": "2ч", "price": 11000, "active": true, "duration": 120}]', true);
INSERT INTO sp_resources (id, "group", code, name, active) VALUES (8, 'company-1', 'Vassona', 'Вассона', t);

INSERT INTO public.sp_clients("group", phone, name) VALUES ('company-1', '777 777 9999', 'Иванов Иван 1');
INSERT INTO sp_assets (id, "group", code, name, types, active) VALUES (82, 'company-2', 'TaiskoeCHudo', 'Тайское Чудо', '[{"name": "1ч", "price": 7000, "active": true, "duration": 60}, {"name": "1ч-30мин", "price": 9000, "active": true, "duration": 90}, {"name": "2ч", "price": 11000, "active": true, "duration": 120}]', true);
INSERT INTO sp_resources (id, "group", code, name, active) VALUES (8, 'company-2', 'Vassona', 'Вассона', true);

INSERT INTO public.sp_clients("group", phone, name) VALUES ('company-2', '777 777 8888', 'Иванов Иван 2');

SELECT sp_init_sales_code_seq();
