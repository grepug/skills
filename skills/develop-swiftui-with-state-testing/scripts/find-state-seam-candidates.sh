#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  echo "find-state-seam-candidates: rg is required" >&2
  exit 2
fi

if (( $# == 0 )); then
  set -- .
fi

for input in "$@"; do
  if [[ ! -e "${input}" ]]; then
    echo "find-state-seam-candidates: path does not exist: ${input}" >&2
    exit 2
  fi
done

declare -a swift_files=()

collect_swift_files() {
  local input=""

  for input in "$@"; do
    if [[ -f "${input}" ]]; then
      [[ "${input}" == *.swift ]] && printf '%s\n' "${input}"
      continue
    fi

    if [[ -d "${input}" ]]; then
      rg --files "${input}" \
        --glob '*.swift' \
        --glob '!**/.build/**' \
        --glob '!**/Build/**' \
        --glob '!**/DerivedData/**' \
        --glob '!**/Pods/**' \
        --glob '!**/Carthage/**' \
        --glob '!**/Tests/**' \
        --glob '!**/Generated/**' \
        --glob '!**/*Generated.swift'
      continue
    fi
  done
}

while IFS= read -r file; do
  [[ -n "${file}" ]] && swift_files+=("${file}")
done < <(collect_swift_files "$@" | sort -u)

if (( ${#swift_files[@]} == 0 )); then
  echo "No State Seam review candidates found."
  exit 0
fi

view_declaration_pattern='\b(struct|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^\{]*:[^\{]*\bView\b'
container_candidate_pattern='(@State|@StateObject|@ObservedObject|@Environment|@EnvironmentObject|@AppStorage|@SceneStorage|@Query|\.task([[:space:]]*\{|\()|\.onAppear[[:space:]]*\{|\.onChange[[:space:]]*\(|\.onOpenURL[[:space:]]*\{|\.refreshable[[:space:]]*\{|Task[[:space:]]*\{|URLSession|Navigation(Stack|SplitView)|navigation(Path|Destination)|\.sheet[[:space:]]*\(|\.alert[[:space:]]*\(|\.fullScreenCover[[:space:]]*\(|\.(save|load|delete|create|submit|retry|refresh|login|logout)[[:space:]]*\()'
application_behavior_pattern='\b(AppModel|ApplicationModel|AppState|ApplicationState|NavigationModel|NavigationState|Router|Coordinator)\b|\b(routes?|navigationPath|selectedTab|rootState|rootFlow|globalPresentation|deepLink|openURL|scenePhase|sessionState|restoration|windowState)\b|handled[[:space:]]*\([^)]*Outcome'
application_match_pattern='(@MainActor|@Observable|import[[:space:]]+SwiftUI|\b(class|actor|struct)[[:space:]]+(AppModel|ApplicationModel|AppState|ApplicationState|NavigationModel|NavigationState|Router|Coordinator)\b|\b(var|private\(set\)[[:space:]]+var|func)[[:space:]]+(routes?|navigationPath|selectedTab|rootState|rootFlow|globalPresentation|deepLink|openURL|scenePhase|sessionState|restoration|windowState|handled|navigationPathChanged|presentationDismissed|deepLinkReceived)\b)'

found_container=0
for file in "${swift_files[@]}"; do
  if ! rg -q "${view_declaration_pattern}" "${file}"; then
    continue
  fi

  matches="$(rg -n --no-heading --color never "${container_candidate_pattern}" "${file}" || true)"
  if [[ -z "${matches}" ]]; then
    continue
  fi

  found_container=1
  printf 'container candidate: %s\n' "${file}"
  while IFS= read -r match; do
    printf '  %s\n' "${match}"
  done <<<"${matches}"
  printf '  review: classify Presentation, Feature Container, and Application Container responsibilities semantically\n\n'
done

found_application=0
for file in "${swift_files[@]}"; do
  if ! rg -q '@Observable' "${file}"; then
    continue
  fi
  if ! rg -qi "${application_behavior_pattern}" "${file}"; then
    continue
  fi

  matches="$(rg -ni --no-heading --color never "${application_match_pattern}" "${file}" || true)"
  if [[ -z "${matches}" ]]; then
    continue
  fi

  found_application=1
  printf 'application-model candidate: %s\n' "${file}"
  while IFS= read -r match; do
    printf '  %s\n' "${match}"
  done <<<"${matches}"
  printf '  review: verify direct construction, SwiftUI-free public state, ownership, intents, and risk-bearing behavior\n\n'
done

if (( found_container == 0 && found_application == 0 )); then
  echo "No State Seam review candidates found."
fi
