# Telegram Relay là gì?

> Dành cho người mới. Đã rõ rồi thì có thể nhảy sang [02-comparison.md](./02-comparison.md).

## Bài toán

Claude Code là một CLI chạy trên máy bạn, trong một terminal. Để dùng, bạn ngồi
trước máy, gõ lệnh, đọc kết quả ngay trên màn hình đó.

Vấn đề nằm ở chỗ đời thực không diễn ra trước máy:

- Bạn đang ở quán cà phê, chỉ có điện thoại. Muốn nhờ Claude sửa một con bug,
  chạy lại build, tóm tắt log, nhưng máy để ở nhà hoặc ngoài server.
- Có mười việc cần chạy song song: nghiên cứu mười đối thủ, theo dõi mười CI,
  viết mười bài. Mỗi việc cần một Claude riêng. Không ai mở mười terminal rồi
  canh từng cái.
- Bạn muốn Claude **tự chạy mỗi sáng tám giờ** để tổng hợp báo cáo, không cần mở
  máy lên.
- Một việc chạy ba mươi phút. Bạn không muốn ngồi chờ, mà muốn nó báo qua điện
  thoại khi xong, rồi trả lời tiếp ngay trên điện thoại.

## Giải pháp: Telegram Relay

Một relay (tram trung chuyen) đứng giữa Claude Code và Telegram:

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

Relay làm hai việc.

Một, hướng vào: bạn gõ tin trong Telegram, relay đọc, đẩy vào Claude đang chạy.
Hai, hướng ra: Claude trả lời, relay bắt lấy, gửi về Telegram. Bạn đọc trên điện
thoại.

Hai chiều chạy thời gian thực. Bạn và Claude trò chuyện qua Telegram như chat
với một người, chỉ là "người" đó là một Claude Code đang chạy trên máy bạn, có
thể đọc và sửa file, chạy lệnh, deploy.

## "Multi" thay đổi mọi thứ

Relay đơn giản chỉ nối một Claude với một chat. Repo này thêm ba chiều.

### Multi-session
Nhiều Claude Code chạy song song, mỗi cái là một "nhân viên" riêng, project
riêng, ngữ cảnh riêng, lịch sử riêng.

### Multi-topic
Telegram Group có tính năng Forum Topics (như Slack channels). Mỗi Claude session
bằng một topic. Mở group ra, bạn thấy:

```
📂 Work Group (forum)
├── 🔵 ai_native_company      ← Claude đang chạy project này
├── 🔵 competitor-research-a
├── 🔵 competitor-research-b
├── 🟡 daily-report            ← idle
└── 🔴 dead-session
```

Click vào topic nào là đang nói chuyện với Claude session đó. Tách bạch, rõ ràng,
không lẫn.

### Multi-user / multi-group
**Một bot token phục vụ nhiều group khác nhau.** Mỗi group có thể là một đội,
một khách hàng, một dự án. Session nào thuộc group nào thì reply về group đó. Ví
dụ: group Công ty A cho các session làm việc cho khách A, group Gia đình cho
session quản lý tài chính gia đình, group Cá nhân cho session nghiên cứu. Cùng
một bot, nhưng routing tách, mỗi "người dùng" thấy group của mình.

### Bidirectional nghĩa là gì
Không phải kiểu "gửi lệnh rồi chờ email". Mà là hội thoại thời gian thực:

- Bạn: "check log app.log 20 dòng cuối"
- Claude: (gửi về 20 dòng, đóng khung `<pre>`)
- Bạn: "dòng 15 có lỗi auth, fix token đi"
- Claude: "đã fix, restart service, xong ✓"

Mỗi reply là một message Telegram. Reply, forward, pin, search lại lúc nào cũng
được. Toàn bộ tương tác với đội AI của bạn nằm gọn trong Telegram, ứng dụng bạn
đã có trên điện thoại.

## Vì sao lại là Telegram

Có sẵn trên mọi nền tảng: điện thoại, desktop, web. Bot API mạnh và miễn phí:
tạo topic, gửi file, inline button, streaming. Forum Topics cho tách session tự
nhiên. HTML mode để format đẹp (code block, bold, bullet). Không rate-limit khắt
khe như SMS hay email.
