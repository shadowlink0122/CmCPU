# HDMIタイミングバイオレーション不具合の改善設計書

## 1. 概要
HDMIテキスト表示回路 (`hdmi_text_top`) のビルドにおいて、画面が白一色で表示されない（もしくは正しく動かない）問題が発生しています。
Gowin Synthesisのタイミングレポートを解析した結果、深刻なタイミングバイオレーションが発生しており、実機での正常な動作周波数（25.2MHz）を満たせていないことが判明しました。
本ドキュメントでは、このタイミング不具合の原因と、除算・剰余演算を排除した最適化の設計についてまとめます。

## 2. 不具合解析（タイミングバイオレーション）

Gowin Synthesis Report (`hdmi_text_syn.rpt.html`) から以下のタイミングエラーが確認されました。

- **目標周波数**: 25.000 MHz (周期 40.000 ns)
- **実効最大周波数 (Actual Fmax)**: **16.464 MHz**
- **スラック (Slack)**: **-20.740 ns** (深刻な時間不足)
- **クリティカルパス**: `write_cnt` レジスタから `text_char` レジスタへの伝搬パス
- **論理レベル数**: **63 レベル** (LUTの多段接続による巨大な遅延)

### 2.1 原因箇所の特定
`src/hdmi/text/animation_ctrl.cm` 内の以下の処理が、32ビット精度 (`uint`) での組み合わせ回路による除算および剰余演算を多用しており、巨大なハードウェア遅延（63段のLUTチェーン）を生成しています。

```cm
// 32ビット除算・剰余が毎クロック実行されるため、伝搬遅延が40nsを超過している
utiny get_table_char(uint r, uint idx) {
    uint c = idx / 10;
    uint offset = idx % 10;
    uint val = 32 + c * 16 + r;

    if (offset == 0) { return (((val / 100) + 48) as utiny); }
    else if (offset == 1) { return ((((val / 10) % 10) + 48) as utiny); }
    else if (offset == 2) { return (((val % 10) + 48) as utiny); }
    ...
}
```

FPGAにおいて32ビットの除算 (`/ 10`, `/ 100`) や剰余 (`% 10`) は非常に重い回路（減算器の縦列接続）となり、1クロックサイクル内で完了させることが困難です。さらに、これらを同一の組み合わせパスで連続して行うことがタイミング未達の直接原因となっています。

---

## 3. 最適化方針と設計

 division (`/`) および modulo (`%`) 演算を完全に排除し、値の範囲が限定されている特徴を利用した比較・減算による「8ビット軽量デコーダ」へと置き換えます。

### 3.1 `idx / 10` および `idx % 10` の最適化
`idx` (`write_cnt`) は最大でも `59` までの値しかとりません。そのため、以下のような段階的な比較・減算（8ビット `utiny` 精度の `if-else`）で商 `c` と剰余 `offset` を瞬時に計算できます。

```cm
utiny c = 0;
if (idx >= 50) { c = 5; }
else if (idx >= 40) { c = 4; }
else if (idx >= 30) { c = 3; }
else if (idx >= 20) { c = 2; }
else if (idx >= 10) { c = 1; }
else { c = 0; }

utiny offset = idx - c * 10;
```
これにより、汎用的な32ビット除算器・剰余器が不要になり、わずか数段の8ビット比較器と乗算・減算のみで回路化されるため、遅延が劇的に削減されます。

### 3.2 `val` の10進数デコード（3桁の分離）の最適化
`val` (ASCII値) は `32` から `127` の範囲に完全に収まります。
このため、以下のように100の位、10の位、1の位を比較と単純な減算のみでデコードします。

```cm
utiny digit100 = 0;
utiny digit10 = 0;
utiny digit1 = 0;

if (val >= 100) {
    digit100 = 1;
    utiny rem = val - 100;
    if (rem >= 90) { digit10 = 9; digit1 = rem - 90; }
    else if (rem >= 80) { digit10 = 8; digit1 = rem - 80; }
    else if (rem >= 70) { digit10 = 7; digit1 = rem - 70; }
    else if (rem >= 60) { digit10 = 6; digit1 = rem - 60; }
    else if (rem >= 50) { digit10 = 5; digit1 = rem - 50; }
    else if (rem >= 40) { digit10 = 4; digit1 = rem - 40; }
    else if (rem >= 30) { digit10 = 3; digit1 = rem - 30; }
    else if (rem >= 20) { digit10 = 2; digit1 = rem - 20; }
    else if (rem >= 10) { digit10 = 1; digit1 = rem - 10; }
    else { digit10 = 0; digit1 = rem; }
} else {
    digit100 = 0;
    if (val >= 90) { digit10 = 9; digit1 = val - 90; }
    else if (val >= 80) { digit10 = 8; digit1 = val - 80; }
    else if (val >= 70) { digit10 = 7; digit1 = val - 70; }
    else if (val >= 60) { digit10 = 6; digit1 = val - 60; }
    else if (val >= 50) { digit10 = 5; digit1 = val - 50; }
    else if (val >= 40) { digit10 = 4; digit1 = val - 40; }
    else if (val >= 30) { digit10 = 3; digit1 = val - 30; }
    else if (val >= 20) { digit10 = 2; digit1 = val - 20; }
    else if (val >= 10) { digit10 = 1; digit1 = val - 10; }
    else { digit10 = 0; digit1 = val; }
}
```

### 3.3 データ幅の `utiny` (8-bit) 化
`animation_ctrl.cm` 内の以下のシグネチャを `uint` (32-bit) から `utiny` (8-bit) に変更し、不要な高ビット演算を抑制します。

- `get_col_header_char(utiny idx)`
- `get_table_char(utiny r, utiny idx)`
- `write_cnt` レジスタ自体を `uint` から `utiny` もしくは `ushort` に変更 (最大値60のため `utiny` で十分)
- `row_idx` も `uint` から `utiny` に変更 (最大値18のため)

---

## 4. 期待される効果
- 除算・剰余用回路の全廃により、組み合わせ回路の論理レベル（LUT段数）が **63段から10段未満** へと減少します。
- これにより、スラック (Slack) が正（正の時間的余裕）になり、実効動作周波数が25.2MHzを余裕で超えるようになります。
- タイミングバイオレーションが解消されることで、実機への書き込み時にHDMI信号の同期が安定し、画面上にASCIIコード表が正しく表示されるようになります。
