# dousei-kakeibo-inhouse-server

自宅サーバーで `dousei-kakeibo` と `dousei-kakeibo-linebot` を運用するためのIaCリポジトリです。アプリ本体やbot本体はここでビルドせず、それぞれのリポジトリがpushしたDocker imageをpullして起動します。

## Services

- `postgres`: 家計簿DB
- `app`: `dousei-kakeibo` Next.js app
- `worker`: 自動支出生成worker
- `linebot`: LINE支出登録bot
- `cloudflared`: Cloudflare Tunnel(外部公開の経路)

どのサービスもホストのポートにはバインドしません。`linebot` はDockerネットワーク内で `http://app:3000` を呼び、外部からのアクセスは `cloudflared` 経由でのみ `app` / `linebot` に届きます。

## Setup

```bash
cp .env.example .env
```

`.env` の値を自宅サーバー用に変更します。`.env` はgit管理外なので、本番サーバー上で `.env.example` からコピーして作成します。

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
TUNNEL_TOKEN=...
```

- `POSTGRES_PASSWORD` と `DATABASE_URL` 内のパスワードは必ず同じ値に変更します。
- `LINE_ALLOWED_USER_IDS` は、起動後にLINEで `ユーザーID` と送って確認した値を設定します。
- `TUNNEL_TOKEN` は下記「Cloudflare Tunnel」で作成したトンネルのトークンです。

```bash
chmod 600 .env
```

起動:

```bash
docker compose up -d
```

ログ:

```bash
docker compose logs -f app worker linebot cloudflared
```

停止:

```bash
docker compose down
```

DB volumeも削除する場合:

```bash
docker compose down -v
```

## Cloudflare Tunnel

外部公開は `cloudflared` サービスが担います。トンネルはCloudflare側で設定を管理する方式(remote-managed)で、公開ホスト名と転送先はダッシュボード(Zero Trust → Networks → Tunnels)で設定します。

| 公開ホスト名 | 転送先 | path | Cloudflare Access |
| --- | --- | --- | --- |
| `dousei-kakeibo.utsumiyoji.com` | `http://app:3000` | (すべて) | **あり** |
| `dousei-kakeibo-linebot.utsumiyoji.com` | `http://linebot:3001` | `^/webhook/line$` | なし |
| (上記以外) | `http_status:404` | | |

- Webアプリにはログイン機能がないため、`dousei-kakeibo.utsumiyoji.com` は必ずCloudflare Accessで保護します。`linebot` はDockerネットワーク内で `app` を呼ぶため、Accessの影響を受けません。
- LINE Webhookのホスト名にAccessを設定すると、LINEプラットフォームから届かなくなります。代わりに `path` で `/webhook/line` だけを通し、リクエストはLINE SDKの署名検証と `LINE_ALLOWED_USER_IDS` で制限します。
- LINE DevelopersのWebhook URLには `https://dousei-kakeibo-linebot.utsumiyoji.com/webhook/line` を設定します。

公開をやめる場合は `docker compose down` し、Cloudflare側でトンネル(と自動作成されたDNSレコード、Accessアプリケーション)を削除します。

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
docker compose exec linebot node -e "fetch('http://localhost:3001/health').then(r=>r.text()).then(console.log)"
```

トンネル接続:

```bash
docker compose logs cloudflared | grep "Registered tunnel connection"
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
