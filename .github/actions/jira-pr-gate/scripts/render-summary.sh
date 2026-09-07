#!/usr/bin/env bash
# Step 5 · Turn the resolved object into the job summary plus annotations.
#
# Rendering only. No decisions, no API calls, no label logic — those already
# happened. Keeping this separate is what makes the output easy to change
# without any risk of touching the gate.
#
# In: RESULT_FILE (output of resolve-labels.jq), FETCH_STATUS, KEY

set -euo pipefail
source "$(dirname "$0")/lib.sh"

# ── Jira unavailable: explain which of the failure modes it was ────────────
if [[ "${FETCH_STATUS:-}" != "ok" ]]; then
  case "${FETCH_STATUS:-}" in
  no-credentials) reason="Faltan las variables de Jira en este repositorio." ;;
  unauthorized) reason="Jira respondió 401: el par correo + token no autentica. Revisar que el correo sea el de la cuenta dueña del token." ;;
  forbidden) reason="Jira respondió 403: la cuenta autentica pero no tiene permiso *Browse Projects* sobre ese proyecto." ;;
  not-found) reason="El ticket **${KEY:-?}** no existe o la cuenta no puede verlo. Puede ser un error de escritura en la clave." ;;
  unreachable) reason="No se pudo contactar a Jira. Revisar el subdominio." ;;
  *) reason="Jira respondió de forma inesperada (\`${FETCH_STATUS:-?}\`)." ;;
  esac

  summary "## Contexto de Jira no disponible"
  summary ""
  summary "$reason"
  warn "Contexto de Jira no disponible" "$reason"
  exit 0
fi

require_env RESULT_FILE

read_field() { jq -r "$1" "$RESULT_FILE"; }
read_list() { jq -r "$1 | if length == 0 then \"\" else join(\", \") end" "$RESULT_FILE"; }

EMOJI="$(read_field '.scopeEmoji')"
SCOPE="$(read_field '.scope')"
CLIENTS="$(read_list '.clients')"
UNKNOWN_SCOPES="$(read_list '.unknownScopeLabels')"
UNKNOWN_CLIENTS="$(read_list '.unknownClientLabels')"
APPROVED="$(read_field '.approved')"
HAS_SCOPE="$(read_field '.hasScope')"

# ── Summary table ─────────────────────────────────────────────────────────
summary "## $EMOJI $(read_field '.key') · $(read_field '.summary')"
table_open
row "Tipo" "$(read_field '.type')"
row "Estado" "$(read_field '.statusName // "?"')"
row "Alcance" "**$SCOPE**"
row "Clientes" "${CLIENTS:--}"
row "Avalado" "$([[ "$APPROVED" == "true" ]] && echo "sí" || echo "no")"
row "Etiquetas" "\`$(read_list '.labels')\`"

# ── Annotations: each one is a distinct, actionable problem ───────────────
if [[ "$HAS_SCOPE" != "true" ]]; then
  warn "Ticket sin etiqueta de alcance" \
    "${KEY:-?} no tiene alc-interno, alc-cliente ni alc-transversal. La notificación de impacto no podría clasificarlo."
fi

if [[ -n "$UNKNOWN_SCOPES" ]]; then
  warn "Etiqueta de alcance desconocida" \
    "${KEY:-?} tiene '$UNKNOWN_SCOPES', que no está en jira-vocabulary.json. Probable error de escritura."
  summary ""
  summary "> Etiqueta \`alc-\` fuera del vocabulario: \`$UNKNOWN_SCOPES\`"
fi

if [[ -n "$UNKNOWN_CLIENTS" ]]; then
  warn "Cliente no registrado" \
    "'$UNKNOWN_CLIENTS' no está en jira-vocabulary.json. Si es un cliente nuevo, hay que agregarlo."
  summary ""
  summary "> Cliente sin registrar: \`$UNKNOWN_CLIENTS\`"
fi

if [[ "$SCOPE" == "CLIENTE ESPECIFICO" && "$APPROVED" != "true" ]]; then
  warn "Sin aval del cliente" \
    "${KEY:-?} impacta a un cliente y no tiene la etiqueta avalado-cliente. Informativo: por ahora no bloquea."
fi
