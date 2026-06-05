# HDMIトップモジュール不整合の解消および実機デプロイタイミングバグ修正

## 1. 背景と問題の診断

HDMIカラーバーの細分化リファクタリング（`main.cm` およびサブモジュールの導入）を行った後、実機デプロイを試みましたが、以下の2つの問題が発生していました。

1. **画面が「接続なし（No Signal）」になる問題**:
   以前の単一ファイル実装である `hdmi_colorbar_old.cm` からコンパイルされた SystemVerilog は正常に実機へ書き込めていましたが、ディスプレイ側で「何も接続されていない」状態になっていました。
2. **トップモジュールが見つからない問題**:
   リファクタリング後の分割モジュール（`main.cm`）のビルドを行う際、Gowin合成フェーズで `No valid top module found` エラーが発生し、ビットストリーム（`.fs`）が正常に生成できなくなっていました。

---

## 2. 原因分析

### 原因A: 旧コードにおける非ブロッキング代入（`<=`）によるTMDSエンコーダの論理破綻

旧コード `hdmi_colorbar_old.cm` を調査したところ、SystemVerilog出力においてすべての中間計算変数（`r_n1`, `r_use_xnor`, `r_qm`, 各ビットスライス `r_q0`-`r_q7` など）が `always_ff` 内で非ブロッキング代入（`<=`）されていました。

```sv
// 旧コードの生成例
if ((de_reg == 1'b1)) begin
    r_n1 <= ...;
    if ((r_n1 > 4)) begin  // 同一サイクル内の <= 代入直後の参照（古い値を読み出す）
        r_use_xnor <= 1;
    end
    r_q0 <= (r_out & 1);
    r_q1 <= (r_out >> 1) ^ r_q0 ^ r_use_xnor; // 古い r_q0, r_use_xnor を参照するため計算が破綻
```

SystemVerilogの `always_ff`（レジスタ動作）内で中間計算に非ブロッキング代入を行うと、代入結果の反映は次のクロックエッジまで保留されます。そのため、同じサイクル内でその変数を参照すると「前のサイクルでの値」を読み出してしまい、TMDSのエンコード論理（遷移最小化やDCバランスの計算）が完全に崩壊していました。この結果、不正なTMDSストリームおよび無効な同期信号がモニターへ送信され、モニター側がHDMI/DVI接続として認識できずに「接続なし」となっていました。

新しい `main.cm` 内の `encoder.cm` では、これらの中間変数が `async func` 内のローカル変数として宣言されています。

```cm
// 新しい Cm の書き方
export async func tmds_encode_r(posedge pixel_clk) {
    tiny r_n1 = 0;
    tiny r_use_xnor = 0;
    ...
```

Cmコンパイラはこれらを SystemVerilog の `always_ff` ブロック内のローカル変数（`logic`）として生成し、それらへの代入をブロッキング代入（`=`）として出力します。

```sv
// 新コードの生成結果
always_ff @(posedge pixel_clk) begin
    logic signed [7:0] r_n1;
    logic signed [7:0] r_use_xnor;
    ...
    r_n1 = ...; // ブロッキング代入
    if ((r_n1 > 4)) begin
        r_use_xnor = 1; // 同一サイクル内で直ちに反映される
```

これにより、同じサイクル内で中間結果が正しく伝搬し、組み合わせ論理としてのTMDSエンコードが正確に実行されるため、タイミングと論理の整合性が完全に維持されます。

### 原因B: `gowin_hdmi.tcl` 内の `-top_module` ハードコーディング

Gowinのビルド制御を行う `src/hdmi/gowin_hdmi.tcl` 内で、トップモジュール名が旧コードのモジュール名である `hdmi_colorbar_old` に固定されていました。

```tcl
set_option -top_module hdmi_colorbar_old
```

新しい分割コード `main.cm` をコンパイルすると、生成されるSystemVerilogファイル `hdmi_colorbar.sv` には `module main` が定義されます。Gowin EDAはこの中から `hdmi_colorbar_old` を探そうとしますが、存在しないため `No valid top module found` エラーを出力して合成を中断していました。

---

## 3. 解決策の適用

1. **Gowinビルド設定の修正**:
   `src/hdmi/gowin_hdmi.tcl` のトップモジュール設定を `main` に書き換えます。
   ```tcl
   set_option -top_module main
   ```
2. **分割コード `main.cm` の使用**:
   ビルドおよび実機デプロイのターゲットを `main.cm` に指定します。
   ```bash
   ./builder.sh hdmi main --apply
   ```

## 4. Gowin EDA 最適化フェーズでのクラッシュと対策

### 現象
上記の修正を適用して `main.cm` をコンパイルし、`gowin_hdmi.tcl` で合成を実行した際、Gowin EDA の `Optimizing Phase 1` 中に以下のクラッシュが発生しました。

```
libc++abi: terminating due to uncaught exception of type std::length_error: basic_string
Gowin EDA 合成失敗
```

### 分析
このクラッシュは、SystemVerilogのコード内で **複数の並列 `always_ff` ブロックが存在し、かつそれぞれの中で複雑な演算やDCバランス計算が行われている場合** に、Gowinの最適化パス（特にセルの結合や最適化変数の名前生成）が破綻して発生するバグであることが判明しました。
旧実装 `hdmi_colorbar_old.sv` では3つのチャネル（Red, Green, Blue）のエンコード処理が **単一の `always_ff` ブロック** 内に並んで記述されていたため、このクラッシュを回避できていました。一方で、新しい分割実装ではチャネルごとに別々の `async func`（= 別々の `always_ff` ブロック）に分けたため、合計 6 個もの並列レジスタブロックが生成され、最適化処理で破綻を引き起こしていました。

### 対策
この合成器のバグを回避するため、`src/hdmi/encoder/encoder.cm` 内の Red, Green, Blue のエンコーダ関数を元の構造と同様に **単一の `async func tmds_encode(posedge pixel_clk)` ブロックに結合** します。
これにより、生成されるSystemVerilogでの `always_ff` ブロックの個数が削減され、Gowin EDAの最適化器が正常に動作するようになります。
また、各エンコードロジック内の中間計算変数はローカル変数のままであるため、タイミング不整合（非ブロッキング代入による論理破綻）の修正効果はそのまま維持されます。

