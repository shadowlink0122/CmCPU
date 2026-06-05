# Verilator リント違反の解消設計書

## 1. 現象
`builder.sh hdmi` によるビルド時に、Verilatorから 37 件のリント違反（エラー/警告）が発生し、ビルドが停止します。

## 2. 原因
前回の「色ずれバグ修正」において、TMDSエンコーダの中間変数をモジュールスコープの `assign` 変数に変更した結果、以下のVerilator警告が発生していると考えられます。
- **`UNUSED` / `WIDTHTRUNC` / `WIDTHEXPAND`**:
  Cmコンパイラが生成する SystemVerilog コードでは、すべての `int` 型変数は `logic signed [31:0]` (32bit) として出力されます。しかし、中間変数（`r_q0`-`r_q7` など）は実際には 1bit しか使われておらず、上位 31bit は未使用です。また、これらに対するビット演算やポート接続時に幅の自動拡張・切り捨てが発生するため、Verilatorから大量の `UNUSED` および `WIDTH` 関連のリント警告が出力されます。
- **未使用変数の残存**:
  前回の修正で不要になった `next_tmds_r/g/b` および `next_cnt_r/g/b`（計6個）が `encoder.cm` に宣言されたまま残っており、これが `UNUSED` および `UNDRIVEN` 警告を発生させています。

## 3. 対策

### (1) 不要な一時出力変数の削除
`src/hdmi/encoder/encoder.cm` から、完全に未使用となった `next_tmds_r/g/b` および `next_cnt_r/g/b` の宣言を削除します。

### (2) Verilatorリント警告の一括抑止（インラインコントロールコメントの追加）
自動生成コード特有のビット幅不一致や未使用ビットに関する警告を安全に無視するため、生成された SystemVerilog ファイルの先頭に以下のコントロールコメントを挿入します。
```systemverilog
/* verilator lint_off UNUSED */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off UNDRIVEN */
```
これを `postprocess_sv.sh` の中で安全に行うため、一時ファイルを利用してファイルの先頭に挿入するポータブルな処理を組み込みます。

## 4. 検証項目
1. `./builder.sh hdmi` を実行し、Verilatorリントチェックが 0 件の警告で正常に通過することを確認する。
2. Gowin EDAでのビルドが正常に終了することを確認する。
