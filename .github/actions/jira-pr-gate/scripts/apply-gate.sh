#!/usr/bin/env bash
# Step 2 · The merge gate. This is the ONLY script allowed to fail the job.
#
# Exit code 1 here is what turns the check red, which is what a branch
# ruleset turns into a disabled merge button.
#
# In:  KEY, MODE (warn|block), BRANCH, TITLE

set -euo pipefail
source "$(dirname "$0")/lib.sh"

MODE="${MODE:-warn}"

if [[ -n "${KEY:-}" ]]; then
  summary "## Ticket \`$KEY\`"
  table_open
  row "Rama" "\`${BRANCH:-}\`"
  row "Título" "${TITLE:-}"
  exit 0
fi

summary "## Este Pull Request no tiene clave de Jira"
summary ""
summary "Ni la rama ni el título contienen una clave con formato \`ERP-1234\`."
table_open
row "Rama" "\`${BRANCH:-}\`"
row "Título" "${TITLE:-}"
summary ""
summary "### Cómo arreglarlo"
summary ""
summary "1. **Editar el título del PR** y ponerle la clave adelante: \`[ERP-1234] ${TITLE:-}\`"
summary "2. O **renombrar la rama** para que incluya la clave"
summary ""
summary "Al editar el título, este check se vuelve a correr solo."
summary ""
summary "### Por qué"
summary ""
summary "Sin la clave no se puede reconstruir qué cambio salió en cada versión,"
summary "ni avisarle al cliente correcto cuando algo lo impacta."

if [[ "$MODE" == "block" ]]; then
  fail "Falta la clave de Jira" \
    "Edita el título del PR y ponele la clave adelante, por ejemplo [ERP-1234]."
  exit 1
fi

warn "Falta la clave de Jira" \
  "Modo advertencia: por ahora deja pasar. En modo bloqueo esto impediría el merge."
exit 0
