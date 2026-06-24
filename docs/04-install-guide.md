# Hướng dẫn cài đặt & sử dụng

> Yêu cầu: **macOS** để dùng phần scheduling launchd. Phần relay core chạy đa
> nền tảng, nhưng bản hoàn chỉnh cần launchd.

## Điều kiện tiên quyết

| Yêu cầu | Cài đặt | Kiểm tra |
|---|---|---|
| Claude Code CLI | `npm i -g @anthropic-ai/claude-code` | `claude --version` |
| `ccc` (relay engine) | xem [kidandcat/ccc](https://github.com/kidandcat/ccc) | `ccc --version` |
| tmux | `brew install tmux` | `tmux -V` |
| python3 | `brew install python` | `python3 --version` |
| GitHub CLI (tuỳ chọn, để push) | `brew install gh` | `gh --version` |

Bắt buộc có `ccc` trước. Repo này orchestrate ccc, chưa cài ccc thì cài nó trước
theo guide của kidandcat.

## Bước 1. Tạo Telegram Bot và lấy token

Một. Mở Telegram, tìm **@BotFather**. Hai. Gõ `/newbot`, đặt tên và username
(kết thúc bằng `bot`). Ba. BotFather trả về token dạng `123456789:ABCdef...`,
lưu lại. Bốn. Tạo group mới, add bot làm admin. Năm. Vào group settings, bật
Topics (Supergroup → Edit → Turn on Topics). Group thành forum, mỗi session sẽ là
một topic. Sáu. Lấy `group_id`: thêm bot `@RawDataBot` hoặc `@getidsbot` vào
group, nó báo group_id (dạng `-100xxxxxxxxxx`). Xong thì xóa bot đó đi.

group_id âm (`-100...`) là supergroup. Đúng rồi, đừng sửa dấu.

## Bước 2. Cài đặt repo này

```bash
git clone https://github.com/hailoc12/claude-telegram-multi-relay.git
cd claude-telegram-multi-relay
```

Copy skill vào nơi Claude Code đọc skills:

```bash
SKILL_DIR=~/.claude/skills/claude-telegram-multi-relay
mkdir -p "$SKILL_DIR"
cp SKILL.md "$SKILL_DIR/"
cp -r scripts "$SKILL_DIR/"
```

Copy bridge script và tạo data dir:

```bash
ORCH=~/.claude/ccc-orchestrator
mkdir -p "$ORCH/logs"
cp scripts/run-scheduled.sh "$ORCH/"
cp config/relay.example.env "$ORCH/relay.env"   # rồi sửa nếu cần
```

## Bước 3. Cấu hình bot token (qua ccc)

Repo này không tự giữ token. Token nằm trong config của `ccc`, cấu hình một lần:

```bash
ccc setup <DÁN_TOKEN_TỪ_BOTFATHER_VÀO_ĐÂY>
```

`ccc setup` sẽ validate token, cài hook vào Claude, đăng ký launchd service
lắng nghe Telegram. Xong thì:

```bash
ccc setgroup        # nhập group_id (để tạo topic /new hoạt động)
ccc doctor          # check toàn bộ dependency OK
```

Kiểm tra config đã có token và group:

```bash
cat ~/.config/ccc/config.json | python3 -m json.tool
# Phải thấy: bot_token, group_id, chat_id
```

## Bước 4. Cấu hình optional (env)

Chỉnh `~/.claude/ccc-orchestrator/relay.env` nếu path khác mặc định (ccc binary
không trong PATH, projects_dir khác):

```bash
# Bỏ dấu thăng và sửa:
#CCC_BIN="/usr/local/bin/ccc"
#PROJECTS_DIR="$HOME/Projects"
```

Mặc định projects_dir là `~/Library/Mobile Documents/.../9. active` (iCloud).
Các giá trị khác đều có default hợp lý.

## Bước 5. Dùng (qua skill hoặc CLI)

### Cách A, qua Claude Code Skill (khuyến nghị)

Trong một Claude Code session:

```
/vibe-ccc-orchestrator        # hoặc tên skill bạn đặt
```

Rồi nói tự nhiên: "tạo session mới tên comp-research-a, nghiên cứu đối thủ A";
"lên lịch daily-standup mỗi sáng 9h thứ 2-6, session daily-report"; "broadcast
'tóm tắt tiến độ' cho tất cả session"; "list sessions".

### Cách B, qua CLI trực tiếp

```bash
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

### Hoặc dùng dispatcher trực tiếp

```bash
./scripts/relay.sh new my-session "desc"
./scripts/relay.sh cron-list
```

## Bước 6. Verify end-to-end

Một. Mở Telegram group, thấy bot tự tạo topic mới (tên bằng session name). Hai.
Bot gửi confirm "✅ Session ready". Ba. Gõ trong topic "hello, bạn là ai?", Claude
reply trong vài giây. Bốn. Tạo cron, đợi đến giờ, thấy bot tự chạy và notify.

Không nhận inbound: `ccc doctor` rồi check `ccc listen`. Cron không fire:
`relay_cron_list` (cột loaded/disk) rồi `tail ~/.claude/ccc-orchestrator/logs/<name>.err`.

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

Bot token còn nằm trong ccc config, gỡ hẳn theo guide của ccc.
