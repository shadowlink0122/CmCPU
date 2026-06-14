# タイトル文字列のパック化とインデックス管理改善の設計書

## 背景と目的
現在、`src/hdmi/text/animation_ctrl.cm` 内の `get_header_char(idx)` は、インデックス（`idx`）ごとに各文字を返す巨大な `switch` 文で構成されています。
これは文字列の実態が見えにくく、管理や修正が困難な状態です。
制御文字略記（`ctrl_abbrev`）で導入した「3文字アスキーパック定数」と同様のアプローチを採用し、ヘッダータイトル文字列（`=== Character Code Table (ASCII & KANA) ===`）を4文字ずつパックした32ビット整数定数（`TITLE_0`〜`TITLE_10`）として宣言します。
これにより、文字列をより直感的に管理し、文字の切り出し処理を共通化して簡潔な実装にします。

---

## 構成設計

### 1. タイトル文字列のパック定数定義 (`animation_ctrl.cm`)
ヘッダー文字列 `=== Character Code Table (ASCII & KANA) ===`（全43文字）を、4文字ごとの `uint` 定数にパックして定義します。

```cm
// タイトル文字列の4文字パック定数定義
const uint TITLE_0  = (('=' as uint) << 24) | (('=' as uint) << 16) | (('=' as uint) << 8) | (' ' as uint); // "=== "
const uint TITLE_1  = (('C' as uint) << 24) | (('h' as uint) << 16) | (('a' as uint) << 8) | ('r' as uint); // "Char"
const uint TITLE_2  = (('a' as uint) << 24) | (('c' as uint) << 16) | (('t' as uint) << 8) | ('e' as uint); // "acte"
const uint TITLE_3  = (('r' as uint) << 24) | ((' ' as uint) << 16) | (('C' as uint) << 8) | ('o' as uint); // "r Co"
const uint TITLE_4  = (('d' as uint) << 24) | (('e' as uint) << 16) | ((' ' as uint) << 8) | ('T' as uint); // "de T"
const uint TITLE_5  = (('a' as uint) << 24) | (('b' as uint) << 16) | (('l' as uint) << 8) | ('e' as uint); // "able"
const uint TITLE_6  = ((' ' as uint) << 24) | (('(' as uint) << 16) | (('A' as uint) << 8) | ('S' as uint); // " (AS"
const uint TITLE_7  = (('C' as uint) << 24) | (('I' as uint) << 16) | (('I' as uint) << 8) | (' ' as uint); // "CII "
const uint TITLE_8  = (('&' as uint) << 24) | ((' ' as uint) << 16) | (('K' as uint) << 8) | ('A' as uint); // "& KA"
const uint TITLE_9  = (('N' as uint) << 24) | (('A' as uint) << 16) | ((')' as uint) << 8) | (' ' as uint); // "NA) "
const uint TITLE_10 = (('=' as uint) << 24) | (('=' as uint) << 16) | (('=' as uint) << 8) | (' ' as uint); // "=== "
```

### 2. `get_header_char` 関数の簡略化
インデックスごとの分岐を廃止し、4文字ブロックを選択する `switch` と、選択したブロック内の位置に応じたシフト演算による文字抽出で実装します。

```cm
utiny get_header_char(utiny idx) {
    uint word = 0;
    switch (idx / 4) {
        case (0) { word = TITLE_0; }
        case (1) { word = TITLE_1; }
        case (2) { word = TITLE_2; }
        case (3) { word = TITLE_3; }
        case (4) { word = TITLE_4; }
        case (5) { word = TITLE_5; }
        case (6) { word = TITLE_6; }
        case (7) { word = TITLE_7; }
        case (8) { word = TITLE_8; }
        case (9) { word = TITLE_9; }
        case (10) { word = TITLE_10; }
        else { word = 0; }
    }
    utiny shift = (3 - (idx % 4)) * 8;
    return ((word >> shift) & 0xFF) as utiny;
}
```
※Cm の SV バックエンドにおける `SwitchInt` ネスト問題を回避するため、関数呼び出しや複雑なネストを避け、フラットで簡潔な分岐と演算にしています。

---

## 検証計画
1. **HDMI Textビルド**: `make text-build` を実行し、コンパイルエラーや Verilator リントエラーが出ないことを検証します。
2. **物理合成検証**: `make text-gowin` で Gowin FPGAの論理合成が正常に通ることを検証します。
3. **実機動作検証**: `make text-flash` で書き込み、HDMI画面上のヘッダータイトル `=== Character Code Table (ASCII & KANA) ===` が正しく表示されることを検証します。
