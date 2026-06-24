# Telegram Relay là gì?

> Dành cho người mới. Nếu đã rõ, có thể nhảy sang [02-comparison.md](./02-comparison.md).

## Bài toán

Claude Code là một **CLI chạy trên máy bạn** — một terminal. Để dùng, bạn phải
ngồi trước máy đó, gõ lệnh, đọc kết quả trên terminal.

Vấn đề thực tế:

- Bạn đang ở ngoài quán cà phê, chỉ có điện thoại. Bạn muốn nhờ Claude sửa một
  con bug, chạy lại build, tóm tắt log — nhưng máy để ở nhà/ngoài server.
- Bạn có **10 task** cần chạy song song (nghiên cứu 10 đối thủ, theo dõi 10 CI,
  viết 10 bài). Mỗi task cần một Claude riêng. Bạn không thể mở 10 terminal và
  canh từng cái.
- Bạn muốn Claude **tự chạy mỗi sáng 8h** để tổng hợp báo cáo, không cần bạn mở
  máy lên.
- Một task chạy 30 phút. Bạn không muốn canh. Bạn muốn nó **báo qua điện thoại khi
  xong**, và bạn có thể **trả lời tiếp ngay trên điện thoại**.

## Giải pháp: Telegram Relay

Một **relay** (trạm trung chuyển) đứng giữa **Claude Code** và **Telegram**:

```
        bạn (điện thoại)
              ▲
              │ Telegram message
              ▼
        ┌───────────┐   bot token   ┌──────────────┐
        │  Telegram  │ ◄──────────► │   RELAY       │
        │   (cloud)  │              │ (trên máy bạn)│
        └───────────┘              └──────┬───────┘
                                           │ tmux / stdin
                                           ▼
                                     ┌───────────┐
                                     │ Claude Code│
                                     └───────────┘
```

Relay làm 2 việc:

1. **Inbound (bạn → Claude):** Bạn gõ tin nhắn trong Telegram → relay đọc →
   chuyển vào Claude đang chạy.
2. **Outbound (Claude → bạn):** Claude trả lời → relay bắt lấy → gửi về
   Telegram. Bạn đọc trên điện thoại.

=> **Hai chiều (bidirectional).** Bạn và Claude trò chuyện qua Telegram như chat
với một người — nhưng người đó là một Claude Code đang chạy trên máy bạn, có thể
đọc/sửa file, chạy lệnh, deploy.

## "Multi" thay đổi mọi thứ

Một relay đơn giản chỉ nối **1 Claude** với **1 chat**. Repo này thêm ba chiều:

### Multi-session
Nhiều Claude Code chạy song song, mỗi cái là một "nhân viên" riêng — project
riêng, context riêng, lịch sử riêng.

### Multi-topic
Telegram Group có tính năng **Forum Topics** (như Slack channels). Mỗi Claude
session = một topic. Bạn mở group, thấy danh sách:

```
📂 Work Group (forum)
├── 🔵 ai_native_company      ← Claude đang chạy project này
├── 🔵 competitor-research-a
├── 🔵 competitor-research-b
├── 🟡 daily-report            ← idle
└── 🔴 dead-session
```

Bạn click vào topic nào = đang nói chuyện với Claude session đó. Tách bạch, rõ
ràng, không lẫn lộn.

### Multi-user / multi-group
**1 bot token phục vụ nhiều group khác nhau.** Mỗi group có thể là một đội/
khách hàng/ dự án khác nhau. Session nào thuộc group nào thì reply về group đó.
Ví dụ:

- Group **Công ty A** → các session làm việc cho khách A
- Group **Gia đình** → session quản lý tài chính gia đình
- Group **Cá nhân** → session nghiên cứu cá nhân

Tất cả dùng chung 1 bot, nhưng routing tách biệt → mỗi "người dùng" thấy group
của mình.

### Bidirectional thực sự nghĩa là gì
Không phải "gửi lệnh rồi chờ email". Nghĩa là **conversation thời gian thực**:

- Bạn: *"check log app.log 20 dòng cuối"*
- Claude: *(gửi về 20 dòng, đóng khung `<pre>`)*
- Bạn: *"dòng 15 có lỗi auth, fix token đi"*
- Claude: *"đã fix, restart service, xong ✓"*

Mỗi reply là một message Telegram. Bạn có thể reply, forward, pin, search lại
bất cứ lúc nào. Toàn bộ tương tác với "đội AI" của bạn nằm trong Telegram — một
ứng dụng bạn đã có trên điện thoại.

## Tại sao lại là Telegram?

- **Có sẵn** trên mọi điện thoại, desktop, web.
- **Bot API mạnh + miễn phí**: tạo topic, gửi file, inline button, streaming.
- **Forum Topics** = channel tách bạch → natural cho multi-session.
- **HTML mode** → format đẹp (code block, bold, bullet).
- **Không giới hạn** như SMS/email, không rate limit khắt khe.
