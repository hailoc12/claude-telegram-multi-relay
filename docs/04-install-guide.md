# Hướng dẫn cài đặt & sử dụng

> Yêu cầu: **macOS** (để dùng phần scheduling launchd). Phần relay core chạy
> đa nền tảng, nhưng bản hoàn chỉnh cần launchd.

## Điều kiện tiên quyết

| Yêu cầu | Cài đặt | Kiểm tra |
|---|---|---|
| Claude Code CLI | `npm i -g @anthropic-ai/claude-code` | `claude --version` |
| `ccc` (relay engine) | xem [kidandcat/ccc](https://github.com/kidandcat/ccc) | `ccc --version` |
| tmux | `brew install tmux` | `tmux -V` |
| python3 | `brew install python` | `python3 --version` |
| GitHub CLI (tuỳ chọn, để push) | `brew install gh` | `gh --version` |

**Bắt buộc phải có `ccc` trước.** Repo này orchestrate ccc — nếu chưa cài ccc,
cài nó trước theo guide của tác giả kidandcat.

## Bước 1 — Tạo Telegram Bot & lấy token

1. Mở Telegram, tìm **@BotFather**.
2. Gõ `/newbot` → đặt tên + username (kết thúc bằng `bot`).
3. BotFather trả về **HTTP API token** dạng `123456789:ABCdef...`. **Lưu lại.**
4. Tạo một **group mới**, add bot vào làm admin.
5. Vào group settings → **Topics** (Supergroup → Edit → Turn on Topics).
   → Group trở thành forum, mỗi session sẽ là 1 topic.
6. Lấy **group_id**: add bot `@RawDataBot` hoặc `@getidsbot` vào group, nó sẽ
   báo group_id (dạng `-100xxxxxxxxxx`). Xóa bot đó sau khi xong.

> group_id âm (`-100...`) = supergroup. Đúng rồi, đừng sửa dấu.

## Bước 2 — Cài đặt repo này

```bash
git clone https://github.com/hailoc12/claude-telegram-multi-relay.git
cd claude-telegram-multi-relay
```

Copy skill vào nơi Claude Code đọc skills:

```bash
# Vị trí skill mặc định của Claude Code
SKILL_DIR=~/.claude/skills/claude-telegram-multi-relay
mkdir -p "$SKILL_DIR"
cp SKILL.md "$SKILL_DIR/"
cp -r scripts "$SKILL_DIR/"
```

Copy bridge script + tạo data dir:

```bash
ORCH=~/.claude/ccc-orchestrator
mkdir -p "$ORCH/logs"
cp scripts/run-scheduled.sh "$ORCH/"
cp config/relay.example.env "$ORCH/relay.env"   # rồi sửa nếu cần
```

## Bước 3 — Cấu hình bot token (qua ccc)

Repo này **không tự giữ token** — token nằm trong config của `ccc` (single
source of truth). Cấu hình một lần:

```bash
ccc setup <DÁN_TOKEN_TỪ_BOTFATHER_VÀO_ĐÂY>
```

`ccc setup` sẽ: validate token → cài hook vào Claude → đăng ký launchd service
lắng nghe Telegram. Sau đó:

```bash
ccc setgroup        # nhập group_id (để tạo topic /new hoạt động)
ccc doctor          # check toàn bộ dependency OK
```

Kiểm tra config đã có token + group:

```bash
cat ~/.config/ccc/config.json | python3 -m json.tool
# Phải thấy: bot_token, group_id, chat_id
```

## Bước 4 — Cấu hình optional (env)

Chỉnh `~/.claude/ccc-orchestrator/relay.env` nếu path của bạn khác mặc định
(ví dụ ccc binary không trong PATH, projects_dir khác):

```bash
# Bỏ comment và sửa:
#CCC_BIN="/usr/local/bin/ccc"
#PROJECTS_DIR="$HOME/Projects"
```

Mặc định: projects_dir = `~/Library/Mobile Documents/.../9. active` (iCloud).
Bearer các giá trị khác đều có default hợp lý.

## Bước 5 — Dùng (qua skill hoặc CLI)

### Cách A — qua Claude Code Skill (khuyến nghị)

Trong một Claude Code session:

```
/vibe-ccc-orchestrator        # hoặc gọi tên skill bạn đặt
```

Rồi nói tự nhiên:

- *"tạo session mới tên comp-research-a, nghiên cứu đối thủ A"*
- *"lên lịch daily-standup mỗi sáng 9h thứ 2-6, session daily-report"*
- *"broadcast 'tóm tắt tiến độ' cho tất cả session"*
- *"list sessions"*

### Cách B — qua CLI trực tiếp

```bash
# Source lib
source scripts/relay.sh

relay_new comp-research-a "Research competitor A"
relay_send comp-research-a "Phân tích điểm yếu của A, lưu ra report.md"
relay_list

# Scheduling
relay_cron_create daily-standup "7 9 * * 1-5" daily-report \
  "Generate today's standup with yesterday metrics"
relay_cron_list
launchctl list | grep com.vccc     # verify agents loaded
```

### Hoặc dùng dispatcher trực tiếp:

```bash
./scripts/relay.sh new my-session "desc"
./scripts/relay.sh cron-list
```

## Bước 6 — Verify end-to-end

1. Mở Telegram group → thấy bot tự tạo topic mới (tên = session name).
2. Bot gửi confirm "✅ Session ready".
3. Gõ trong topic: *"hello, bạn là ai?"* → Claude reply trong vài giây.
4. Tạo cron → đợi đến giờ → thấy bot tự chạy + notify.

Nếu không nhận được inbound: `ccc doctor` + check `ccc listen`.
Nếu cron không fire: `relay_cron_list` (cột loaded/disk) + `tail ~/.claude/ccc-orchestrator/logs/<name>.err`.

## Gỡ cài đặt

```bash
# Xóa mọi launchd agent đã tạo
launchctl list | grep com.vccc | awk '{print $3}' | while read l; do
  launchctl unload ~/Library/LaunchAgents/$l.plist
  rm -f ~/Library/LaunchAgents/$l.plist
done
# Xóa data
rm -rf ~/.claude/ccc-orchestrator
rm -rf ~/.claude/skills/claude-telegram-multi-relay
```

Bot token còn nằm trong ccc config — gỡ hẳn theo guide của ccc.
