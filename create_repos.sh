#!/usr/bin/env bash
# =============================================================================
# GitHub リポジトリ一括作成スクリプト
# 前提: gh CLI・jq インストール済み & gh auth login 済み
# 設定: repos.json を編集してください
# =============================================================================
set -euo pipefail

# =============================================================================
# 引数パース
# =============================================================================
ADD_PERMISSIONS=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --add-permissions)
      ADD_PERMISSIONS=true
      shift
      ;;
    -h|--help)
      cat <<'EOS'
使い方: create_repos.sh [--add-permissions] [CONFIG]

  --add-permissions  既存リポジトリに対しても権限付与処理を実行する。
                     リポジトリ作成はスキップし、JSON に記載した権限を
                     追加・更新する。JSON にない既存の権限は変更しない。
  CONFIG             設定ファイルパス (デフォルト: ./repos.json)
EOS
      exit 0
      ;;
    --)
      shift
      POSITIONAL+=("$@")
      break
      ;;
    -*)
      echo "未知のオプション: $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

CONFIG="${POSITIONAL[0]:-$(dirname "$0")/repos.json}"

# =============================================================================
# ログ出力
# =============================================================================
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; NC=''
fi
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_info() { echo -e "${YELLOW}[INFO]${NC}  $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# 事前チェック
# =============================================================================
command -v gh  &>/dev/null || { log_err "gh CLI が見つかりません。"; exit 1; }
command -v jq  &>/dev/null || { log_err "jq が見つかりません。brew install jq などでインストールしてください。"; exit 1; }
gh auth status &>/dev/null || { log_err "gh auth login を先に実行してください。"; exit 1; }
[[ -f "${CONFIG}" ]]       || { log_err "設定ファイルが見つかりません: ${CONFIG}"; exit 1; }

# 設定ファイルの最低限のバリデーション
jq -e '.org | type == "string" and length > 0' "${CONFIG}" >/dev/null \
  || { log_err "${CONFIG}: .org が文字列として指定されていません"; exit 1; }
jq -e '.repos | type == "array" and length > 0' "${CONFIG}" >/dev/null \
  || { log_err "${CONFIG}: .repos が空または配列ではありません"; exit 1; }
jq -e '[.repos[] | .name | type == "string" and length > 0] | all' "${CONFIG}" >/dev/null \
  || { log_err "${CONFIG}: .repos[].name に空または非文字列が含まれています"; exit 1; }

ORG="$(jq -r '.org' "${CONFIG}")"
REPO_COUNT="$(jq '.repos | length' "${CONFIG}")"

if [[ "${ADD_PERMISSIONS}" == "true" ]]; then
  MODE_LABEL="権限のみ追加（既存リポジトリも対象）"
else
  MODE_LABEL="通常（既存リポジトリはスキップ）"
fi

echo "========================================"
echo " GitHub リポジトリ一括作成"
echo " Config : ${CONFIG}"
echo " Org    : ${ORG}"
echo " Repos  : ${REPO_COUNT} 個"
echo " Mode   : ${MODE_LABEL}"
echo "========================================"
echo ""

# =============================================================================
# プレビュー表示
# =============================================================================
truncate_field() {
  local s="$1" max="${2:-23}"
  if (( ${#s} > max )); then
    printf '%s…' "${s:0:max-1}"
  else
    printf '%s' "$s"
  fi
}

printf '  %-24s %-24s %-24s %-24s %-24s\n' "リポジトリ" "admin" "admin_team" "write" "write_team"
printf '  %-24s %-24s %-24s %-24s %-24s\n' "------------------------" "------------------------" "------------------------" "------------------------" "------------------------"
# 空配列は jq 側で「（なし）」に置換しておく
# （tab は IFS whitespace 扱いになり、空フィールドが連続すると read で潰れるため）
jq -r '
  def fill: if . == "" then "（なし）" else . end;
  .repos[] | [
    .name,
    (.admin // [] | join(",") | fill),
    (.admin_team // [] | join(",") | fill),
    (.write // [] | join(",") | fill),
    (.write_team // [] | join(",") | fill)
  ] | @tsv
' "${CONFIG}" | \
  while IFS=$'\t' read -r name admin admin_team write write_team; do
    printf '  %-24s %-24s %-24s %-24s %-24s\n' \
      "$(truncate_field "${name}")" \
      "$(truncate_field "${admin}")" \
      "$(truncate_field "${admin_team}")" \
      "$(truncate_field "${write}")" \
      "$(truncate_field "${write_team}")"
  done
echo ""
read -rp "上記の設定で実行しますか？ [y/N]: " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "キャンセルしました。"; exit 0; }
echo ""

# =============================================================================
# リポジトリ1件の処理
#   return 0: 成功（新規作成 + 権限付与）
#   return 2: 既存のためスキップ
#   return 3: 既存リポジトリへの権限付与のみ成功
#   return 1: 失敗
# =============================================================================
process_repo() {
  local index="$1"
  local repo user team exists=false
  repo="$(jq -r ".repos[${index}].name" "${CONFIG}")"
  echo "----------------------------------------"
  log_info "処理中: ${ORG}/${repo}"

  if gh repo view "${ORG}/${repo}" &>/dev/null; then
    exists=true
  fi

  if [[ "${exists}" == "true" ]]; then
    if [[ "${ADD_PERMISSIONS}" == "true" ]]; then
      log_info "  → 既存リポジトリのため作成をスキップし、権限付与のみ実行"
    else
      log_info "  → すでに存在するためスキップ"
      return 2
    fi
  else
    # 1. リポジトリ作成（gh 側でデフォルト README を同時に作成）
    gh repo create "${ORG}/${repo}" --private --add-readme 2>&1 | sed 's/^/  /' \
      || { log_err "  リポジトリ作成に失敗"; return 1; }
    log_ok "  リポジトリ作成完了"
  fi

  # 2. admin（個人）
  while IFS= read -r user; do
    [[ -z "${user}" ]] && continue
    gh api --method PUT -H "Accept: application/vnd.github+json" \
      "/repos/${ORG}/${repo}/collaborators/${user}" \
      -f permission=admin --silent \
      || { log_err "  admin 付与失敗（個人）: ${user}"; return 1; }
    log_ok "  admin 付与（個人）: ${user}"
  done < <(jq -r ".repos[${index}].admin[]?" "${CONFIG}")

  # 3. admin_team（チーム）
  while IFS= read -r team; do
    [[ -z "${team}" ]] && continue
    gh api --method PUT -H "Accept: application/vnd.github+json" \
      "/orgs/${ORG}/teams/${team}/repos/${ORG}/${repo}" \
      -f permission=admin --silent \
      || { log_err "  admin 付与失敗（チーム）: ${team}"; return 1; }
    log_ok "  admin 付与（チーム）: ${team}"
  done < <(jq -r ".repos[${index}].admin_team[]?" "${CONFIG}")

  # 4. write（個人）
  while IFS= read -r user; do
    [[ -z "${user}" ]] && continue
    gh api --method PUT -H "Accept: application/vnd.github+json" \
      "/repos/${ORG}/${repo}/collaborators/${user}" \
      -f permission=push --silent \
      || { log_err "  write 付与失敗（個人）: ${user}"; return 1; }
    log_ok "  write 付与（個人）: ${user}"
  done < <(jq -r ".repos[${index}].write[]?" "${CONFIG}")

  # 5. write_team（チーム）
  while IFS= read -r team; do
    [[ -z "${team}" ]] && continue
    gh api --method PUT -H "Accept: application/vnd.github+json" \
      "/orgs/${ORG}/teams/${team}/repos/${ORG}/${repo}" \
      -f permission=push --silent \
      || { log_err "  write 付与失敗（チーム）: ${team}"; return 1; }
    log_ok "  write 付与（チーム）: ${team}"
  done < <(jq -r ".repos[${index}].write_team[]?" "${CONFIG}")

  if [[ "${exists}" == "true" ]]; then
    return 3
  fi
  return 0
}

# =============================================================================
# メインループ
# =============================================================================
SUCCESS=(); FAILED=(); SKIPPED=(); UPDATED=()

for i in $(seq 0 $((REPO_COUNT - 1))); do
  REPO="$(jq -r ".repos[${i}].name" "${CONFIG}")"
  set +e
  process_repo "${i}"
  rc=$?
  set -e
  case "${rc}" in
    0) SUCCESS+=("${REPO}") ;;
    2) SKIPPED+=("${REPO}") ;;
    3) UPDATED+=("${REPO}") ;;
    *) FAILED+=("${REPO}") ;;
  esac
  echo ""
done

# =============================================================================
# サマリー
# =============================================================================
echo "========================================"
echo " 完了サマリー"
echo "========================================"
echo "  リポジトリ作成: ${#SUCCESS[@]} 件"
if [[ ${#SUCCESS[@]} -gt 0 ]]; then
  for r in "${SUCCESS[@]}"; do echo "    ✓ ${r}"; done
fi
if [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo "  権限更新: ${#UPDATED[@]} 件"
  for r in "${UPDATED[@]}"; do echo "    ↻ ${r}"; done
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo "  スキップ: ${#SKIPPED[@]} 件"
  for r in "${SKIPPED[@]}"; do echo "    - ${r}"; done
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "  失敗:     ${#FAILED[@]} 件"
  for r in "${FAILED[@]}"; do echo "    ✗ ${r}"; done
  exit 1
fi
echo ""
