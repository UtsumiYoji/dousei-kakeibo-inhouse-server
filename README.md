# dousei-kakeibo-inhouse-server

自宅サーバーで `dousei-kakeibo` と `dousei-kakeibo-linebot` を運用するためのIaCリポジトリです。アプリ本体やbot本体はここでビルドせず、それぞれのリポジトリがpushしたDocker imageをpullして起動します。

## Services

- `postgres`: 家計簿DB
- `app`: `dousei-kakeibo` Next.js app
- `worker`: 自動支出生成worker
- `linebot`: LINE支出登録bot

`linebot` はDockerネットワーク内で `http://app:3000` を呼びます。既存の家計簿APIは外部公開せず、ホストの `127.0.0.1:3000` にだけ公開します。

## Setup

```bash
cp .env.example .env
```

`.env` の値を自宅サーバー用に変更します。

```env
POSTGRES_PASSWORD=change-me
DATABASE_URL=postgresql://kakeibo:change-me@postgres:5432/kakeibo?schema=public
APP_IMAGE=ghcr.io/utsumiyoji/dousei-kakeibo-app:latest
WORKER_IMAGE=ghcr.io/utsumiyoji/dousei-kakeibo-worker:latest
LINEBOT_IMAGE=ghcr.io/utsumiyoji/dousei-kakeibo-linebot:latest
LINE_CHANNEL_SECRET=...
LINE_CHANNEL_ACCESS_TOKEN=...
LINE_ALLOWED_USER_IDS=...
SUMMARY_SCHEDULE_CONFIG_PATH=/app/config/summary-schedule.json
```

起動:

```bash
docker compose up -d
```

ログ:

```bash
docker compose logs -f app worker linebot
```

停止:

```bash
docker compose down
```

DB volumeも削除する場合:

```bash
docker compose down -v
```

## Reverse proxy

LINE Webhookは公開HTTPS URLが必要です。既存のnginx、Caddy、Cloudflare Tunnelなどで以下へ転送してください。

```text
https://<your-domain>/<path> -> http://127.0.0.1:3001/webhook/line
```

Webアプリを外から開く場合は、同じく既存プロキシから `http://127.0.0.1:3000` へ転送します。外部公開する場合は、プロキシ側で認証やIP制限を検討してください。

## Scheduled LINE summary

`summary-schedule.json` で、LINEへ定期送信する家計簿サマリーを設定します。初期値は `enabled: false` です。

送信内容:

- 未清算支出の件数と合計金額
- 清算状況のメンバー別 `+/-` 金額

毎日21:00に送る例:

```json
{
  "enabled": true,
  "timezone": "Asia/Tokyo",
  "recipients": [],
  "schedules": [
    { "type": "daily", "time": "21:00" }
  ]
}
```

毎週日曜21:00と毎月1日09:00に送る例:

```json
{
  "enabled": true,
  "timezone": "Asia/Tokyo",
  "recipients": [],
  "schedules": [
    { "type": "weekly", "dayOfWeek": "sun", "time": "21:00" },
    { "type": "monthly", "dayOfMonth": 1, "time": "09:00" }
  ]
}
```

`recipients` が空の場合は `LINE_ALLOWED_USER_IDS` の全員へ送ります。特定の送信先だけにしたい場合はLINE userIdを `recipients` に列挙してください。

## Checks

Compose設定:

```bash
docker compose config
```

linebot health:

```bash
curl http://127.0.0.1:3001/health
```

コンテナ内疎通:

```bash
docker compose exec linebot node -e "fetch('http://app:3000/api/members').then(r=>console.log(r.status))"
```

## Updates

各アプリrepoで新しいimageをpushした後、このrepo上でpullして再起動します。

```bash
docker compose pull
docker compose up -d
```
