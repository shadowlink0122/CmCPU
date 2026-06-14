# タイトル文字列の別ファイル化とインデックス管理改善の設計書

## 背景と目的
Cm の SystemVerilog (SV) バックエンドでは、`string` 型は非合成型 (`error[SV003]`) として扱われ、回路としてはトランスパイル・合成することができません。
そのため、アスキー文字をビットシフトによりパックした `uint` 型定数を用いる必要があります。

本設計では、これらのパック定数を `animation_ctrl.cm` から完全に切り離し、専用モジュール `src/hdmi/text/display_strings.cm` に分離することで、ロジックから定数定義を隠蔽し、プログラマ視点での文字列表現の管理・保守性を向上させます。

---

## 構成設計

### 1. 新モジュール `src/hdmi/text/display_strings.cm`
ヘッダー文字列 `=== Character Code Table (ASCII & KANA) ===`（全43文字）を4文字ごとの `uint` 定数にパックして定義し、`export` キーワードで公開します。
コメントを用いて、連続した一つの文字列として読めるように視覚的な配慮を施します。

```cm
module display_strings;

// 全体文字列イメージ:
// "=== Character Code Table (ASCII & KANA) ==="

export const uint TITLE_0  = (('=' as uint) << 24) | (('=' as uint) << 16) | (('=' as uint) << 8) | (' ' as uint); // "=== "
export const uint TITLE_1  = (('C' as uint) << 24) | (('h' as uint) << 16) | (('a' as uint) << 8) | ('r' as uint); // "Char"
export const uint TITLE_2  = (('a' as uint) << 24) | (('c' as uint) << 16) | (('t' as uint) << 8) | ('e' as uint); // "acte"
export const uint TITLE_3  = (('r' as uint) << 24) | ((' ' as uint) << 16) | (('C' as uint) << 8) | ('o' as uint); // "r Co"
export const uint TITLE_4  = (('d' as uint) << 24) | (('e' as uint) << 16) | ((' ' as uint) << 8) | ('T' as uint); // "de T"
export const uint TITLE_5  = (('a' as uint) << 24) | (('b' as uint) << 16) | (('l' as uint) << 8) | ('e' as uint); // "able"
export const uint TITLE_6  = ((' ' as uint) << 24) | (('(' as uint) << 16) | (('A' as uint) << 8) | ('S' as uint); // " (AS"
export const uint TITLE_7  = (('C' as uint) << 24) | (('I' as uint) << 16) | (('I' as uint) << 8) | (' ' as uint); // "CII "
export const uint TITLE_8  = (('&' as uint) << 24) | ((' ' as uint) << 16) | (('K' as uint) << 8) | ('A' as uint); // "& KA"
export const uint TITLE_9  = (('N' as uint) << 24) | (('A' as uint) << 16) | ((')' as uint) << 8) | (' ' as uint); // "NA) "
export const uint TITLE_10 = (('=' as uint) << 24) | (('=' as uint) << 16) | (('=' as uint) << 8) | (' ' as uint); // "=== "
```

### 2. `src/hdmi/text/animation_ctrl.cm` の変更
`display_strings` モジュールをインポートし、ローカルに定義されていたタイトル文字列定数をすべて削除します。

```cm
import ./display_strings;
```

`get_header_char(idx)` 関数の内部実装は、インポートされた `display_strings::TITLE_X` 定数をそのまま参照する形で実行されます。

---

## 検証計画
1. **HDMI Textビルド**: `make text-build` を実行し、コンパイル・リントエラーが起きないことを検証します。
2. **物理合成検証**: `make text-gowin` で論理合成が正常に通ることを検証します。
3. **実機動作検証**: `make text-flash` で書き込み、HDMI画面上のヘッダータイトルが正しく描画されることを確認します。
