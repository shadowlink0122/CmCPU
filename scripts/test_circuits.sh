#!/bin/bash
# ============================================================
# 回路のシミュレーションテスト（自動発見）
# ============================================================
# 使い方: test_circuits.sh [対象ディレクトリ]（省略時は src 全体）
#
# 以下を自動的に発見し、`cm test` で実行する:
#   - テストラッパー: <対象>/**/*_test.cm（対象モジュールと同じ階層に配置）
#   - #[test] 関数を含む回路: <対象>/**/*.cm
#
# `cm test` は //! platform: sv を検出してSV+テストベンチを生成し、
# iverilog + vvp でシミュレーションを実行する（TEST が自動定義される）。
# 生成物・ログは .tmp/test/ に出力される。
# ============================================================
set -u
cd "$(dirname "$0")/.."

ROOT="${1:-src}"
if [ ! -d "$ROOT" ]; then
    echo "エラー: テスト対象ディレクトリがありません: $ROOT"
    echo "利用可能な対象:"
    find src -mindepth 1 -maxdepth 1 -type d | sed 's|^src/|  |' | sort
    exit 1
fi

CM=Cm/cm
OUT=.tmp/test
mkdir -p "$OUT"

# テキスト系はフォントROM（$readmemh）を実行ディレクトリに要する
cp src/hdmi_text/font/font_rom.hex "$OUT/" 2>/dev/null || true

# テスト対象の自動発見（*_test.cm + #[test] を含むファイル）
TARGETS=$( { find "$ROOT" -name "*_test.cm"; grep -rl '#\[test\]' "$ROOT" --include="*.cm"; } | sort -u )

if [ -z "$TARGETS" ]; then
    echo "エラー: $ROOT にテスト（*_test.cm または #[test]）が見つかりません"
    exit 1
fi

PASSED=0
FAILED=0

for src in $TARGETS; do
    # テスト名は「カテゴリ_テスト名_test」形式（中間サブフォルダは含めない。同一カテゴリ内でテストファイル名は一意にすること）
    # カテゴリ = src直下のフォルダ名（modulesは modules_<モジュール名>）
    # 例: src/hdmi_text/renderer/text_renderer_test.cm → hdmi_text_text_renderer_test
    rel="${src#src/}"
    base=$(basename "$rel" .cm)
    category=$(dirname "$rel")
    top="${category%%/*}"
    if [ "$top" = "modules" ]; then
        rest="${category#modules/}"
        top="modules_${rest%%/*}"
    fi
    name="${top}_${base}"
    case "$name" in
        *_test) ;;
        *) name="${name}_test" ;;
    esac
    log="$OUT/$name.log"

    if "$CM" test "$src" > "$log" 2>&1; then
        pass_count=$(grep -c "^PASS:" "$log" || true)
        echo "[PASS] $name (${pass_count} assertions)"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $name:"
        grep -E "^(PASS|FAIL|エラー|assertion)" "$log" | tail -5 | sed 's/^/    /'
        echo "    （詳細: $log）"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "結果: PASS=$PASSED FAIL=$FAILED"
[ "$FAILED" -eq 0 ]
