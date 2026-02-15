<p align="center">
  <img src=".github/assets/logo.png" width="128" height="128" alt="TablePro">
</p>

<h1 align="center">TablePro</h1>

<p align="center">
  Ứng dụng quản lý cơ sở dữ liệu native cho macOS — được xây dựng bằng SwiftUI và AppKit.
</p>

<p align="center">
  <a href="https://docs.tablepro.app">Tài liệu</a> ·
  <a href="https://github.com/datlechin/tablepro/releases">Tải xuống</a> ·
  <a href="https://github.com/datlechin/tablepro/issues">Báo lỗi</a>
</p>

---

<p align="center">
  <img src=".github/assets/hero-dark.png" alt="TablePro Screenshot" width="800">
</p>

## Giới thiệu

TablePro là một giải pháp thay thế nhẹ cho TablePlus, được xây dựng hoàn toàn bằng các framework native của Apple. Không Electron, không web view — chỉ SwiftUI + AppKit thuần tuý cho trải nghiệm macOS native thực sự.

## Cơ sở dữ liệu hỗ trợ

- **MySQL / MariaDB** — qua MariaDB Connector/C
- **PostgreSQL** — qua libpq
- **SQLite** — thư viện có sẵn trên macOS

## Tính năng

- **Trình soạn SQL** — tô sáng cú pháp, tự động hoàn thành, thực thi nhiều truy vấn, chỉnh sửa theo tab
- **Lưới dữ liệu** — lưới hiệu năng cao với chỉnh sửa trực tiếp, sắp xếp, phân trang và sao chép dưới dạng CSV/JSON
- **Theo dõi thay đổi** — hoàn tác/làm lại, so sánh trực quan, commit hàng loạt với truy vấn tham số hoá
- **Cấu trúc bảng** — trình chỉnh sửa cột/chỉ mục/khoá ngoại trực quan với xem trước schema
- **Bộ lọc** — trình tạo bộ lọc trực quan (AND/OR), tìm kiếm nhanh, lưu preset
- **Nhập & Xuất** — CSV, JSON, SQL với theo dõi tiến trình và hỗ trợ gzip
- **SSH Tunneling** — xác thực bằng mật khẩu và khoá, đọc `~/.ssh/config`
- **Khác** — lịch sử truy vấn, gắn thẻ kết nối, lưu trữ Keychain, tuỳ chỉnh giao diện, universal binary

## Yêu cầu

- macOS 14.0 (Sonoma) trở lên

## Biên dịch từ mã nguồn

```bash
# Cài đặt dependencies
brew install libpq mariadb-connector-c

# Build debug
xcodebuild -project TablePro.xcodeproj -scheme TablePro -configuration Debug build

# Build release (Universal)
scripts/build-release.sh both

# Tạo DMG
scripts/create-dmg.sh
```

## Tài liệu

Tài liệu đầy đủ tại [docs.tablepro.app](https://docs.tablepro.app).

## Giấy phép

Dự án này được cấp phép theo [GNU General Public License v3.0](LICENSE).
