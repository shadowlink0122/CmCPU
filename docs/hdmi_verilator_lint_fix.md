# HDMI Verilator リント警告解消設計

## 1. 背景と問題の事象
`./builder.sh --apply hdmi` 実行時に、Verilator のリントチェックにおいて大量のビット幅不一致に関する警告（`%Warning-WIDTHTRUNC`, `%Warning-WIDTHEXPAND` など計404件）が発生し、ビルドプロセスが失敗します。

## 2. 原因調査結果
Cm から SystemVerilog へのコンパイル過程で、`encoder.cm` や `pattern.cm` 内の変数（`tiny` (8bit) / `short` (16bit)）と、Cm言語の整数リテラル（暗黙的に `int` (32bit) となる）が混在する演算が行われています。
Cm の SV バックエンドでは、型キャスト（`as tiny` 等）が現状では SV レベルのキャストコードに変換されず、単に元のオペランド値がそのまま出力されます。さらに、複数の二項演算が連なる複雑な式（popcount や DCバランス計算など）において、フロントエンドによる型推論で中間の一時変数の型が `int` (32bit) に昇格されます。
これらが SystemVerilog のコードとして出力された際、32bit の中間値やリテラルと、8bit/16bit の変数・レジスタが混在する式が大量に生成され、Verilator の厳密なビット幅チェックに違反していました。

## 3. 対策方針
最も安全かつ確実な対策として、タイミング制御以外の演算に用いるすべてのデータ、カウンタ、および中間変数の型を 32bit の `int`（または `uint`）に統一します。
HDMI カラーバーの画像生成および TMDS エンコードにおけるすべての数値型を 32bit 整数に統一することで、出力される SystemVerilog コード上で 32bit 演算に統一され、Verilator の警告が完全にゼロになります。
これは、以前に正常動作していたコミット `7df0eb2d4f7a39945cdd8f74df3e68a62507b84d` の型定義ポリシーと同じです。

## 4. 具体的な変更内容

### ① [pattern.cm](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/pattern/pattern.cm)
- `r_out`、`g_out`、`b_out` の定義を `utiny` から `int` に戻します。

### ② [encoder.cm](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/encoder/encoder.cm)
- 状態変数 `tmds_r`、`tmds_g`、`tmds_b` を `short` から `int` に戻します。
- DCバランスカウンタ `cnt_r`、`cnt_g`、`cnt_b` を `tiny` から `int` に戻します。
- `tmds_encode_r`、`tmds_encode_g`、`tmds_encode_b` の関数内のすべてのローカル中間変数（`*_n1`, `*_use_xnor`, `*_q0` 〜 `*_q7`, `*_qm`, `*_n1_qm`）を `tiny` / `short` から `int` に変更します。

## 5. 検証計画

1. **コンパイラの再確認**:
   `cd Cm && make build` が問題なくビルドできることを確認。
2. **ローカルリント検証**:
   `/usr/local/bin/verilator --lint-only --timing -Wno-MODMISSING build/hdmi/hdmi_colorbar.sv` を実行し、警告が 0 件になることを確認。
3. **ビルドスクリプト検証**:
   `./builder.sh hdmi` を実行し、警告 0 件で正常終了することを確認。
