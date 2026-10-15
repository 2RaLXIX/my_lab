#!/usr/bin/env bash
# Запечатывает API-ключ ElevenLabs в SealedSecret
# apps/utilities/n8n/elevenlabs-sealedsecret.yaml (секрет "elevenlabs" в namespace n8n).
#
# ЗАПУСКАТЬ ИЗ НАСТОЯЩЕГО ТЕРМИНАЛА на машине с:
#   - kubectl, чей текущий контекст смотрит на твой k3s-кластер
#   - kubeseal CLI (brew install kubeseal)
#
# Запускать из корня репозитория my_lab.
# Ключ вводится скрыто и не попадает в историю shell.
# Нужен именно секрет вида sk_..., а не ID ключа из списка в ElevenLabs.

set -euo pipefail

NAMESPACE="n8n"
SECRET_NAME="elevenlabs"
OUT_FILE="apps/utilities/n8n/elevenlabs-sealedsecret.yaml"
CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets-controller"

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal не найден. Установи: brew install kubeseal" >&2
  exit 1
fi

if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
  read -r -s -p "ElevenLabs API key (sk_...): " ELEVENLABS_API_KEY
  echo
fi

case "$ELEVENLABS_API_KEY" in
  sk_*) ;;
  *) echo "Ключ должен начинаться с sk_ (похоже, вставлен ID ключа, а не сам ключ)" >&2; exit 1 ;;
esac

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=ELEVENLABS_API_KEY="$ELEVENLABS_API_KEY" \
  --dry-run=client -o yaml \
  | kubeseal \
      --controller-namespace "$CONTROLLER_NAMESPACE" \
      --controller-name "$CONTROLLER_NAME" \
      --format yaml \
  > "$OUT_FILE"

echo ">>> Записано в $OUT_FILE"
echo ">>> Проверь diff и закоммить вместе с deployment.yaml, configmap.yaml и kustomization.yaml."
