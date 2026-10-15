#!/usr/bin/env bash
# Создаёт SealedSecret'ы для car-catalog:
#   apps/cloudnative-pg/cluster/sealedsecret-car-web.yaml  — пароль роли car_web (CNPG managed role, ns gitea)
#   apps/utilities/car-catalog/sealedsecret.yaml           — строка подключения PostgREST + basic auth для /admin
#
# ЗАПУСКАТЬ ИЗ НАСТОЯЩЕГО ТЕРМИНАЛА на машине с:
#   - kubectl, чей текущий контекст смотрит на твой k3s-кластер
#   - kubeseal CLI (brew install kubeseal)
#   - openssl
#
# Запускать из корня репозитория my_lab. Повторный запуск = ротация обоих паролей.

set -euo pipefail

CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets-controller"

DB_NS="gitea"
DB_HOST="postgres-rw.gitea.svc.cluster.local"
DB_NAME="n8n"
APP_NS="car-catalog"
ADMIN_USER="${ADMIN_USER:-admin}"

OUT_DB="apps/cloudnative-pg/cluster/sealedsecret-car-web.yaml"
OUT_APP="apps/utilities/car-catalog/sealedsecret.yaml"

for bin in kubectl kubeseal openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin не найден" >&2; exit 1; }
done
[ -d apps/utilities/car-catalog ] || { echo "Запусти из корня my_lab" >&2; exit 1; }

seal() {
  kubeseal --controller-namespace "$CONTROLLER_NAMESPACE" --controller-name "$CONTROLLER_NAME" --format yaml
}

# hex — без спецсимволов, безопасно вставлять в URI
CAR_WEB_PASS="${CAR_WEB_PASS:-$(openssl rand -hex 24)}"
ADMIN_PASS="${ADMIN_PASS:-$(openssl rand -base64 18 | tr -d '/+=')}"

# 1) пароль роли car_web для CNPG (тип basic-auth обязателен для managed roles)
kubectl create secret generic car-web-db \
  --namespace "$DB_NS" \
  --type kubernetes.io/basic-auth \
  --from-literal=username=car_web \
  --from-literal=password="$CAR_WEB_PASS" \
  --dry-run=client -o yaml | seal > "$OUT_DB"

# 2) строка подключения PostgREST и basic auth ingress-nginx (ключ auth, формат htpasswd).
#    apr1 (MD5), а не bcrypt: nginx в ingress-nginx на Alpine/musl bcrypt не понимает.
{
  kubectl create secret generic car-catalog-db \
    --namespace "$APP_NS" \
    --from-literal=uri="postgres://car_web:${CAR_WEB_PASS}@${DB_HOST}:5432/${DB_NAME}?sslmode=require" \
    --dry-run=client -o yaml | seal
  echo "---"
  kubectl create secret generic car-catalog-admin-auth \
    --namespace "$APP_NS" \
    --from-literal=auth="${ADMIN_USER}:$(openssl passwd -apr1 "$ADMIN_PASS")" \
    --dry-run=client -o yaml | seal
} > "$OUT_APP"

echo ">>> Записано: $OUT_DB"
echo ">>> Записано: $OUT_APP"
echo
echo ">>> Логин в https://carsdb.home.arpa/admin/ — СОХРАНИ В ПАРОЛЬНЫЙ МЕНЕДЖЕР:"
echo "    ${ADMIN_USER} / ${ADMIN_PASS}"
echo
echo ">>> Пароль car_web знать не нужно: им управляют CNPG и PostgREST."
echo ">>> Проверь diff и закоммить."
