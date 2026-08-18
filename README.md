# 🧪 Hermes Shared Test Workflow — Hướng dẫn chi tiết (TOÀN TẬP)

Bộ khung test **dùng chung cho MỌI dự án** (Python & JS/TS).
Thiết kế theo 10 nguyên lý: nhiều unit cô lập, ít E2E, fail-fast,
chạy giống nhau ở local lẫn CI.

---

## 📁 1. Mọi thứ để ở đâu?

### Bộ khung workflow (CHỈ 1 bản duy nhất — không copy vào từng dự án)
```
~/test-workflow/
├── run-tests.sh          ← entry point chính (dùng mọi lúc)
├── Makefile              ← tiện ích cho máy có `make` (Linux/CI)
├── pre-commit            ← hook local (lint+unit nhanh)
├── github-actions/
│   └── test.yml          ← CI tự động (GitHub Actions)
└── README.md             ← file này
```

### Dự án của bạn để ở đâu?
Để dự án vào **1 trong các thư mục gốc** (đã có sẵn trên máy anh):
```
~/source/repos/<tên-dự-án>/     ← khuyên dùng (đã có ~/source/repos)
~/.openclaw/workspace/<tên>/     ← workspace OpenClaw (đã có sẵn)
~/dev/<tên>/                     ← tuỳ chọn
```
> Quy tắc: mỗi dự án = 1 thư mục riêng, có file marker để workflow nhận diện:
> - Python → có `pyproject.toml` HOẶC `requirements.txt` HOẶC ít nhất 1 file `*.py`
> - JS/TS  → có `package.json`

Ví dụ:
```
~/source/repos/my-bot/         (Python)
~/source/repos/web-app/        (JS/TS)
~/.openclaw/workspace/rss/      (Python+JS mixed)
```

---

## 🌐 0. Cài đặt workflow (chỉ 1 lần)

Workflow được publish lên npm — user chỉ cần 1 lệnh là xài được trên mọi dự án:

```bash
npx test-workflow                 # chạy full pipeline (không cần cài)
# hoặc cài global để dùng lệnh `test-workflow` ở mọi nơi:
npm i -g test-workflow
test-workflow fast                # sau khi cài global
```

Hoặc clone repo về máy (để có cả `run-tests.sh`, `pre-commit`, CI):
```bash
git clone https://github.com/vanbui-2705/test-workflow ~/test-workflow
```

> `npx test-workflow` = CLI Node cross-platform (bin/test-workflow.js) — chạy được
> trên Windows/macOS/Linux miễn có Node. Không cần `make`.

## 🚀 2. Vào mỗi dự án, tôi phải làm gì?

Có 3 cấp độ — từ nhẹ đến đầy đủ. Anh chọn tùy nhu cầu.

### Cấp độ A — CHỈ CHẠY TEST (nhanh nhất, không cài gì)
Đứng ở thư mục dự án, gọi workflow từ xa bằng `npx`:
```bash
cd ~/source/repos/my-bot
npx test-workflow fast      # lint + unit
npx test-workflow           # full: lint+unit+integ+e2e
```
Hoặc nếu đã clone repo local:
```bash
bash ~/test-workflow/run-tests.sh fast
bash ~/test-workflow/run-tests.sh
```
Không cần copy file vào dự án. Đứng ở thư mục dự án, gọi workflow từ xa:

```bash
cd ~/source/repos/my-bot
bash ~/test-workflow/run-tests.sh fast      # lint + unit
bash ~/test-workflow/run-tests.sh           # full: lint+unit+integ+e2e
```

✅ Xong. Workflow auto-detect Py/JS, chạy đúng tier. Không sửa project.

---

### Cấp độ B — GẮN VÀO DỰ ÁN (khuyên dùng cho dự án lâu dài)
Copy 3 file vào dự án để nó "có test riêng":

```bash
cd ~/source/repos/my-bot

# 1) Runner (đứng tên dự án)
cp ~/test-workflow/run-tests.sh ./run-tests.sh
chmod +x ./run-tests.sh

# 2) Pre-commit hook (chạy nhanh mỗi lần git commit)
mkdir -p .git/hooks
cp ~/test-workflow/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 3) CI (tự chạy trên GitHub khi push/PR)
mkdir -p .github/workflows
cp ~/test-workflow/github-actions/test.yml .github/workflows/test.yml
```

Sau đó trong dự án anh có thể chạy ngắn gọn:
```bash
./run-tests.sh fast     # local nhanh
./run-tests.sh          # local full
git commit -m "..."     # tự động chạy lint+unit trước khi commit
git push                # GitHub Actions tự chạy toàn bộ pipeline
```

---

