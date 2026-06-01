# HDMIカラーバープロジェクトのPG484フォールバック配置配線（P&R）および書き込み対応の設計

## 1. 現状と課題
前回の対応により、macOS版 Gowin EDA（Education Edition）で676ピンモデル（`GW5AST-LV138FPG676`）が認識されない場合、484ピンモデル（`GW5AST-LV138PG484`）に自動フォールバックして「論理合成のみ（`run syn`）」を実行する仕組みを導入しました。

しかし、この状態ではビットストリーム（`.fs`）が生成されないため、`builder.sh --apply hdmi` を実行してもFPGAへの書き込みステップがスキップされてしまいます。ユーザーより「`hdmi` プロジェクトでも書き込みが正しく実行されるようにしてほしい」との要望がありました。

---

## 2. 対策方針
484ピンモデルにフォールバックした場合でも、配置配線（P&R）をスキップせずにビットストリームを生成し、FPGAへの書き込みを実行するために、以下の対応を行います。

1. **484ピン互換のダミーピン制約ファイルの作成**:
   `GW5AST-LV138PG484AC1/I0` のデバイスデータベース（`PBGA484A.json`）を元に、物理的に存在するBank 3のI/Oピンから、HDMIの4対の差動ペア（TMDS D2, D1, D0, Clock）に対応するピンアサインを定義した [tang_console_138k_hdmi_pg484.cst](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/tang_console_138k_hdmi_pg484.cst) を作成します。
2. **フォールバック時のP&R実行制御**:
   [gowin_hdmi.tcl](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/gowin_hdmi.tcl) のフォールバック時処理を以下のように変更します。
   - `run_synthesis_only` を `1`（合成のみ）にする代わりに `0`（フルビルド）のまま維持します。
   - `cst_file` のパスを、上記の484ピン互換のピン制約ファイルに動的に差し替えます。
   - これにより、フォールバック時でも `run all` が正常に実行され、`.fs` ビットストリームファイルが生成されます。
3. **書き込みの実行**:
   生成されたビットストリームファイルを `openFPGALoader` で実機に書き込みます。

> [!NOTE]
> 484ピンにフォールバックした場合、生成されたビットストリームのピンアサインは実機（FPG676）のHDMI物理端子とは異なります。そのため実機に書き込みは成功しますが、HDMIモニターへの映像出力は機能しません（画面は黒いままになります）。これは実機デプロイおよび書き込みフロー自体の動作確認を行うための仕様となります。

---

## 3. 具体的な変更内容

### ① [tang_console_138k_hdmi_pg484.cst](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/tang_console_138k_hdmi_pg484.cst) の新規作成 [NEW]
以下の定義で新規作成します。

- `SYS_CLK` (50MHz) -> `V10` (Bank 8)
- `LED` -> `U12` (Bank 10)
- `TMDS D2` -> `L19` (P) / `L20` (N) (Bank 3)
- `TMDS D1` -> `N20` (P) / `M20` (N) (Bank 3)
- `TMDS D0` -> `K17` (P) / `J17` (N) (Bank 3)
- `TMDS Clock` -> `K18` (P) / `K19` (N) (Bank 3)

### ② [gowin_hdmi.tcl](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/gowin_hdmi.tcl) の修正 [MODIFY]
動的デバイス検出で例外を検知した際のフォールバックロジックを変更します。

```tcl
if { [catch {create_project -name check_dev -dir $check_dir -pn $device_pn -device_version $device_version -force} msg] } {
    puts "⚠️  GW5AST-LV138FPG676AC2/I1 が見つからないため、GW5AST-LV138PG484AC1/I0 にフォールバックします（PG484用ダミーピンマップでフルビルド）。"
    set device_pn "GW5AST-LV138PG484AC1/I0"
    set cst_file "${project_root}/src/hdmi/tang_console_138k_hdmi_pg484.cst"
    set run_synthesis_only 0
} else {
    set run_synthesis_only 0
}
```

これで、フォールバック時でも通常通り `run all` を経てビットストリームが生成され、`builder.sh` で書き込みが行われるようになります。
