-- Схема api и view для car-catalog. Не входит в kustomization, Argo CD этот файл не применяет.
--
-- Роли car_web и car_anon создаёт CNPG (managed roles в apps/cloudnative-pg/cluster/cluster.yaml).
-- Этот скрипт выполняется ОДИН раз, после того как Argo CD синкнул Cluster, суперпользователем через сокет:
--
--   kubectl exec -i -n gitea postgres-1 -c postgres -- \
--     psql -d n8n -v ON_ERROR_STOP=1 < apps/utilities/car-catalog/db-setup.sql
--
-- Идемпотентный: повторный запуск безопасен.

-- 0. Роли уже должны существовать (их создаёт оператор).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'car_web')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'car_anon') THEN
    RAISE EXCEPTION 'Нет ролей car_web/car_anon. Проверь: kubectl get cluster postgres -n gitea -o jsonpath=''{.status.managedRolesStatus}''';
  END IF;
END $$;

ALTER ROLE car_web SET statement_timeout = '5s';

-- 1. Отдельная схема api: наружу видна только view, а не вся public.
--    Владелец схемы и view — n8n_user (он же владелец car_queue),
--    поэтому view читает таблицу его правами, а car_anon прав на саму таблицу не получает.
CREATE SCHEMA IF NOT EXISTS api AUTHORIZATION n8n_user;

CREATE OR REPLACE VIEW api.cars AS
SELECT id, car_class, car_name, engine_info, body_index, status, created_at
FROM public.car_queue;
ALTER VIEW api.cars OWNER TO n8n_user;

REVOKE ALL ON SCHEMA api FROM PUBLIC;
GRANT USAGE ON SCHEMA api TO car_anon;
GRANT SELECT ON api.cars TO car_anon;

-- 2. PostgREST перечитает схему без рестарта пода.
NOTIFY pgrst, 'reload schema';

-- 3. Проверка: car_anon видит view и не видит таблицу напрямую.
SET ROLE car_anon;
SELECT count(*) AS cars_visible FROM api.cars;
SELECT has_table_privilege('public.car_queue', 'SELECT') AS direct_table_access;  -- ожидается f
RESET ROLE;
