# 制御文字の3文字略記定数定義のモジュール分割設計書

## 背景と目的
前回のリファクタリングにより、`animation_ctrl.cm` 内の制御文字略記アスキーパック定義を `const` 定数として可読化しました。
本設計では、定数定義が `animation_ctrl.cm` 内に多く存在している状態を解消し、文字管理をより容易にするため、これらの定数を別のモジュールファイル `ctrl_abbrev.cm` に分割します。
これにより、文字の追加・変更が1箇所で管理可能となり、`animation_ctrl.cm` は本来の制御・描画ロジックのみに集中することができます。

---

## 構成設計

### 1. 新モジュール `src/hdmi/text/ctrl_abbrev.cm`
すべての制御文字アスキーパック定数をこのファイルに定義し、`export` キーワードを用いて外部に公開します。

```cm
module ctrl_abbrev;

// 制御文字の3文字略記定数定義
export const uint NUL = (('N' as uint) << 16) | (('U' as uint) << 8) | ('L' as uint);
export const uint SOH = (('S' as uint) << 16) | (('O' as uint) << 8) | ('H' as uint);
...
```

### 2. `src/hdmi/text/animation_ctrl.cm` の変更
`ctrl_abbrev` モジュールをインポートし、定数定義部を削除します。

```cm
import ./ctrl_abbrev;
```

これにより、既存のロジック（`get_ctrl_abbrev` や `extract_char`）は一切変更することなく、定数をクリーンに参照できます。

---

## 検証計画
1. **HDMI Textビルド**: `make text-build` を実行し、トランスパイル後の `build/hdmi/hdmi_text.sv` が正常に生成され、リントチェックを通過することを確認します。
2. **物理合成・実機検証**: `make text-gowin` および `make text-flash` を実行し、実機でアスキー文字が崩れることなく正常に描画されることを検証します。
