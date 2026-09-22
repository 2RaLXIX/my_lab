#!/usr/bin/env bash
# Генерирует N8N_ENCRYPTION_KEY и сразу сохраняет его как SealedSecret
# в apps/utilities/n8n/sealedsecret.yaml.
#
# ЗАПУСКАТЬ ИЗ НАСТОЯЩЕГО ТЕРМИНАЛА на машине с:
#   - kubectl, чей текущий контекст смотрит на твой k3s-кластер
#   - kubeseal CLI (brew install kubeseal)
#
# Запускать из корня репозитория my_lab.

set -euo pipefail

NAMESPACE="n8n"
SECRET_NAME="n8n-secret"
OUT_FILE="apps/utilities/n8n/sealedsecret.yaml"
CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets-controller"

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal не найден. Установи: brew install kubeseal" >&2
  exit 1
fi

if [ -z "${N8N_ENCRYPTION_KEY:-}" ]; then
  N8N_ENCRYPTION_KEY="$(openssl rand -base64 32)"
  echo ">>> Сгенерирован новый ключ. СОХРАНИ ЕГО В ПАРОЛЬНЫЙ МЕНЕДЖЕР ПРЯМО СЕЙЧАС:"
  echo "$N8N_ENCRYPTION_KEY"
  echo
fi

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY" \
  --dry-run=client -o yaml \
  | kubeseal \
      --controller-namespace "$CONTROLLER_NAMESPACE" \
      --controller-name "$CONTROLLER_NAME" \
      --format yaml \
  > "$OUT_FILE"

echo ">>> Записано в $OUT_FILE"
echo ">>> Проверь diff и закоммить."
