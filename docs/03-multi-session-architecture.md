# Kiến trúc Multi-Session / Multi-Topic / Multi-User

## Tổng quan lớp

```
┌─────────────────────────────────────────────────────────────┐
│                   BẠN (điện thoại / desktop)                 │
│              chat trong Telegram group (forum)               │
└───────────────▲─────────────────────────────▲───────────────┘
                │ inbound                     │ outbound
                ▼                             │
┌──────────────────────────────────────────────────────────────┐
│  LỚP ORCHESTRATION  ← repo này (claude-telegram-multi-relay)  │
│                                                              │
│   registry.json    schedules.json    relay.sh    launchd     │
│   • session meta   • cron jobs       • new/send  • com.vccc.*│
│   • groups/tags    • run history     • broadcast • wake/sleep│
│   • auto-restart                     • cron CRUD • auto-retry │
└───────────────────────────────▲──────────────────────────────┘
                                │ tmux send-keys / window mgmt
                                ▼
┌──────────────────────────────────────────────────────────────┐
│  RELAY ENGINE  ← ccc (kidandcat/ccc)                         │
│                                                              │
│   • bot token • Telegram Bot API long-poll                   │
│   • Claude hook (inbound/outbound)                           │
│   • OTP permission approval  • file relay                    │
└───────────────────────────────▲──────────────────────────────┘
                                │ tmux panes
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
          ┌──────────┐   ┌──────────┐   ┌──────────┐
          │ Claude A │   │ Claude B │   │ Claude C │   ← multi-session
          │ project A│   │ project B│   │ project C│
          └──────────┘   └──────────┘   └──────────┘
```

**Nguyên tắc phân lớp:** repo này KHÔNG reimplement relay. Nó đọc/ghi config
của `ccc` (source of truth cho kết nối) và thêm **registry** (metadata
orchestration) + **schedules** (cron) + **scripts** (lifecycle).

## 3 trục "multi"

### Multi-session
Mỗi Claude là 1 tmux window riêng + 1 working dir riêng. Registry track:
purpose, tags, status, auto_restart, last_command. Không giới hạn số lượng
(thực tế ~10-20 cùng lúc tùy RAM/CPU).

### Multi-topic (Telegram Forum)
Group phải bật **Topics** (Supergroup → Enable Topics). Khi tạo session:
`createForumTopic` API → nhận `topic_id`. Mỗi session map 1:1 với 1 topic.
Routing outbound: `topic_id` xác định Claude nào trả lời vào topic nào.

### Multi-user / multi-group
**1 bot token phục vụ N group.** Telegram Bot API tự nhiên hỗ trợ: bot nhận
message từ mọi group nó được add. Mỗi session lưu `group_id` riêng:

```
session "work-x"   → group_id -1003460044206  (Work group)
session "family"   → group_id -1003918647978  (Family group)
```

Routing: `getSessionGroupID = session.group_id ?? config.group_id` (fallback).
=> Multi-user: mỗi group là "không gian" của một người/đội khác nhau, cùng 1 bot.

## 4 nguồn dữ liệu — phải đồng bộ

| Nguồn | Vai trò | Ai ghi |
|---|---|---|
| `ccc config.json` | Kết nối: token, group_id, sessions(topic/path/window) | ccc + repo này |
| `registry.json` | Orchestration: purpose, tags, status, auto_restart | repo này |
| `schedules.json` | Cron: cron expr, prompt, last_run, enabled | repo này |
| `~/Library/LaunchAgents/com.vccc.*.plist` | launchd job định nghĩa | repo này (cron_to_launchd) |

Rule R-12: mọi thay đổi phải update đủ nguồn. `relay_cron_list` detect orphan
(plist mà không có registry entry và ngược lại).

## Luồng 2 chiều (điển hình)

**Inbound (bạn → Claude):**
```
Bạn gõ trong topic → Telegram Bot API → ccc listener (long-poll)
→ nhận message_thread_id → tra config → tìm session có topic_id khớp
→ tmux send-keys vào window của session đó → Claude nhận input
```

**Outbound (Claude → bạn):**
```
Claude in ra terminal → ccc hook (Stop/Notification) bắt output
→ tra session hiện tại → lấy topic_id + group_id
→ sendMessage API vào đúng topic → bạn thấy trên điện thoại
```

Cả hai chiều chạy thời gian thực, không cần bạn mở terminal.

## Scheduling layer (persistent)

`launchd` (native macOS scheduler) là **primary** — không phải crontab:

- **Sống qua reboot** — plist trong `~/Library/LaunchAgents` tự load lại.
- **Wake from sleep** — cron skip job khi Mac ngủ; launchd chạy khi thức.
- **Auto-retry, keep-alive** built-in.
- **1 plist = 1 job**, group bằng prefix `com.vccc.*` → `launchctl list | grep com.vccc`.

Luồng khi trigger:
```
launchd fire → run-scheduled.sh <name>
→ đọc schedules.json → check/create session → tmux send-keys <prompt>
→ update last_run/last_status → notify Telegram topic
```

`CronCreate` (built-in của Claude Code session) chỉ là **fallback** cho task
tạm trong phiên hiện tại (session-only, 7 ngày, REPL phải idle) — KHÔNG
persistent. Repo này mặc định dùng launchd.

## Why a Skill?

Toàn bộ orchestration được đóng gói thành một **Claude Code Skill** (SKILL.md).
Nghĩa là: bạn nói *"tạo 3 session nghiên cứu đối thủ"* hoặc *"lên lịch báo cáo
mỗi sáng 8h"* bằng tiếng tự nhiên → Claude tự gọi đúng hàm `relay_*`. Không cần
nhớ cú pháp CLI. Skill cũng lưu rules (R-00..R-27) — những bài học debug thực
tế (PATH trong launchd, function ordering, timezone,...) để không lặp lỗi.
