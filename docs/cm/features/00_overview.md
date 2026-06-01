# Cm SV バックエンド: HDMI プロジェクトに必要な機能拡張

## 概要

HDMI テキスト出力プロジェクトの実装中に特定された、
Cm SV バックエンドに不足している (または未確認の) 機能の一覧。

## 機能一覧

| # | 機能 | 優先度 | ステータス | ドキュメント |
|---|------|--------|-----------|-------------|
| F1 | ビットシフト演算子 (`<<`, `>>`) | **HIGH** | ✅ 実装済み | [sv_bitshift_operators.md](sv_bitshift_operators.md) |
| F2 | 配列宣言 / BRAM 推論 | **MEDIUM** | ✅ 修正済み (v0.15.1) | [sv_array_declaration.md](sv_array_declaration.md) |
| F3 | マルチモジュール / import | **LOW** | 未実装 | [sv_multi_module.md](sv_multi_module.md) |
| F4 | 符号付き整数 (signed) | **MEDIUM** | ✅ 実装済み | [sv_signed_integers.md](sv_signed_integers.md) |

## 影響度マトリクス

| 機能 | TMDS Encoder | Video Timing | GBC Display | Font ROM | Text Renderer | Animation |
|------|:-----------:|:----------:|:----------:|:------:|:----------:|:--------:|
| F1: ビットシフト | ●● | - | ● | ● | ●● | - |
| F2: 配列 | - | - | - | ●● | ●● | ● |
| F3: マルチモジュール | ● | ● | ● | ● | ● | ● |
| F4: 符号付き整数 | ●● | - | - | - | - | - |

凡例: ●● = 必須, ● = あると便利, - = 不要

## 回避策サマリ

全ての機能には回避策が存在し、機能が未実装でもプロジェクトは進行可能:

| 機能 | 回避策 | コスト |
|------|--------|--------|
| F1 | 除算 + マスクによるビット操作 | コード量 2-3× 増加 |
| F2 | if/else チェーン or Gowin IP ROM | 小規模 ROM は可、大規模は Gowin IP |
| F3 | 手動 SV トップモジュール | 1 ファイル追加 |
| F4 | オフセット付き unsigned 表現 | バグリスク増加 |

## 事前検証チェックリスト

実装開始前に以下を確認する:

- [ ] `<<` / `>>` が SV に正しく生成されるか (`feature/v0.15.0` ブランチ)
- [ ] `>=` / `<=` 比較演算子が SV に正しく生成されるか
- [ ] `utiny data[N]` 形式の配列宣言が SV に変換されるか
- [ ] `extern struct` でユーザー定義モジュールをインスタンス化できるか
- [ ] `int` (符号付き) 型が `logic signed` として生成されるか
- [ ] `~` (ビット反転) が SV の `~` として正しく生成されるか

## 検証手順

```bash
# 1. Cm コンパイラの SV ブランチに切り替え
cd Cm
git checkout feature/v0.15.0
make build

# 2. テスト用 .cm ファイルを作成して各機能を確認
cd ../CmCPU
cat > .tmp/test_shift.cm << 'EOF'
//! platform: sv
#[input] posedge clk;
#[input] utiny a = 0;
#[output] utiny b = 0;
void process(posedge clk) {
    b = (a << 2) as utiny;
}
EOF

./Cm/cm compile --target=sv .tmp/test_shift.cm -o .tmp/test_shift.sv
cat .tmp/test_shift.sv
verilator --lint-only --timing -Wno-fatal .tmp/test_shift.sv
```
