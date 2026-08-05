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

view_declaration_pattern='\b(struct|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^\{]*:[^\{]*\bView\b'
candidate_pattern='(@State|@StateObject|@ObservedObject|@Environment|@EnvironmentObject|@AppStorage|@SceneStorage|@Query|\.task([[:space:]]*\{|\()|\.onAppear[[:space:]]*\{|\.onChange[[:space:]]*\(|\.refreshable[[:space:]]*\{|Task[[:space:]]*\{|URLSession|navigation(Path|Destination)|\.sheet[[:space:]]*\(|\.alert[[:space:]]*\(|\.fullScreenCover[[:space:]]*\(|\.(save|load|delete|create|submit|retry|refresh|login|logout)[[:space:]]*\()'

found=0
for file in "${swift_files[@]}"; do
  if ! rg -q --pcre2 "${view_declaration_pattern}" "${file}"; then
    continue
  fi

  matches="$(rg -n --no-heading --color never --pcre2 "${candidate_pattern}" "${file}" || true)"
  if [[ -z "${matches}" ]]; then
    continue
  fi

  found=1
  printf '%s\n' "${file}"
  while IFS= read -r match; do
    printf '  %s\n' "${match}"
  done <<<"${matches}"
  printf '  review: classify visual-only state separately from product behavior or effects\n\n'
done

if (( found == 0 )); then
  echo "No SwiftUI state-seam review candidates found."
fi
