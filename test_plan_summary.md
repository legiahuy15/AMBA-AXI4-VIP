# AXI4 VIP — Demo Test Plan cho Waveform & Report

## Tổng quan

5 cặp **Sequence + Test** mới, mỗi cái chỉ **3–8 transaction**, thiết kế để **chụp waveform gọn** và **viết report** minh họa từng feature AXI4.

---

## Tổng hợp Test Cases

| # | Test Name | Seq Name | Txns | Mục đích chính | Điểm hay trên waveform |
|---|-----------|----------|------|----------------|----------------------|
| 1 | `axi4_wr_order_demo_test` | `axi4_wr_order_demo_seq` | **3** | So sánh 3 chế độ AW↔W ordering | AWVALID vs WVALID timing khác nhau rõ rệt |
| 2 | `axi4_narrow_burst_test` | `axi4_narrow_burst_seq` | **4** | Narrow transfer (SIZE < bus width) | WSTRB chỉ active 1-2 byte lane mỗi beat |
| 3 | `axi4_error_response_test` | `axi4_error_response_seq` | **6** | OKAY + SLVERR + DECERR responses | BRESP/RRESP thay đổi theo address region |
| 4 | `axi4_all_burst_type_test` | `axi4_all_burst_type_seq` | **6** | So sánh FIXED vs INCR vs WRAP | Address pattern khác nhau rõ rệt |
| 5 | `axi4_back_to_back_test` | `axi4_back_to_back_seq` | **8** | Pipeline throughput, no-gap | xVALID/xREADY chain liên tục |

---

## Chi tiết từng Test

### 1. Write Channel Ordering Demo (`axi4_wr_order_demo_test`)

> [!TIP]
> Test lý tưởng để minh họa AXI4 cho phép W data trước AW address.

**Transactions:**
| TX | Mode | Addr | LEN | Điểm quan sát waveform |
|----|------|------|-----|----------------------|
| 1 | `PARALLEL` | 0x1000 | 3 (4 beat) | AWVALID ↑ cùng lúc WVALID ↑ |
| 2 | `AW_BEFORE_W` | 0x2000 | 3 (4 beat) | AWREADY HS xong → mới có WVALID ↑ |
| 3 | `W_BEFORE_AW` | 0x3000 | 3 (4 beat) | WVALID ↑ trước AWVALID ↑ |

