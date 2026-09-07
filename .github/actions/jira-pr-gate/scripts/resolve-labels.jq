# Step 4 · Combine the vocabulary with the Jira issue into one result object.
#
# All the label logic lives here, in one declarative place. Adding a scope or
# a client is an edit to jira-vocabulary.json, never to this file.
#
#   jq -n --argjson vocab "$(cat jira-vocabulary.json)" \
#         --argjson issue "$(cat issue.json)" \
#         -f resolve-labels.jq
#
# Membership is tested with `index(...) != null` on purpose: exact array
# membership, not substring matching. A label like `alc-cliente-piloto` must
# never be mistaken for `alc-cliente`.

($issue.fields.labels // [])                          as $labels
| ($vocab.scopes | map(.label))                       as $knownScopes

# Highest `priority` among the scopes present wins. Declarative precedence:
# transversal > cliente > interno, driven by data.
| ($vocab.scopes
    | map(select(.label as $l | $labels | index($l) != null))
    | sort_by(.priority)
    | last)                                           as $scope

| {
    key:     ($issue.key // "?"),
    summary: ($issue.fields.summary // "(sin resumen)"),
    type:    ($issue.fields.issuetype.name // "?"),
    labels:  $labels,

    # Jira status is localized and renameable, so `statusCategory.key` is the
    # only stable value. Carried through but not acted on yet.
    statusName:     ($issue.fields.status.name // null),
    statusCategory: ($issue.fields.status.statusCategory.key // null),

    scope:      ($scope.display // "SIN ETIQUETA DE ALCANCE"),
    scopeEmoji: ($scope.emoji // "⚫"),
    scopeLabel: ($scope.label // null),
    hasScope:   ($scope != null),

    approved: (($labels | index($vocab.approvalLabel)) != null),

    # Unregistered clients fall back to the raw label instead of vanishing.
    clients: [ $labels[]
      | select(startswith("cli-"))
      | . as $c
      | ($vocab.clients[$c] // $c) ],

    # Typo guards: anything shaped like our vocabulary but absent from it.
    unknownScopeLabels: [ $labels[]
      | select(startswith("alc-"))
      | . as $x
      | select(($knownScopes | index($x)) == null) ],

    unknownClientLabels: [ $labels[]
      | select(startswith("cli-"))
      | . as $c
      | select(($vocab.clients | has($c)) == false) ]
  }
