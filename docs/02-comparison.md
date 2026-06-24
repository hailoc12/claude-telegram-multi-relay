# So sánh với các giải pháp khác

## Tóm tắt nhanh

| Khả năng | Claude (native) | ccc (kidandcat) | Các relay khác | **Repo này** |
|---|---|---|---|---|
| Chat 2 chiều Claude ↔ điện thoại | ❌ | ✅ | ✅ | ✅ |
| Multi-session song song | ❌ | ⚠️ thủ công | ❌ / hạn chế | ✅ fleet |
| Multi-topic (Telegram forum) | ❌ | ✅ (1 session) | ❌ | ✅ (N topic) |
| Multi-user / multi-group (1 bot) | ❌ | ⚠️ | ❌ | ✅ |
| Lên lịch định kỳ persistent | ❌ | ❌ | ❌ | ✅ launchd |
| Auto-restart / self-heal | ❌ | ❌ | ❌ | ✅ |
| Broadcast / quản lý fleet | ❌ | ❌ | ❌ | ✅ |
| OTP approval permission qua Telegram | ❌ | ✅ | tùy tool | ✅ (qua ccc) |
| Là Claude Code Skill (gọi bằng tiếng nói) | — | ❌ | ❌ | ✅ |

## 1. Tích hợp native của Claude

Anthropic cung cấp:

- **claude.ai** — web/app chat. Không truy cập codebase máy bạn, không chạy lệnh.
- **Claude API** — bạn tự build mọi thứ.
- **Claude Code** (CLI) — mạnh, nhưng phải ngồi trước terminal.
- **Claude Code trên cloud / IDE** — vẫn là bạn-chỉ-định, không phải "AI gọi
  bạn khi cần".

**Không có native Telegram relay.** Không có cơ chế nào để Claude Code *tự*
nhắn cho bạn trên điện thoại khi nó xong việc, hay bạn điều khiển nó từ xa. Đây
là khoảng trống mà các relay điền vào.

## 2. ccc — Claude Code Companion (kidandcat/ccc)

Đây là **nền tảng (upstream)** mà repo này xây lên. Credits đầy đủ ở
[README](../README.md#credits--relationship-to-ccc).

- ✅ relay 2 chiều Claude ↔ Telegram, ổn định, dùng production.
- ✅ OTP permission approval, file relay, `/new`, `/continue`, `/c`.
- ❌ **Single-session per invocation**: bạn tự mở nhiều terminal, tự nhớ session
  nào ở topic nào. Không có khái niệm "fleet".
- ❌ Không lên lịch được. Không tự restart. Không broadcast.

**Repo này = ccc (relay engine) + lớp orchestration multi + scheduling.**

## 3. Các Telegram relay opensource khác

| Project | Mô hình | Multi? | Scheduling? |
|---|---|---|---|
| [JessyTsui/Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote) | Async task qua email/discord/telegram. Gửi task → nhận notify khi xong. | 1 session/task | ❌ |
| [RichardAtCT/claude-code-telegram](https://github.com/RichardAtCT/claude-code-telegram) | Bot hội thoại trên codebase. | ❌ | ❌ |
| [RemoteCode](https://kcisoul.github.io/remotecode/) | Điều khiển Claude từ Telegram, giữ session/history. | 1 session active | ❌ |
| [Claudegram](https://claudegram.com/) | Telegram, streaming response. | ❌ | ❌ (SaaS) |
| Claude Code Channels (plugin) | Telegram/Discord/iMessage vào 1 session đang chạy. | ❌ | ❌ |

**Điểm chung của tất cả:** xử lý tốt bài toán *1 Claude ↔ 1 kênh chat*.

**Khoảng trống mà repo này lấp:** *N Claude ↔ N topic ↔ N group*, kèm **lên lịch
persistent** (launchd, sống qua reboot/sleep) và **quản lý fleet** (monitor,
broadcast, auto-heal, audit). Không có project nào ở trên làm phần này.

## Khi nào dùng gì?

- **Chỉ cần chat 1 Claude từ điện thoại** → dùng thẳng `ccc`. Đơn giản, đủ dùng.
- **Cần nhiều kênh (email/discord)** → JessyTsui/Claude-Code-Remote.
- **Muốn SaaS, không muốn host** → Claudegram.
- **Muốn chạy đội AI nhiều session, mỗi session 1 topic, tự lên lịch, tự
  self-heal, điều khiển từ điện thoại** → **repo này.**

## Trade-off thành thật

Repo này mạnh ở orchestration, nhưng:

- **macOS-first.** Scheduling dùng `launchd` (native macOS). Linux dùng systemd
  (chưa wrap), Windows chưa hỗ trợ. Phần relay core (multi-session/topic/group)
  vẫn chạy đa nền tảng; chỉ phần scheduling gắn macOS.
- **Phụ thuộc ccc.** Relay engine là ccc (binary). Repo này không reimplement
  relay — nó orchestrate ccc. (Đây cũng là điểm mạnh: kế thừa một engine ổn định.)
- **Headless server / máy luôn bật** là thiết kế lý tưởng. Máy sleep thường
  xuyên → nên để trên một mini/Mac luôn-on hoặc VPS chạy ccc.

Chi tiết kiến trúc multi-session: [03-multi-session-architecture.md](./03-multi-session-architecture.md).
