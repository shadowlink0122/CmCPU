# 制御文字文字列化統一およびトップレベルモジュール最適化設計書 (改訂版)

## 1. 背景と目的
現在、画面のタイトルヘッダー文字列は `display_strings::TITLE` という `const string` で定義され、インデックスアクセス `TITLE[idx]` を使って1文字ずつ抽出されています。また、制御文字の略記定数も `const string CTRL_ABBREVS` 定義に一本化されました。
しかし、文字を抽出する関数は依然として `get_header_char(idx)` と `get_ctrl_char(code, char_idx)` という2つの異なる関数に分かれています。これらを単一の汎用文字列文字抽出関数 `get_string_char` に統合し、文字列の取り扱い方を完全に統一します。

また、トップレベルモジュール `hdmi_text_top.cm` 内のインポート文を見直し、他のモジュール内でインポート済みの重複する依存関係（`constants`, `timing`, `gbc_display`, `text_renderer`）を削除することで、モジュール間の境界をスッキリさせ、無駄なファイル読み込みや記述を削減します。

---

## 2. 設計詳細

### 2.1 文字列取得処理の統合 (`animation_ctrl.cm`)
- `get_header_char` および `get_ctrl_char` を廃止し、両方の文字列からインデックスアクセスで文字を抽出する `get_string_char` 関数に一本化します。
- Cmの制限（引数として渡した異なる長さの `string` をSystemVerilog上で動的に扱うことが困難）を考慮し、第一引数に `is_title` フラグを受け取ることで分岐して安全に静的グローバル文字列にアクセスします。

```cm
// 文字列からインデックスで文字を抽出する統一関数
utiny get_string_char(bool is_title, utiny idx, utiny offset) {
    if (is_title) {
        return (TITLE[idx] as utiny);
    } else {
        utiny code = idx;
        if (idx == 127) {
            code = 33; // DELのインデックス
        }
        return (CTRL_ABBREVS[(code as uint) * 3 + (offset as uint)] as utiny);
    }
}
```

- `process_anim` におけるヘッダー文字取得の呼出部を変更します。
```diff
- text_char = get_header_char(write_cnt) as ushort;
+ text_char = get_string_char(true, write_cnt, 0) as ushort;
```

- `get_table_char` における制御文字略記取得の呼出部を変更します。
```diff
- res_char = get_ctrl_char(val as utiny, (offset - 5) as utiny) as ushort;
+ res_char = get_string_char(false, val as utiny, (offset - 5) as utiny) as ushort;
```

### 2.2 トップレベルモジュールのインポート最適化 (`hdmi_text_top.cm`)
- `hdmi_text_top.cm` が直接インスタンス化または参照している以外の、冗長なインポートを整理します。
  - `import ./constants/hdmi_constants;`（`encoder` 等でインポート済みのため不要）
  - `import ./timing/timing;`（`encoder` / `text_renderer` 等でインポート済みのため不要）
  - `import ./text/gbc_display;`（`text_renderer` 内でインポート済みのため不要）
  - `import ./text/text_renderer;`（`animation_ctrl` 内でインポート済みのため不要）
- 必要なインポートは以下のみに集約されます。
  - `import ./pll/pll;`
  - `import ./encoder/encoder;`
  - `import ./serdes/oser;`
  - `import ./serdes/obuf;`
  - `import ./text/animation_ctrl;` (これにより間接的に `text_renderer` や `gbc_display` などが再帰インポートされます)

---

## 3. 検証計画

### 3.1 統合ビルドおよびVerilatorリント検証
- `make text-build` を実行し、CmからSVへのトランスパイル、および Verilator によるリントチェックが警告・エラーなしで合格することを確認します。

### 3.2 物理合成・実機検証
- `make text-gowin` を実行し、物理合成が正常に終了することを確認します。
- `make text-flash` を実行し、実機でタイトルおよび制御文字略記（`[NUL]` 等）が正しく表示されることを確認します。