### Cấp độ C — DỰ ÁN CÓ TEST THỰC TẾ (để pipeline có gì chạy)
Workflow cần thư mục test theo quy ước:
```
my-bot/
├── run-tests.sh
├── .github/workflows/test.yml
├── src/ hoặc *.py / *.ts
├── tests/              ← UNIT tests (bắt buộc để có ý nghĩa)
├── tests_integration/  ← INTEGRATION (tùy chọn)
└── tests_e2e/          ← E2E (tùy chọn)
```

**Python** — ví dụ `tests/test_rss.py`:
```python
import iran_rss_monitor as m

def test_is_iran_war():
    assert m.is_iran_war({"title":"Iran không kích","description":"tên lửa"}) is True
```

**JS/TS** — thêm script vào `package.json`:
```json
{
  "scripts": {
    "lint": "eslint .",
    "test:unit": "vitest run",
    "test:integ": "vitest run --mode integration",
    "test:e2e": "playwright test"
  }
}
```

> Nếu chưa có test nào, workflow vẫn chạy (lint + "⚠ no tests found") — không lỗi.

---

## 🔁 3. Pipeline chạy như thế nào (fail-fast)

```
lint → unit → integration → e2e
 ^       ^        ^             ^
 |       |        |             └ E2E: luồng chính (ít, chậm)
 |       |        └ INTEGRATION: ghép module, mock external (Telegram/RSS)
 |       └ UNIT: hàm đơn lẻ, cô lập, mock hết (nhiều, nhanh)
 └ LINT: ruff (py) / eslint (js) — tĩnh, tức thì
```
**Lớp nào lỗi → dừng ngay, exit 1, in ❌.** Không chạy lớp sau.

- `fast` = chỉ chạy `lint + unit` (dành cho local / pre-commit)
- `full` = chạy cả 4 lớp (dành cho CI)

---

## 🧩 4. Auto-detect stack (không cần config)

| Dấu hiệu trong dự án | Workflow chạy |
|----------------------|---------------|
| `pyproject.toml` / `requirements.txt` / `*.py` | Python tier |
| `package.json` | JS/TS tier |
| Cả 2 | Chạy cả 2 stacks |
| Không có gì | "⚠ No markers" → skip, exit 0 |

---

## 🔧 5. Yêu cầu môi trường (1 lần duy nhất)

Chỉ cần cài 1 lần trên máy (CI đã có sẵn):
```bash
# Python
pip install ruff pytest pytest-cov pytest-mock freezegun

# JS/TS
npm install   # + eslint, vitest, playwright theo dự án
```
Windows/MSYS: `make` chưa có sẵn → dùng `run-tests.sh` (không cần make).
Trên Linux/CI: `make` có sẵn → có thể dùng `make -f ~/test-workflow/Makefile test-fast`.

---

## 📋 6. Cheat-sheet lệnh

| Muốn làm | Lệnh |
|----------|------|
| Test nhanh 1 dự án (đứng trong dự án) | `bash ~/test-workflow/run-tests.sh fast` |
| Test đầy đủ 1 dự án | `bash ~/test-workflow/run-tests.sh` |
| Gắn hook vào dự án | copy `run-tests.sh` + `pre-commit` + `test.yml` (mục 2) |
| Xem bot/lint báo lỗi gì | chạy `fast`, đọc output ruff/eslint |
| CI tự chạy | `git push` (đã copy `test.yml`) |

---

## ✅ 7. Triết lý (system prompt của workflow)

```
SYSTEM: You are a Shared Test Workflow runner.
ROLE: Verify any Python or JS/TS project with one command, zero per-project config.
PIPELINE (fail-fast): lint → unit → integration → e2e
DETECT: py if pyproject/requirements/*.py; js if package.json; both = run both; none = skip.
RULES:
  1. Never edit source under test — only verify.
  2. Fail-fast: any tier non-zero → exit 1, stop.
  3. Deterministic: caller mocks externals (network/time).
  4. Idempotent: re-run = same result.
  5. Local == CI: same commands, same order.
OUTPUT: ✅ per tier, 🎉 on success, ❌ + exit 1 on failure.
```

---

## 🆘 8. Troubleshooting

| Hiện tượng | Nguyên nhân | Xử lý |
|-----------|------------|-------|
| "⚠ ruff missing" | chưa cài ruff | `pip install ruff` |
| "⚠ no pytest tests found" | chưa viết test | tạo `tests/` (mục 2C) |
| "No Python or JS markers" | đứng sai thư mục | `cd` vào đúng dự án |
| Exit 1 ở lint | code sai style/import | sửa theo gợi ý ruff/eslint |
| CI đỏ mà local xanh | thiếu dep trên CI | thêm vào `test.yml` setup bước cài |

---

📌 **Tóm lại:** Dự án để trong `~/source/repos/` (hoặc `workspace`).
Vào dự án → `bash ~/test-workflow/run-tests.sh fast`.
Muốn tự động → copy 3 file (mục 2B). Xong.
