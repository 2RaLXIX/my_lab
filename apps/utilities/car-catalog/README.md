# car-catalog — https://carsdb.home.arpa

Каталог и админка для таблицы `car_queue` (база `n8n` в CNPG-кластере `postgres`, ns `gitea`).

- `/` — каталог с живыми данными: поиск, фильтр по классу, моторы, статус. Клик по строке копирует `SELECT * FROM car_queue WHERE id = …` для SQL-ноды n8n.
- `/admin/` — basic auth ingress-nginx. Можно добавить, изменить или удалить машину. На каждое изменение выдаётся готовая команда `kubectl exec … psql` под `n8n_user`. Пароль команда берёт из `n8n-secret` в ns `n8n`, так что в терминале его вводить не надо.

Сайт **не пишет в базу**. PostgREST ходит в Postgres под ролью `car_web`, у которой есть только `SELECT` на view `api.cars`. Записывает только тот, у кого есть `kubectl exec` в ns `gitea`.

```
ingress-nginx (local-ca TLS)
 ├─ carsdb.home.arpa/        → svc car-catalog
 └─ carsdb.home.arpa/admin*  → svc car-catalog  (+ basic auth: car-catalog-admin-auth)
pod car-catalog
 ├─ nginx-unprivileged :8080  site/index.html и nginx.conf из ConfigMap (configMapGenerator)
 │    └─ /api/* (GET/HEAD) → 127.0.0.1:3000
 └─ postgrest :3000 (localhost) → postgres-rw.gitea:5432/n8n как car_web → SET ROLE car_anon → api.cars
```

## Файлы

| Файл | Что |
|---|---|
| `appset.yaml` | `namespace: car-catalog`, подхватывается `apps-simple` |
| `kustomization.yaml` | ресурсы и `configMapGenerator` для страницы и nginx.conf |
| `sealedsecret.yaml` | `car-catalog-db` (URI PostgREST) и `car-catalog-admin-auth`. **Генерируется** скриптом |
| `db-setup.sql` | схема `api`, view, гранты. Выполняется руками один раз, Argo его не применяет |
| `../../cloudnative-pg/cluster/cluster.yaml` | `managed.roles`: `car_anon`, `car_web` |
| `../../cloudnative-pg/cluster/sealedsecret-car-web.yaml` | пароль `car_web` для CNPG. **Генерируется** скриптом |
| `../../../scripts/seal-car-catalog-secrets.sh` | генерация обоих SealedSecret |

## Первый запуск (порядок важен)

```bash
# 1. Секреты. Скрипт покажет логин/пароль для /admin, сохрани их.
./scripts/seal-car-catalog-secrets.sh

# 2. Коммит. Argo CD создаст роли в Postgres и задеплоит под.
#    Под будет 1/2 Ready, пока нет view: PostgREST не находит схему api.
git add apps/utilities/car-catalog apps/cloudnative-pg/cluster scripts/seal-car-catalog-secrets.sh
git commit -m "car-catalog: каталог и админка car_queue" && git push

# 3. Убедиться, что CNPG создал роли:
kubectl get cluster postgres -n gitea -o jsonpath='{.status.managedRolesStatus}'; echo

# 4. Схема и view (один раз):
kubectl exec -i -n gitea postgres-1 -c postgres -- \
  psql -d n8n -v ON_ERROR_STOP=1 < apps/utilities/car-catalog/db-setup.sql
# в конце: cars_visible = 2xx, direct_table_access = f

# 5. Проверка
kubectl -n car-catalog get pods                                    # 2/2 Running
curl -sk https://carsdb.home.arpa/api/cars?limit=1                 # JSON
curl -sk -o /dev/null -w '%{http_code}\n' https://carsdb.home.arpa/admin/   # 401
```

`carsdb.home.arpa` должен резолвиться в ingress так же, как `n8n.home.arpa`. Если используешь Pi-hole или локальный DNS, добавь запись.

## Как обновлять

- **Страница**: правишь `site/index.html`, коммитишь. Хэш ConfigMap меняется, и под перекатывается.
- **Новая колонка в `car_queue`**: добавь её во view (`CREATE OR REPLACE VIEW api.cars AS SELECT …`), затем `NOTIFY pgrst, 'reload schema';`. Рестарт не нужен. Учти, что `DROP COLUMN` у колонки, которая есть во view, Postgres не даст сделать, пока не пересоздашь view.
- **Ротация паролей** (`car_web` и admin): перезапусти скрипт и закоммить. CNPG сменит пароль роли, а под нужно перезапустить, чтобы PostgREST подхватил новый URI: `kubectl -n car-catalog rollout restart deploy/car-catalog`.

## Админка

1. Клик по строке, правка, «Получить команду». Команда копируется сразу и появляется в «Изменения к применению».
2. Вставляешь её в терминал. Изменение выполняется внутри `BEGIN … COMMIT` с `ON_ERROR_STOP=1`, а `RETURNING` показывает результат.
3. «Обновить из базы»: применённые изменения отмечаются ✓. Список хранится в localStorage браузера.

В «Настройках команды» можно сменить способ передачи пароля (Secret, запрос в терминале или интерактивный psql) и под: фиксированный `postgres-1` или поиск текущего primary по лейблам CNPG.

Если PostgREST недоступен, страница показывает встроенный снимок `car_queue` от 15.10.2026 с жёлтой меткой.
