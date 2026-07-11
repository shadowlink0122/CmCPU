# CPU/GPUサンプル回路の設計

## 概要

Cm言語のSVバックエンドで「計算する回路」を書くサンプルとして、アキュムレータ型CPU（`src/cpu/simple_cpu.cm`）と矩形フィルGPU（`src/gpu/simple_gpu.cm`）を追加した。どちらも `#[test]` によるシミュレーションテスト付きで、`make test` の自動発見対象。

## SimpleCPU（src/cpu/simple_cpu.cm）

16bit命令・1命令/サイクルのアキュムレータ型CPU。プログラムROM（`uint[8]` 配列、合成時はROM推論）上の総和プログラム（10+9+...+1 = 55）を実行し、結果を `result_out` に出力して停止する。

### 命令セット

| opcode | ニーモニック | 動作 |
|---|---|---|
| 0x0 | NOP | 何もしない |
| 0x1 | LDI imm | acc = imm |
| 0x2 | ADD imm | acc += imm |
| 0x3 | SUB imm | acc -= imm |
| 0x4 | LDC imm | cnt = imm |
| 0x5 | DEC | cnt -= 1 |
| 0x6 | ADDC | acc += cnt |
| 0x7 | BNZ imm | cnt != 0 なら pc = imm |
| 0x8 | OUT | result_out = acc下位8bit |
| 0xF | HALT | 停止（halt_led点灯） |

### 実装の要点

- デコードは `match (op)` で記述（v0.16.0のmatch→casez変換のデモ）
- posedge関数内はNBA意味論のため、`pc = pc + 1` を先に書き、分岐命令が後から `pc = imm` で上書きする（後の代入が勝つ）
- ローカル変数（`instr`/`op`/`imm`）は即時代入なので同サイクル内で使える

## SimpleGPU（src/gpu/simple_gpu.cm）

16×8ピクセル・8色（3bit）のフレームバッファを持つ矩形フィルラスタライザ。`start` で「全クリア→指定矩形をフィル」を実行し、1ピクセル/サイクルで描画して `done` を立てる。

### インタフェース

| ポート | 方向 | 説明 |
|---|---|---|
| start | in | 描画開始（doneはstickyで、次のstartまで保持） |
| rect_x/y/w/h/color | in | 矩形パラメータ（start時にラッチ） |
| busy / done | out | 実行中 / 完了 |
| rd_addr → rd_data | in/out | フレームバッファ同期読み出し（1サイクル遅延） |

### FSM

IDLE →（start）→ CLEAR（128px消去）→ FILL（w×h走査）→ DONE →（!start）→ IDLE

フレームバッファは `utiny[128]` で、書き込み（描画FSM）と読み出し（read_port）を別のposedge関数に分けており、合成ではデュアルポートRAMに推論される。

## ビルド・テスト

```bash
make cpu-build   # SV生成 + Verilatorリント
make gpu-build
make test        # 全回路テスト（cpu/gpuも自動発見される）
```

## 開発時に踏んだコンパイラの問題（Cm側に報告済み）

以下は `Cm/docs/design/v0.16.0/08_sv_codegen_audit.md` に詳細を記載。

1. 変数名 `program` がSV予約語と衝突し、生成SVがiverilogで構文エラーになる → `prog_rom` に改名して回避
2. `async void f(posedge clk)` ＋ 内部クロック（OSC駆動）の組み合わせで`input clk, rst` が自動注入され重複宣言になる → 非asyncの`void f(posedge clk)`（blinkと同じパターン）で回避
3. `#[test]` から内部レジスタ（`halted`）を参照するとiverilogの束縛エラーになる → 出力ポート（`halt_led`）経由の検証に変更
