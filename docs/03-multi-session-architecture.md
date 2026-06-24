# Kiến trúc Multi-Session / Multi-Topic / Multi-User

## Tổng quan các lớp

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

Một nguyên tắc cốt lõi: repo này KHÔNG reimplement relay. Nó đọc và ghi config
của `ccc` (nguồn dữ liệu chính cho kết nối), rồi thêm registry (metadata điều
phối), schedules (cron), và scripts (vòng đời).

## Ba trục "multi"

### Multi-session
Mỗi Claude là một tmux window riêng, một working dir riêng. Registry lưu purpose,
tags, status, auto_restart, last_command. Không giới hạn cứng (thực tế ~10-20
cùng lúc tùy RAM/CPU).

### Multi-topic (Telegram Forum)
Group phải bật Topics (Supergroup → Enable Topics). Khi tạo session, gọi
`createForumTopic` API để nhận `topic_id`. Mỗi session map 1:1 với một topic.
Routing outbound: `topic_id` quyết định Claude nào trả lời vào topic nào.

### Multi-user / multi-group
**Một bot token phục vụ nhiều group.** Telegram Bot API vốn hỗ trợ: bot nhận
message từ mọi group nó được add. Mỗi session lưu `group_id` riêng:

```
session "work-x"   → group_id -1003460044206  (Work group)
session "family"   → group_id -1003918647978  (Family group)
```

Routing gọn: `getSessionGroupID = session.group_id ?? config.group_id` (fallback).
Vì vậy multi-user mới hoạt động: mỗi group là "không gian" của một người hoặc
một đội khác, cùng chung một bot.

## Bốn nguồn dữ liệu, phải đồng bộ

| Nguồn | Vai trò | Ai ghi |
|---|---|---|
| `ccc config.json` | Kết nối: token, group_id, sessions(topic/path/window) | ccc + repo này |
| `registry.json` | Điều phối: purpose, tags, status, auto_restart | repo này |
| `schedules.json` | Cron: cron expr, prompt, last_run, enabled | repo này |
| `~/Library/LaunchAgents/com.vccc.*.plist` | launchd job định nghĩa | repo này (cron_to_launchd) |

Rule R-12: mỗi thay đổi phải cập nhật đủ nguồn. `relay_cron_list` phát hiện
orphan (plist mà không có registry entry, và ngược lại).

## Luồng hai chiều (điển hình)

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

## Lớp lập lịch (persistent)

`launchd` (native macOS scheduler) là primary, không phải crontab. Lý do: sống
qua reboot (plist trong `~/Library/LaunchAgents` tự load lại); wake from sleep
(cron skip job khi Mac ngủ, launchd chạy khi thức); auto-retry và keep-alive
tích hợp sẵn; một plist bằng một job, nhóm bằng prefix `com.vccc.*` nên
`launchctl list | grep com.vccc`.

Khi trigger:
```
launchd fire → run-scheduled.sh <name>
→ đọc schedules.json → check/create session → tmux send-keys <prompt>
→ update last_run/last_status → notify Telegram topic
```

`CronCreate` (built-in của Claude Code session) chỉ là fallback cho task tạm
trong phiên hiện tại (session-only, 7 ngày, REPL phải idle), không persistent.
Repo này mặc định launchd.

## Vì sao đóng gói thành Skill

Toàn bộ orchestration được đóng thành một Claude Code Skill (SKILL.md). Bạn nói
"tạo 3 session nghiên cứu đối thủ" hoặc "lên lịch báo cáo mỗi sáng 8h" bằng tiếng
tự nhiên, Claude tự gọi đúng hàm `relay_*`, không cần nhớ cú pháp CLI. Skill còn
lưu rules (R-00 đến R-27), là những bài học debug thực tế (PATH trong launchd,
thứ tự hàm, múi giờ...) để không lặp lỗi.
