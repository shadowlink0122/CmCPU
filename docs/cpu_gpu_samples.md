# CPU/GPUサンプル回路の設計

## 概要

Cm言語のSVバックエンドで「計算する回路」を書くサンプルとして、アキュムレータ型CPU（`src/cpu/simple_cpu.cm`）と矩形フィルGPU（`src/gpu/simple_gpu.cm`）を追加した。どちらも `#[test]` によるシミュレーションテスト付きで、`make test` の自動発見対象。

## SimpleCPU（src/cpu/）

8レジスタ・16bit命令のロード/ストア型CPU。C言語風の簡単なプログラミング言語のコンパイル対象にできる基本命令セット（算術論理・ロード/ストア・pc相対分岐・JAL/JRによる関数呼び出し・MMIO出力）を持つ。
命令セットと呼び出し規約の詳細は [SimpleCPU ISA](cpu_isa.md) を参照。

デモプログラム（`program/demo_program.cm`）は「1..10の総和を関数 `twice()` で2倍してMMIOへ出力する」C風コードを手動コンパイルしたもので、実行結果110を `result_out` で検証する。

### 構成（基本回路のファイル分割）

| ファイル | 内容 |
|---|---|
| `core/adder.cm` | 全加算器と32bitリップルキャリー加算器 |
| `core/alu.cm` | ALU（加減算は全加算器ベース、減算は2の補数） |
| `core/decoder.cm` | 命令デコーダとオペコード定義 |
| `core/register_file.cm` | レジスタファイル（r0固定0） |
| `core/core.cm` | フェッチ・デコード・実行コア |
| `memory/ram.cm` | データRAM（256ワード）とMMIO出力（0xFF） |
| `program/demo_program.cm` | デモプログラム（手書きアセンブリ） |
| `simple_cpu.cm` | トップモジュールと統合テスト |
| `core/alu_test.cm` | 基本回路の検証ラッパー |

### 実装の要点

- 算術演算は全加算器（`full_adder`）を32段連結したリップルキャリー加算器で構成し、減算は2の補数（`a + ~b + 1`）で行う
- posedge関数内はNBA意味論のため、`pc = next_pc` を先に書き、分岐・ジャンプ命令が後から上書きする（後の代入が勝つ）
- レジスタ書き込みは全てコアの実行プロセスが行い、r0への書き込みは `if (rd != 0)` で抑止、読み出しは `rf_read()` で固定0を保証する
- exportする配列（`prog_rom`）の初期化子は1行で書く必要がある（プリプロセッサのexport再宣言が複数行初期化子に未対応。Cm側の既知の問題として報告済み）

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
