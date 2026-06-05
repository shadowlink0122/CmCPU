# HDMI出力回復のための always ブロック変換および Verilator リントメタコメント挿入

## 1. 背景と問題点

従来の HDMI 開発では、Cmコンパイラが生成した SystemVerilog（以下 SV）ファイルに対して `postprocess_sv.sh` を介して以下の置換を行っていました。
- `always_ff @` → `always @`
- `always_comb begin` → `always @(*) begin`

これらの置換は、Gowin EDA（特に論理合成エンジン）が `always_ff` や `always_comb` ブロック内部の代入文の混在（ブロッキング代入と非ブロッキング代入など）に対して誤った最適化やエラーを起こすことを防ぎ、実機（FPGA）で HDMI 出力を正常に動作させるために不可欠でした。

ポスト処理スクリプトを排除した現状の構成では、Cmコンパイラが raw の `always_ff` や `always_comb` を出力しているため、Gowin EDA で合成したビットストリームが意図通りに動作せず、画面が映らない（HDMI出力が行われない）状態になっていました。

また、Verilator リント警告（`UNUSED`, `WIDTHTRUNC` 等）を抑止するためのメタコメント挿入処理も消失していたため、リントクリーンなコンパイル状態を維持するためにコンパイラ側での自動挿入が必要となっています。

## 2. 解決策と設計

Cm コンパイラの SystemVerilog コード生成バックエンド（`codegen.cpp`）を修正し、外部のポスト処理スクリプトに依存せずに、生成時に自動で Gowin 互換の記述に置換して出力するようにします。

### 2.1 always ブロックの出力置換
`SVCodeGen::emitModule` において、収集された各ブロックを SV ファイルへ出力する際、以下の部分文字列置換を適用します。

| 置換前キーワード | 置換後キーワード | 理由 |
| :--- | :--- | :--- |
| `always_ff @` | `always @` | Gowin EDA のレジスタ合成バグ回避 |
| `always_comb begin` | `always @(*) begin` | Gowin EDA の組み合わせ回路合成クラッシュ回避 |
| `always_latch begin` | `always @(*) begin` | 同上 |

### 2.2 Verilator リント無効化メタコメントの自動挿入
SVモジュール宣言の直後に、自動生成コードで発生しがちな警告を無視するための以下のコメントを挿入します。

```systemverilog
/* verilator lint_off UNUSED */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off UNDRIVEN */
```

## 3. 実装方針

- `Cm/src/codegen/sv/codegen.cpp` の無名名前空間に文字列一括置換ユーティリティ `replace_all` を追加します。
- `SVCodeGen::emitModule` の各ブロック（`always_ff_blocks`, `always_comb_blocks`, `always_latch_blocks`）の出力ループで `replace_all` を実行します。
- 同 `emitModule` でポートリスト（`emitPortList`）の出力直後にメタコメントを出力します。
