# HDMI表示ブラックアウトおよびSystemVerilogコードネスト深さの改善設計書

## 1. 背景と課題

前回の修正でキャラクターコードを9ビット（512文字領域）に拡張し、グリッドサイズを8列×37行（計296文字）に拡張した際、FPGAへの書き込み後に画面が何も出力されない（ブラックアウトする）現象が発生しました。

SystemVerilogの出力ファイル（ `build/hdmi/hdmi_text.sv` ）を調査した結果、以下の2つの関数において極めて深い条件分岐ネスト（43段および33段）が生成されていることが判明しました。

1. **`get_header_char(idx)`**
   - Cm側の記述において、各インデックスごとに `if (idx == X) { return ...; }` のように早期リターン（ `return` ）を使用していたため、CmコンパイラがこれをSystemVerilogの深い `else begin if (...) end` のネストに自動変換した。これにより、SystemVerilog側で最大43段におよぶシリアルな multiplexer チェーンが生成された。
2. **`get_ctrl_abbrev(val, pos)`**
   - 同様に早期リターンを使用していたため、最大33段の multiplexer チェーンが生成された。

### ブラックアウトの原因

多くのFPGA合成ツール（特にGowinSynthesisなどの軽量なツールチェーン）は、1つの関数内で30段〜40段を超える非常に深い `if-else` ネストやシリアルマルチプレクサ構造に遭遇すると、以下のような問題を引き起こします。

1. **合成エンジンの論理最適化のバグ/破綻**:
   - 膨大な深さの条件判定グラフの最適化において、合成ツールが論理を誤って定数 `0` または不定（ `X` ）として最適化してしまい、回路が機能しなくなる。
2. **極端な伝搬遅延によるタイミングエラー**:
   - 43個のLUTを直列に通過するデータパスが形成され、タイミング制約を満たせずクロック間のデータセットアップが破綻し、出力段の同期レジスタが不定値に固定され、結果として画面がブラックアウトする。

---

## 2. 改善方針

### A. 早期リターンの廃止と一時変数の使用によるネスト平坦化

Cmコードから `if` ブロック内部の早期リターン（ `return` ）を完全に排除し、一時変数への代入方式に変更します。

これにより、CmコンパイラはSystemVerilogへ出力する際、 `else begin if` のネスト構造を作らず、並列で独立した `if` 文の列として出力します。合成ツールはこれを深いシリアルチェーンではなく、浅い並列マルチプレクサツリー（対数的なデコーダ）として合成できるため、ネストが解消され、論理バグとタイミング遅延の両方が一気に解決します。

#### 例：`get_header_char` の平坦化イメージ (Cm)

```cm
// 修正前
utiny get_header_char(utiny idx) {
    if (idx == 0) { return '=' as utiny; }
    if (idx == 1) { return '=' as utiny; }
    ...
    return ' ' as utiny;
}

// 修正後
utiny get_header_char(utiny idx) {
    utiny c = ' ' as utiny;
    if (idx == 0) { c = '=' as utiny; }
    if (idx == 1) { c = '=' as utiny; }
    ...
    return c;
}
```

これにより、SystemVerilog側では以下の平坦なコードが生成されます。

```systemverilog
    if (idx == 32'd0) begin
        c = 32'd61;
    end
    if (idx == 32'd1) begin
        c = 32'd61;
    end
```

---

## 3. 具体的な変更内容

1. **`get_header_char` の変更** (`src/hdmi/text/animation_ctrl.cm`):
   - 一時変数 `c` を導入し、各 `idx` に応じて値を代入し、最後に `c` を返します。
2. **`get_ctrl_abbrev` の変更** (`src/hdmi/text/animation_ctrl.cm`):
   - 一時変数 `c` を導入します。
   - `val` と `pos` を `if (val == X)` のブロック内にまとめ、その中で `pos` による判定を行い `c` に代入します。
3. **`get_table_char` の変更** (`src/hdmi/text/animation_ctrl.cm`):
   - すでに一部一時変数代入を行っていますが、 `return` を使用している箇所を一時変数 `res_char` への代入に統一し、最後の一行でのみ `return res_char` とします。

---

## 4. 期待される効果

- SystemVerilog出力コードのネストが最大でも2レベル以内に収まり、コードが非常にシンプルかつ可読性の高い状態になります。
- GowinSynthesisが正しく論理を解釈できるようになり、ブラックアウト現象が解消され、ASCIIおよび日本語グリッドが正常に表示されるようになります。
- 最大遅延が大幅に減少し、タイミング上の安全性が向上します。