**File source:**
- [axi4_wr_order_demo_seq.sv](file:///d:/Code/axi4_vip/src/seq/axi4_wr_order_demo_seq.sv)
- [axi4_wr_order_demo_test.sv](file:///d:/Code/axi4_vip/src/test/axi4_wr_order_demo_test.sv)

---

### 2. Narrow Burst Demo (`axi4_narrow_burst_test`)

> [!TIP]
> Minh họa cách byte lane hoạt động khi transfer size nhỏ hơn bus width.

**Transactions:**
| TX | Dir | SIZE | Addr | Điểm quan sát |
|----|-----|------|------|--------------|
| 1 | WRITE | 1B | 0x4000 | WSTRB chỉ 1 bit active, xoay qua 4 lane |
| 2 | READ | 1B | 0x4000 | RDATA chỉ valid 1 byte/beat |
| 3 | WRITE | 2B | 0x5000 | WSTRB alternating 0011/1100 |
| 4 | READ | 2B | 0x5000 | Half-word access |

**File source:**
- [axi4_narrow_burst_seq.sv](file:///d:/Code/axi4_vip/src/seq/axi4_narrow_burst_seq.sv)
- [axi4_narrow_burst_test.sv](file:///d:/Code/axi4_vip/src/test/axi4_narrow_burst_test.sv)

---

### 3. Error Response Demo (`axi4_error_response_test`)

> [!IMPORTANT]
> Minh họa 3 loại AXI4 response: OKAY (00), SLVERR (10), DECERR (11).

**Address Map:**
```
[0x0000_0000 : 0xDFFF_FFFF]  →  OKAY   (2'b00)
[0xE000_0000 : 0xEFFF_FFFF]  →  SLVERR (2'b10)
[0xF000_0000 : 0xFFFF_FFFF]  →  DECERR (2'b11)
```

**Transactions:**
| TX | Dir | Addr | Expected RESP |
|----|-----|------|--------------|
| 1 | WRITE | 0x0000_0100 | OKAY |
| 2 | READ | 0x0000_0100 | OKAY |
| 3 | WRITE | 0xE000_0000 | SLVERR |
| 4 | READ | 0xE000_0000 | SLVERR |
| 5 | WRITE | 0xF000_0000 | DECERR |
| 6 | READ | 0xF000_0000 | DECERR |

**File source:**
- [axi4_error_response_seq.sv](file:///d:/Code/axi4_vip/src/seq/axi4_error_response_seq.sv)
- [axi4_error_response_test.sv](file:///d:/Code/axi4_vip/src/test/axi4_error_response_test.sv)

---

### 4. All Burst Types Demo (`axi4_all_burst_type_test`)

> [!TIP]
> Cùng LEN=3 (4 beat), cùng SIZE=4B — so sánh address pattern cực kỳ rõ.

**Transactions:**
| TX | Burst | Dir | Start Addr | Address pattern |
|----|-------|-----|------------|-----------------|
| 1 | FIXED | WR | 0x6000 | 0x6000 → 0x6000 → 0x6000 → 0x6000 |
| 2 | FIXED | RD | 0x6000 | Tương tự |
| 3 | INCR | WR | 0x7000 | 0x7000 → 0x7004 → 0x7008 → 0x700C |
| 4 | INCR | RD | 0x7000 | Tương tự |
| 5 | WRAP | WR | 0x8004 | 0x8004 → 0x8008 → 0x800C → 0x8000 (wrap!) |
| 6 | WRAP | RD | 0x8004 | Tương tự |

**File source:**
- [axi4_all_burst_type_seq.sv](file:///d:/Code/axi4_vip/src/seq/axi4_all_burst_type_seq.sv)
- [axi4_all_burst_type_test.sv](file:///d:/Code/axi4_vip/src/test/axi4_all_burst_type_test.sv)

---

### 5. Back-to-Back Pipeline Demo (`axi4_back_to_back_test`)

> [!TIP]
> Trên waveform: AWVALID → AWREADY chain liên tục không có idle cycle.

**Transactions:**
| Phase | TX | Dir | ID | Addr | LEN |
|-------|----|-----|----|------|-----|
| Write | 0 | WR | 0 | 0xA000 | 1 (2 beat) |
| Write | 1 | WR | 1 | 0xA100 | 1 |
| Write | 2 | WR | 2 | 0xA200 | 1 |
| Write | 3 | WR | 3 | 0xA300 | 1 |
| Read | 0 | RD | 0 | 0xA000 | 1 |
| Read | 1 | RD | 1 | 0xA100 | 1 |
| Read | 2 | RD | 2 | 0xA200 | 1 |
| Read | 3 | RD | 3 | 0xA300 | 1 |

**File source:**
- [axi4_back_to_back_seq.sv](file:///d:/Code/axi4_vip/src/seq/axi4_back_to_back_seq.sv)
- [axi4_back_to_back_test.sv](file:///d:/Code/axi4_vip/src/test/axi4_back_to_back_test.sv)

---

## Cách chạy

```bash
# Chạy từng test riêng lẻ (CLI mode)
make run TESTNAME=axi4_wr_order_demo_test
make run TESTNAME=axi4_narrow_burst_test
make run TESTNAME=axi4_error_response_test
make run TESTNAME=axi4_all_burst_type_test
make run TESTNAME=axi4_back_to_back_test

# Chạy với GUI + waveform
make gui TESTNAME=axi4_wr_order_demo_test

# Chạy regression toàn bộ (bao gồm cả test cũ + mới)
make regress
```

---

## Files đã thay đổi

| File | Thay đổi |
|------|---------|
| [axi4_pkg.sv](file:///d:/Code/axi4_vip/src/axi4_pkg.sv) | Thêm 5 `include` sequence mới |
| [axi4_test_pkg.sv](file:///d:/Code/axi4_vip/src/axi4_test_pkg.sv) | Thêm 5 `include` test mới |
| [Makefile](file:///d:/Code/axi4_vip/sim/Makefile) | Thêm 5 test vào `TEST_LIST` |

