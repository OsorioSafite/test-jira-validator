#!/usr/bin/env bash
# Local test suite. Runs the real scripts, no push and no credentials.
#
#   .github/tests/run-tests.sh
#
# This is the whole point of moving the logic out of the YAML: the feedback
# loop drops from "commit, push, open a PR, wait" to under a second.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ACTION="$HERE/../actions/jira-pr-gate"
SCRIPTS="$ACTION/scripts"
FIXTURES="$HERE/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PATTERN='\b[A-Z]{2,6}-[0-9]+\b'
PASS=0
FAIL=0

ok() {
  printf '  \033[32m✓\033[0m %s\n' "$1"
  PASS=$((PASS + 1))
}
ko() {
  printf '  \033[31m✗\033[0m %s\n     esperado: %s\n     obtenido: %s\n' "$1" "$2" "$3"
  FAIL=$((FAIL + 1))
}
check() { [[ "$2" == "$3" ]] && ok "$1" || ko "$1" "$2" "$3"; }

# ─────────────────────────────────────────────────────────────────────────
echo
echo "extract-key.sh · qué cuenta como clave de Jira"
# ─────────────────────────────────────────────────────────────────────────
extract() {
  local out="$WORK/out"
  : >"$out"
  BRANCH="$1" TITLE="$2" PATTERN="$PATTERN" GITHUB_OUTPUT="$out" \
    "$SCRIPTS/extract-key.sh" >/dev/null 2>&1
  sed -n 's/^key=//p' "$out"
}

check "clave en la rama"                 "ERP-1234" "$(extract 'ERP-1234' 'ajuste de flete')"
check "clave en el título"               "ERP-1234" "$(extract 'arreglo-rapido' '[ERP-1234] ajuste')"
check "rama gana sobre el título"        "SIS-87"   "$(extract 'SIS-87' '[GEN-15] otra cosa')"
check "sin clave en ninguno"             ""         "$(extract 'arreglo-rapido' 'ajuste rapido')"
check "RELEASE-2024 no es clave"         ""         "$(extract 'RELEASE-2024' 'preparar release')"
check "prefijo de 7 letras no es clave"  ""         "$(extract 'main' 'ABCDEFG-1 algo')"
check "clave pegada al texto"            "DEVP-7"   "$(extract 'rama-test' 'DEVP-7')"
check "toma la primera de dos"           "GEN-15"   "$(extract 'GEN-15' '[SOP-13] y algo mas')"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "apply-gate.sh · sólo este script puede fallar el check"
# ─────────────────────────────────────────────────────────────────────────
gate() {
  KEY="$1" MODE="$2" BRANCH="rama" TITLE="titulo" \
    GITHUB_STEP_SUMMARY="$WORK/summary.md" \
    "$SCRIPTS/apply-gate.sh" >/dev/null 2>&1
  echo $?
}

check "con clave, modo warn  → pasa"      "0" "$(gate 'ERP-1' warn)"
check "con clave, modo block → pasa"      "0" "$(gate 'ERP-1' block)"
check "sin clave, modo warn  → pasa"      "0" "$(gate '' warn)"
check "sin clave, modo block → FALLA"     "1" "$(gate '' block)"
check "sin MODE definido     → pasa"      "0" "$(KEY='' MODE='' BRANCH=r TITLE=t GITHUB_STEP_SUMMARY=$WORK/s.md "$SCRIPTS/apply-gate.sh" >/dev/null 2>&1; echo $?)"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "resolve-labels.jq · alcance, clientes, aval y typos"
# ─────────────────────────────────────────────────────────────────────────
resolve() {
  jq -n \
    --argjson vocab "$(cat "$ACTION/jira-vocabulary.json")" \
    --argjson issue "$(cat "$FIXTURES/$1")" \
    -f "$SCRIPTS/resolve-labels.jq"
}
field() { resolve "$1" | jq -r "$2"; }
list() { resolve "$1" | jq -r "$2 | join(\",\")"; }

check "transversal · alcance"        "TRANSVERSAL"              "$(field transversal.json .scope)"
check "transversal · emoji"          "🔵"                       "$(field transversal.json .scopeEmoji)"
check "transversal · statusCategory" "indeterminate"            "$(field transversal.json .statusCategory)"

check "cliente avalado · alcance"    "CLIENTE ESPECIFICO"       "$(field client-approved.json .scope)"
check "cliente avalado · aval"       "true"                     "$(field client-approved.json .approved)"
check "cliente avalado · nombre"     "Almacafé Cargo"           "$(list client-approved.json .clients)"

check "cliente sin aval · aval"      "false"                    "$(field client-not-approved.json .approved)"

check "conflicto · gana el mayor"    "TRANSVERSAL"              "$(field conflicting-and-typos.json .scope)"
check "conflicto · detecta typo"     "alc-clientte"             "$(list conflicting-and-typos.json .unknownScopeLabels)"
check "conflicto · cliente nuevo"    "cli-nuevocliente"         "$(list conflicting-and-typos.json .unknownClientLabels)"
check "conflicto · no pierde al nuevo" "Almacafé Cargo,cli-nuevocliente" "$(list conflicting-and-typos.json .clients)"

check "sin etiquetas · alcance"      "SIN ETIQUETA DE ALCANCE"  "$(field no-labels.json .scope)"
check "sin etiquetas · hasScope"     "false"                    "$(field no-labels.json .hasScope)"
check "sin etiquetas · sin typos"    ""                         "$(list no-labels.json .unknownScopeLabels)"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "fetch-issue.sh · el fixture evita la API"
# ─────────────────────────────────────────────────────────────────────────
fetch_status() {
  local out="$WORK/fout"
  : >"$out"
  FIXTURE="${1:-}" KEY=DEVP-7 ISSUE_FILE="$WORK/issue.json" GITHUB_OUTPUT="$out" \
    JIRA_BASE_URL="${2:-}" JIRA_USER_EMAIL="" JIRA_API_TOKEN="" \
    "$SCRIPTS/fetch-issue.sh" >/dev/null 2>&1
  sed -n 's/^status=//p' "$out"
}

check "con fixture → ok"             "ok"             "$(fetch_status "$FIXTURES/transversal.json")"
check "sin credenciales → aviso"     "no-credentials" "$(fetch_status "")"

# ─────────────────────────────────────────────────────────────────────────
echo
echo "render-summary.sh · degradación cuando Jira no responde"
# ─────────────────────────────────────────────────────────────────────────
render_status() {
  local s="$WORK/render.md"
  : >"$s"
  FETCH_STATUS="$1" KEY=DEVP-7 RESULT_FILE="$WORK/none.json" \
    GITHUB_STEP_SUMMARY="$s" "$SCRIPTS/render-summary.sh" >/dev/null 2>&1
  local rc=$?
  grep -qi "$2" "$s" && echo "0" || echo "$rc:no-encontro-'$2'"
}

check "401 explica el par correo+token" "0" "$(render_status unauthorized '401')"
check "404 sugiere error de escritura"  "0" "$(render_status not-found 'escritura')"
check "sin credenciales lo dice"        "0" "$(render_status no-credentials 'variables de Jira')"

# ─────────────────────────────────────────────────────────────────────────
echo
if [[ $FAIL -eq 0 ]]; then
  printf '\033[32m%d pruebas, todas pasan\033[0m\n\n' "$PASS"
  exit 0
fi
printf '\033[31m%d pasan · %d fallan\033[0m\n\n' "$PASS" "$FAIL"
exit 1
