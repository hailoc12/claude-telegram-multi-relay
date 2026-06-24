# claude-telegram-multi-relay

> **Tầng giao tiếp & vận hành của con người cho đội AI Worker.**
> Điều khiển một **fleet** các Claude Code session từ Telegram — **hai chiều**,
> **multi-session**, **multi-topic**, **multi-user/multi-group**, kèm **lập lịch
> định kỳ persistent**.

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](./LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-blueviolet)]()
[![Built on ccc](https://img.shields.io/badge/built%20on-ccc%20(kidandcat)-orange)](https://github.com/kidandcat/ccc)
[![Part of AI Native Company](https://img.shields.io/badge/part%20of-AI%20Native%20Company-success)](https://github.com/hailoc12/ai_native_company)

### English (TL;DR)
A Claude Code **Skill + bash toolkit** that lets you drive many Claude Code
sessions from your phone via Telegram: each session is a Telegram forum *topic*,
one bot can serve *multiple groups* (multi-user), replies are real-time
(two-way), and recurring tasks run via macOS `launchd` (survives reboot/sleep,
auto-restarts dead sessions). It is the **human communication & operations
layer** for the [AI Native Company](https://github.com/hailoc12/ai_native_company)
model. Built on top of the [`ccc`](https://github.com/kidandcat/ccc) relay
engine — this repo contributes the **multi-session/topic/user orchestration +
scheduling + fleet management** layer that ccc alone does not provide.

---

## Mục lục

- [📖 Ebook hướng dẫn (PDF)](#-ebook-hướng-dẫn)
- [Đây là gì](#đây-là-gì)
- [Telegram Relay là gì?](#telegram-relay-là-gì)
- [Điểm khác biệt: Multi + Bidirectional](#điểm-khác-biệt-multi--bidirectional)
- [So sánh với các giải pháp khác](#so-sánh-với-các-giải-pháp-khác)
- [Vị trí trong AI Native Company](#vị-trí-trong-ai-native-company)
- [Cài đặt & sử dụng](#cài-đặt--sử-dụng)
- [Ví dụ thực tế](#ví-dụ-thực-tế)
- [Cấu trúc repo](#cấu-trúc-repo)
- [Credits & relationship to ccc](#credits--relationship-to-ccc)
- [License](#license)

---

## 📖 Ebook hướng dẫn

Cuốn **"Cẩm nang vận hành đội AI từ xa"** — hướng dẫn chi tiết từng bước cách
dùng skill này, từ tạo bot Telegram đến vận hành một đội Claude tự chạy theo
lịch và tự phục hồi.

| Định dạng | File |
|---|---|
| 📕 PDF | [`ebook/huong-dan-claude-telegram-multi-relay.pdf`](./ebook/huong-dan-claude-telegram-multi-relay.pdf) |
| 📝 Nguồn Markdown | [`ebook/huong-dan-claude-telegram-multi-relay.md`](./ebook/huong-dan-claude-telegram-multi-relay.md) |

Mười chương + ba phụ lục: Telegram Relay là gì → kiến trúc → cài đặt → quản lý
session → multi-topic/user/group → broadcast → lập lịch launchd → giám sát &
self-heal → tích hợp AI Native Company → bảng 27 quy tắc + khắc phục sự cố.

---

## Đây là gì

Bạn chạy Claude Code trên một máy (Mac / headless server / mini luôn-on). Vấn
đề: Claude là CLI trong terminal — bạn phải ngồi trước máy đó mới dùng được.

`claude-telegram-multi-relay` biến Claude Code thành **một đội nhân viên số mà
bạn trò chuyện qua Telegram trên điện thoại**:

- **Mỗi Claude session = một topic** trong Telegram group (kiểu Slack channel).
- **Nhiều session chạy song song**, mỗi cái làm một project riêng.
- **1 bot phục vụ nhiều group** → multi-user, mỗi đội/khách hàng một không gian.
- **Hai chiều thời gian thực**: bạn gõ → Claude làm → Claude trả lời về topic.
- **Tự lên lịch** mỗi sáng / mỗi 15 phút / mỗi thứ 6 — sống qua reboot & sleep.
- **Tự chữa** (auto-restart), **broadcast**, **audit fleet**, **monitor**.

Toàn bộ được đóng gói thành một **Claude Code Skill** — bạn nói *"tạo 3 session
nghiên cứu đối thủ"* hoặc *"lên lịch báo cáo mỗi sáng 8h"* bằng tiếng tự nhiên,
Claude tự gọi đúng thao tác.

> 📖 Chưa rõ khái niệm? Đọc [`docs/01-what-is-telegram-relay.md`](./docs/01-what-is-telegram-relay.md).

---

## Telegram Relay là gì?

Một **relay** (trạm trung chuyển) đứng giữa Claude Code (chạy trên máy bạn) và
Telegram (trên điện thoại):

```
   bạn (điện thoại)  ◄──►  Telegram cloud  ◄──►  RELAY  ◄──►  Claude Code
                                                         (tmux)
```

Relay làm đúng 2 việc:

1. **Inbound:** tin nhắn Telegram → đẩy vào Claude đang chạy.
2. **Outbound:** output của Claude → gửi về Telegram.

→ **Bidirectional.** Bạn và Claude trò chuyện qua Telegram như chat với người
thật — nhưng "người" đó đọc/sửa file, chạy lệnh, deploy ngay trên máy bạn.

**Tại sao Telegram?** Có sẵn mọi nền tảng, Bot API miễn phí & mạnh, có **Forum
Topics** (tách session như channel), HTML mode format đẹp, không rate-limit
khắt khe.

---

## Điểm khác biệt: Multi + Bidirectional

Một relay đơn giản chỉ nối **1 Claude ↔ 1 chat**. Repo này thêm 3 trục:

| Trục | Nghĩa |
|---|---|
| **Multi-session** | N Claude Code chạy song song, mỗi cái project/context/lịch sử riêng |
| **Multi-topic** | Mỗi session = 1 Telegram forum topic. Mở group → thấy danh sách đội |
| **Multi-user / multi-group** | **1 bot phục vụ nhiều group**. Session thuộc group nào reply về group đó |

**Bidirectional thực sự** không phải "gửi task, chờ email". Mà là hội thoại thời
gian thực:

```
Bạn:    check log app.log 20 dòng cuối
Claude: (gửi về 20 dòng, đóng khung code)
Bạn:    dòng 15 lỗi auth, fix token đi
Claude: đã fix, restart, xong ✓
```

Mỗi reply là 1 message Telegram — reply, forward, pin, search lại bất cứ lúc nào.
Toàn bộ tương tác với đội AI nằm trong Telegram, ứng dụng bạn đã có sẵn.

> 📖 Chi tiết kiến trúc & luồng 2 chiều: [`docs/03-multi-session-architecture.md`](./docs/03-multi-session-architecture.md)

---

## So sánh với các giải pháp khác

| Khả năng | Claude native | ccc | Relay khác¹ | **Repo này** |
|---|:--:|:--:|:--:|:--:|
| Chat 2 chiều Claude ↔ điện thoại | ❌ | ✅ | ✅ | ✅ |
| Multi-session song song (fleet) | ❌ | ⚠️ | ❌ | ✅ |
| Multi-topic (Telegram forum) | ❌ | ✅(1) | ❌ | ✅(N) |
| Multi-user / multi-group (1 bot) | ❌ | ⚠️ | ❌ | ✅ |
| Lập lịch persistent (reboot/sleep) | ❌ | ❌ | ❌ | ✅ |
| Auto-restart / self-heal | ❌ | ❌ | ❌ | ✅ |
| Broadcast + quản lý fleet | ❌ | ❌ | ❌ | ✅ |
| Là Claude Code Skill (giao tiếp tiếng tự nhiên) | — | ❌ | ❌ | ✅ |

¹ JessyTsui/Claude-Code-Remote, RichardAtCT/claude-code-telegram, RemoteCode,
Claudegram, Claude Code Channels — đều giải tốt bài toán *1 Claude ↔ 1 kênh*.

**Khoảng trống repo này lấp:** *N Claude ↔ N topic ↔ N group* + **scheduling
persistent** + **fleet management**. Không có project nào ở trên làm phần này.

**Khi nào dùng gì:**
- Chỉ chat 1 Claude → dùng thẳng [`ccc`](https://github.com/kidandcat/ccc).
- Muốn nhiều kênh (email/discord) → JessyTsui/Claude-Code-Remote.
- Muốn SaaS, không host → Claudegram.
- **Muốn chạy đội AI nhiều session + tự lên lịch + self-heal + điều khiển từ điện thoại → repo này.**

> 📖 Phân tích đầy đủ: [`docs/02-comparison.md`](./docs/02-comparison.md)

**Trade-off thành thật:** macOS-first (scheduling dùng `launchd`); phụ thuộc
`ccc` (không reimplement relay — cố ý, để kế thừa engine ổn định); lý tưởng nhất
cho máy always-on / headless server.

---

## Vị trí trong AI Native Company

Repo này là **tầng giao tiếp & vận hành của con người (human communication &
operations layer)** cho mô hình [**AI Native Company**](https://github.com/hailoc12/ai_native_company)
— nơi 1 người vận hành với năng lực 15–20 người nhờ đội AI Worker.

```
┌──────────────────────────────────────────────────┐
│         AI NATIVE COMPANY  (ai_native_company)    │
│                                                   │
│   AI Worker • AI Worker • AI Worker  (nhiều role) │
│        ▲            ▲            ▲                │
│        │   ai_native_company định nghĩa Worker    │
│        │   (SOP, SLI, KPI, Skill, Knowledge)      │
└────────┼──────────────────────────────────────────┘
         │ con người giao tiếp & điều phối ĐỘI Worker ở đâu?
         ▼
┌──────────────────────────────────────────────────┐
│   claude-telegram-multi-relay  (REPO NÀY)         │
│                                                   │
│   • mỗi AI Worker = 1 Claude session              │
│   • mỗi Worker có 1 Telegram topic                │
│   • 1 bot phục vụ nhiều group (team / khách hàng) │
│   • lên lịch Worker chạy định kỳ (standup, report)│
│   • monitor + self-heal toàn đội                  │
└──────────────────────────────────────────────────┘
```

Trong AI Native Company, mỗi **AI Worker** là một nhân sự số chuyên biệt
(marketing, sales, finance, research...). Repo này cung cấp **cơ chế để con
người**:

- **giao việc** cho từng Worker (và Worker trả lời lại) — qua Telegram topic,
- **xem toàn bộ đội** đang làm gì (list / status / monitor),
- **phối hợp** nhiều Worker (broadcast),
- **lên lịch** Worker tự chạy (standup mỗi sáng, report mỗi cuối tuần),
- **không cần mở máy** — toàn bộ qua điện thoại.

=> Nếu `ai_native_company` là **bộ não/org chart** (định nghĩa Worker), thì repo
này là **hệ thống liên lạc nội bộ + ca trực** (con người điều phối đội mỗi ngày).

---

## Cài đặt & sử dụng

> Đầy đủ: [`docs/04-install-guide.md`](./docs/04-install-guide.md). Tóm tắt:

**Điều kiện:** macOS · Claude Code CLI · [`ccc`](https://github.com/kidandcat/ccc) · tmux · python3.

**1. Tạo bot + group:**
```bash
# Telegram → @BotFather → /newbot → lấy token
# Tạo group → add bot làm admin → bật Topics
# Add @getidsbot → lấy group_id (-100xxxxxxxxxx)
```

**2. Clone + cài skill:**
```bash
git clone https://github.com/hailoc12/claude-telegram-multi-relay.git
cd claude-telegram-multi-relay

SKILL_DIR=~/.claude/skills/claude-telegram-multi-relay
mkdir -p "$SKILL_DIR" && cp SKILL.md scripts -t "$SKILL_DIR"

ORCH=~/.claude/ccc-orchestrator
mkdir -p "$ORCH/logs"
cp scripts/run-scheduled.sh config/relay.example.env -t "$ORCH/"
mv "$ORCH/relay.example.env" "$ORCH/relay.env"
```

**3. Cấu hình bot token (qua ccc — token nằm ở ccc, không ở repo này):**
```bash
ccc setup <DÁN_TOKEN_TỪ_BOTFATHER>     # validate token + cài hook + launchd service
ccc setgroup                            # nhập group_id
ccc doctor                              # verify
```

**4. Dùng** — qua Claude Code Skill (nói tự nhiên) hoặc CLI:
```bash
source scripts/relay.sh
relay_new comp-research-a "Research competitor A"
relay_send comp-research-a "Phân tích điểm yếu A, lưu report.md"
relay_cron_create daily-standup "7 9 * * 1-5" daily-report "Standup with yesterday metrics"
relay_cron_list
launchctl list | grep com.vccc
```

---

## Ví dụ thực tế

**Đội nghiên cứu song song** — 5 Claude, mỗi con 1 đối thủ, broadcast 1 lệnh:
```bash
for c in a b c d e; do relay_new "comp-$c" "Research competitor $c"; done
relay_broadcast "Deep research: market position, pricing, weaknesses. Save output/<name>.md" all
```

**Báo cáo tự động mỗi sáng** — không cần mở máy:
```bash
relay_cron_create daily-standup "7 9 * * 1-5" daily-report \
  "Generate today's standup with yesterday metrics"
```

**Đội tự chữa** — session chết → tự restart, notify nếu quá giới hạn:
```bash
relay_cron_create fleet-monitor "*/30 * * * *" monitor "Check all sessions health"
```

---

## Cấu trúc repo

```
claude-telegram-multi-relay/
├── README.md                      # bạn đang ở đây
├── SKILL.md                       # Claude Code Skill (orchestration logic + rules)
├── LICENSE                        # CC BY-NC-SA 4.0
├── scripts/
│   ├── relay.sh                   # core lib: new/send/broadcast/list/kill/cron-*
│   ├── run-scheduled.sh           # launchd ↔ Claude bridge (PATH-safe, self-healing)
│   └── cron_to_launchd.py         # cron expr → macOS launchd plist
├── config/
│   ├── ccc-config.example.json    # schema ccc config (multi-session/group model)
│   └── relay.example.env          # optional overrides (paths, binary)
├── templates/
│   └── com.vccc.example.plist     # ví dụ launchd agent
└── docs/
    ├── 01-what-is-telegram-relay.md
    ├── 02-comparison.md
    ├── 03-multi-session-architecture.md
    └── 04-install-guide.md
```

---

## Credits & relationship to ccc

### 🔶 Upstream foundation: [`ccc`](https://github.com/kidandcat/ccc)

Repo này **KHÔNG** reimplement Telegram relay. Nó xây trên **`ccc` (Claude Code
Companion)** của tác giả **[kidandcat](https://github.com/kidandcat)** — một
relay engine Claude↔Telegram ổn định, đã production-hardened, hỗ trợ OTP
permission approval, file relay, và single-session forum topic.

**`ccc` cung cấp (phần foundation):**
- bot token handling, Telegram Bot API long-poll listener
- Claude hook (inbound/outbound message bridge)
- OTP permission approval qua Telegram
- file relay + `/new`, `/continue`, `/c` commands

### 🟢 Đóng góp của repo này (hailoc12)

`ccc` tự thân xử lý **1 session ↔ 1 topic**. Repo này thêm **lớp orchestration
phía trên** — đúng phần mà ccc (và các relay khác) chưa có:

| Đóng góp | Mô tả |
|---|---|
| **Multi-session orchestration** | registry + lifecycle (new/send/broadcast/list/status/kill) cho fleet Claude |
| **Multi-topic management** | tự tạo Telegram forum topic + map 1:1 với mỗi session |
| **Multi-user / multi-group routing** | 1 bot → N group, per-session `group_id` + fallback |
| **Persistent scheduling** | cron → launchd, sống qua reboot + wake-from-sleep + auto-retry |
| **Fleet management** | monitor, broadcast, auto-restart/self-heal, audit, orphan detection |
| **Self-healing bridge** | `run-scheduled.sh`: PATH-safe, pre-flight checks, auto-recreate dead sessions |
| **Claude Code Skill packaging** | toàn bộ orchestration + 27 battle-tested rules đóng gói thành Skill gọi bằng tiếng tự nhiên |

**Tóm lại:** `ccc` = *engine relay 1 session*. Repo này = *bộ chỉ huy điều phối
đội nhiều session + lịch trình + self-heal*. Cả hai kết nối với nhau qua config
của ccc (`~/.config/ccc/config.json`) — repo này đọc/ghi config đó như single
source of truth.

Cảm ơn **kidandcat** vì nền móng vững chắc. ⭐ repo [`ccc`](https://github.com/kidandcat/ccc)
nếu bạn thấy hữu ích.

---

## License

**[CC BY-NC-SA 4.0](./LICENSE)** — Attribution-NonCommercial-ShareAlike.

Khớp với license của [ai_native_company](https://github.com/hailoc12/ai_native_company)
(để cả hệ sinh thái nhất quán, dùng phi thương mại). Bạn được: chia sẻ, remix,
xây tiếp — với điều kiện credit repo này + upstream `ccc`, không dùng thương mại,
và chia sẻ dưới cùng license.

> Lưu ý: `ccc` có license riêng (xem repo của kidandcat). Phần engine relay thuộc
> về kidandcat; phần orchestration trong repo này thuộc CC BY-NC-SA 4.0.

---

*Part of the [AI Native Company](https://github.com/hailoc12/ai_native_company) ecosystem.*
