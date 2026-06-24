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

Anthropic cho bạn mấy lựa chọn: claude.ai (chat trên web/app, không đụng codebase
máy bạn, không chạy lệnh), Claude API (tự build mọi thứ từ đầu), Claude Code CLI
(mạnh, nhưng phải ngồi trước terminal), Claude Code trên cloud hoặc IDE (vẫn là
bạn-chỉ-định, không phải AI chủ động gọi bạn khi cần).

Không có native Telegram relay. Không cơ chế nào để Claude Code *tự* nhắn cho
bạn trên điện thoại khi xong việc, hay để bạn điều khiển nó từ xa. Đó là khoảng
trống mà các relay lấp.

## 2. ccc, Claude Code Companion (kidandcat/ccc)

Đây là **nền tảng (upstream)** mà repo này xây lên. Credits đầy đủ ở
[README](../README.md#credits--relationship-to-ccc).

ccc làm tốt: relay hai chiều Claude và Telegram, ổn định, dùng production, có OTP
permission approval, file relay, `/new`, `/continue`, `/c`.

Nhưng ccc có giới hạn. **Single-session per invocation**: bạn tự mở nhiều
terminal, tự nhớ session nào ở topic nào, không có khái niệm "fleet". Không lên
lịch được. Không tự restart. Không broadcast.

Nói ngắn gọn: **repo này bằng ccc (relay engine) cộng thêm lớp orchestration
multi và scheduling.**

## 3. Các Telegram relay opensource khác

| Project | Mô hình | Multi? | Scheduling? |
|---|---|---|---|
| [JessyTsui/Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote) | Async task qua email/discord/telegram. Gửi task, nhận notify khi xong. | 1 session/task | ❌ |
| [RichardAtCT/claude-code-telegram](https://github.com/RichardAtCT/claude-code-telegram) | Bot hội thoại trên codebase. | ❌ | ❌ |
| [RemoteCode](https://kcisoul.github.io/remotecode/) | Điều khiển Claude từ Telegram, giữ session/history. | 1 session active | ❌ |
| [Claudegram](https://claudegram.com/) | Telegram, streaming response. | ❌ | ❌ (SaaS) |
| Claude Code Channels (plugin) | Telegram/Discord/iMessage vào 1 session đang chạy. | ❌ | ❌ |

Điểm chung của tất cả: giải bài toán *một Claude ứng với một kênh chat* khá tốt.

Khoảng trống repo này lấp: *N Claude ứng với N topic ứng với N group*, kèm lập
lịch persistent (launchd, sống qua reboot và sleep) và quản lý fleet (monitor,
broadcast, auto-heal, audit). Phần này chưa project nào ở trên làm.

## Khi nào dùng gì

- Chỉ cần chat một Claude từ điện thoại: dùng thẳng [`ccc`](https://github.com/kidandcat/ccc).
  Đơn giản, đủ.
- Cần nhiều kênh (email, discord): JessyTsui/Claude-Code-Remote.
- Muốn SaaS, không muốn host: Claudegram.
- Muốn chạy đội AI nhiều session, mỗi session một topic, tự lên lịch, tự
  self-heal, điều khiển từ điện thoại: **repo này.**

## Trade-off thành thật

Repo này mạnh ở orchestration, nhưng có mặt trái.

macOS-first. Scheduling dùng `launchd` (native macOS). Linux dùng systemd (chưa
wrap), Windows chưa hỗ trợ. Phần relay core (multi-session, topic, group) vẫn
chạy đa nền tảng, chỉ phần scheduling gắn macOS.

Phụ thuộc ccc. Relay engine là ccc (binary). Repo này không reimplement relay,
nó orchestrate ccc. Đây vừa là điểm yếu (phụ thuộc), vừa là điểm mạnh (kế thừa
một engine ổn định).

Lý tưởng nhất cho máy luôn-on hoặc headless server. Máy hay sleep thì nên để
trên một mini/Mac always-on, hoặc VPS chạy ccc.

Chi tiết kiến trúc: [03-multi-session-architecture.md](./03-multi-session-architecture.md).
