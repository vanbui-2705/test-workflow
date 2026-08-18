# 🧪 test-workflow

[![npm](https://img.shields.io/badge/npm-test--workflow-blue)](https://www.npmjs.com/package/test-workflow)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Node](https://img.shields.io/badge/node-%3E%3D18-brightgreen.svg)](https://nodejs.org)
[![Repo](https://img.shields.io/badge/repo-github-black)](https://github.com/vanbui-2705/test-workflow)

**Một workflow test dùng chung cho mọi dự án** (Python và/hoặc JS/TS).
Tự động nhận diện stack và chạy pipeline fail-fast — `lint → unit → integration → e2e` —
**không cần cấu hình riêng cho từng dự án**. Gọi 1 lệnh qua `npx`, gắn vào pre-commit và CI,
và mọi repo đều có chung một cổng chất lượng.

## ✨ Tại sao

- **Một lệnh test mọi dự án** — không copy-paste CI YAML vào từng repo.
- **Monorepo-aware** — quét đệ quy mọi sub-project Python/JS và test từng cái riêng biệt.
- **Fail-fast** — tier đỏ dừng chạy ngay (exit 1) để anh sửa lỗi đầu tiên, không phải lỗi thứ năm.
- **Local == CI** — cùng lệnh, cùng thứ tự, nên "chạy trên máy tôi" hết là nói dối.
- **Tôn trọng môi trường** — ưu tiên venv của dự án, không có thì `uv run` cô lập, và **không bao giờ sửa code đang test**.

## 🎯 Tính năng

- 🔍 **Auto-detect stack** — Python (`pyproject.toml` / `requirements.txt` / `*.py`),
  JS/TS (`package.json`), hoặc cả hai trong cùng một cây thư mục.
- 🏗️ **Monorepo-aware** — quét đệ quy (loại trừ `node_modules`, `.git`, `.venv`, `.next`, …).
- ⚡ **Pipeline fail-fast** — `lint → unit → integration → e2e`, dừng ngay khi gặp lỗi.
- 🐍 **Python env resolution (mở, theo thư mục dự án):**
  1. venv dự án (`.venv` / `venv` / `env`) → dùng `pytest` của nó
  2. có `uv` → `uv run --python 3.12 pytest` (cô lập, tự cài dep từ `pyproject.toml`)
  3. `pytest` global → dùng luôn
  4. không có → cảnh báo và skip unit một cách graceful
- 🧹 **Output gọn** — `ruff --output-format concise`, mỗi tier chỉ in 40 dòng cuối.
- 🪟 **Cross-platform** — CLI Node chạy trên Windows / macOS / Linux (không cần `make`).

## 📦 Cài đặt

```bash
# Chạy không cần cài (cần network + package trên npm/GitHub)
npx test-workflow

# Hoặc cài global để có lệnh `test-workflow` ở mọi nơi
npm i -g test-workflow

# Hoặc clone source (có sẵn run-tests.sh, pre-commit, GitHub Action)
git clone https://github.com/vanbui-2705/test-workflow ~/test-workflow
```

> Entry point `npx`/`npm` là `bin/test-workflow.js` — CLI Node thuần, cross-platform.

## 🚀 Sử dụng

Đứng trong thư mục dự án:

```bash
cd path/to/your-project

test-workflow fast     # chỉ lint + unit (local / pre-commit)
test-workflow          # full: lint + unit + integration + e2e

# hoặc dùng shell runner đi kèm (không cần npm):
bash ~/test-workflow/run-tests.sh fast
bash ~/test-workflow/run-tests.sh
```

Xem trợ giúp:

```bash
test-workflow --help
```

### Gắn vào dự án (khuyên dùng cho repo lâu dài)

```bash
cd path/to/your-project

# 1) Runner, nằm trong dự án
cp ~/test-workflow/run-tests.sh ./run-tests.sh && chmod +x ./run-tests.sh

# 2) Pre-commit hook — chạy tier nhanh trước mỗi commit
cp ~/test-workflow/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

# 3) CI — chạy full pipeline trên GitHub Actions
mkdir -p .github/workflows
cp ~/test-workflow/github-actions/test.yml .github/workflows/test.yml
```

Sau đó:

```bash
./run-tests.sh fast   # local nhanh
git commit -m "..."   # tier nhanh tự chạy
git push              # GitHub Actions chạy full pipeline
```

## ⚙️ Pipeline hoạt động thế nào

```
lint → unit → integration → e2e
 │      │        │             │
 │      │        │             └ E2E: luồng chính (ít, chậm)
 │      │        └ INTEGRATION: ghép module, mock external
 │      └ UNIT: hàm đơn lẻ, cô lập, mock hết (nhiều, nhanh)
 └ LINT: ruff (py) / eslint (js) — tĩnh, tức thì
```

Tier lỗi → dừng ngay (exit 1) và in `❌`. Các tier sau không chạy.

| Mode   | Tiers                              | Dùng cho             |
|--------|------------------------------------|---------------------|
| `fast` | `lint` + `unit`                    | local / pre-commit  |
| (full) | `lint` + `unit` + `integration` + `e2e` | CI           |

## 🔧 Auto-detect

| Dấu hiệu trong dự án                          | Workflow chạy        |
|------------------------------------------------|----------------------|
| `pyproject.toml` / `requirements.txt` / `*.py` | Python tier          |
| `package.json`                                  | JS/TS tier           |
| cả hai                                          | cả hai stack         |
| không có gì                                      | `⚠ No markers` → skip (exit 0) |

## 📁 Quy ước thư mục test

```
your-project/
├── run-tests.sh
├── .github/workflows/test.yml
├── src/ (hoặc *.py / *.ts)
├── tests/              # UNIT tests (khuyên dùng)
├── tests_integration/  # INTEGRATION (tùy chọn)
└── tests_e2e/          # E2E (tùy chọn)
```

**Python** — `tests/test_example.py`:

```python
def test_add():
    assert 1 + 1 == 2
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

Nếu dự án chưa có test, workflow vẫn chạy lint và báo "no tests found" — không fail.

## 🧰 Yêu cầu môi trường (1 lần)

```bash
# Python tooling
pip install ruff pytest

# JS/TS tooling (theo dự án)
npm install   # cung cấp eslint / vitest / playwright theo package.json
```

`uv` tùy chọn nhưng khuyên dùng — khi có, workflow dùng nó chạy môi trường test cô lập,
đúng dependency thay vì interpreter global.

Trên Windows/MSYS, `make` chưa có sẵn → dùng `run-tests.sh` (không cần make).
Trên Linux/CI, `make` có sẵn và `Makefile` đi kèm chạy cùng lệnh.

## 📜 Nguyên lý thiết kế

```
SYSTEM: You are a Shared Test Workflow runner.
ROLE:   Verify any Python or JS/TS project with one command, zero per-project config.
PIPELINE (fail-fast): lint → unit → integration → e2e
DETECT:  py if pyproject/requirements/*.py; js if package.json; both → run both; none → skip.
RULES:
  1. Never edit source under test — only verify.
  2. Fail-fast: any tier non-zero → exit 1, stop.
  3. Deterministic: callers mock externals (network/time).
  4. Idempotent: re-run = same result.
  5. Local == CI: same commands, same order.
OUTPUT: ✅ per tier, 🎉 on success, ❌ + exit 1 on failure.
```

## 🆘 Troubleshooting

| Hiện tượng                          | Nguyên nhân              | Xử lý                     |
|----------------------------------|--------------------------|---------------------------|
| `⚠ ruff missing`                 | chưa cài ruff            | `pip install ruff`        |
| `⚠ pytest unavailable … skipping`| không có venv/uv/pytest  | `pip install pytest` hoặc cài `uv` |
| `No Python or JS markers`        | đứng sai thư mục         | `cd` vào dự án            |
| exit 1 ở lint                    | sai style/import        | sửa theo gợi ý ruff/eslint|
| CI đỏ, local xanh                | thiếu dep trên CI       | thêm bước cài trong `test.yml` |

## 📄 License

MIT © vanbui-2705 — https://github.com/vanbui-2705/test-workflow
