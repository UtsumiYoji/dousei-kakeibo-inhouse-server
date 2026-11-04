#!/bin/bash
# PostgreSQL を毎日 BACKUP_TIME に pg_dump(custom形式)で /backups へ出力する。
# 引数 --once で1回だけ実行して終了する(手動バックアップ用)。
set -euo pipefail

: "${BACKUP_TIME:=03:00}"
: "${BACKUP_KEEP_DAYS:=14}"
BACKUP_DIR=/backups

backup() {
  local ts tmp out
  ts=$(date +%Y%m%d-%H%M%S)
  # 書き込み途中のファイルを同期対象にしないよう、完了するまでは隠しファイル名にしておく
  tmp="$BACKUP_DIR/.kakeibo-$ts.dump.partial"
  out="$BACKUP_DIR/kakeibo-$ts.dump"

  if pg_dump --format=custom --file="$tmp"; then
    mv "$tmp" "$out"
    echo "[db-backup] ok: $(basename "$out") ($(du -h "$out" | cut -f1))"
  else
    rm -f "$tmp"
    echo "[db-backup] FAILED" >&2
    return 1
  fi

  find "$BACKUP_DIR" -maxdepth 1 -name 'kakeibo-*.dump' -mtime +"$BACKUP_KEEP_DAYS" -print -delete \
    | sed 's/^/[db-backup] removed old: /'
}

if [ "${1:-}" = "--once" ]; then
  backup
  exit $?
fi

trap 'exit 0' TERM INT

while true; do
  now=$(date +%s)
  next=$(date -d "today $BACKUP_TIME" +%s)
  [ "$next" -le "$now" ] && next=$(date -d "tomorrow $BACKUP_TIME" +%s)
  echo "[db-backup] next backup at $(date -d "@$next" '+%F %T %Z')"
  sleep $((next - now)) &
  wait $!
  backup || true
done
