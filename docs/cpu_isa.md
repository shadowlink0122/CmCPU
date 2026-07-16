# SimpleCPU 命令セットアーキテクチャ (ISA)

## 概要

SimpleCPU（`src/cpu/`）は、C言語風の簡単なプログラミング言語のコンパイル対象にできることを目標にした、8レジスタ・16bit命令のロード/ストア型CPUである。
データパスは32bit、命令は1命令/サイクルで実行される（フェッチ・デコード・実行を同一サイクルで行う単純な構成）。
命令ROM（16ワード）とデータRAM（256ワード）を分離したハーバードアーキテクチャで、結果出力はメモリマップドI/Oで行う。

## レジスタ

| レジスタ | 用途（呼び出し規約） |
|---|---|
| r0 | 常に0（書き込みは無視される） |
| r1〜r3 | 引数・戻り値 |
| r4〜r5 | 一時レジスタ |
| r6 | スタックポインタ (SP) |
| r7 | リンクレジスタ (JALの戻り先) |

## 命令フォーマット

| 形式 | [15:12] | [11:9] | [8:6] | [5:3] | [5:0] | [7:0] |
|---|---|---|---|---|---|---|
| R形式 | op | rd | rs1 | rs2 / funct | - | - |
| I形式 | op | rd | rs1 | - | imm6（符号付き） | - |
| LI形式 | op | rd | - | - | - | imm8（符号なし） |

## 命令セット

| opcode | ニーモニック | 形式 | 動作 |
|---|---|---|---|
| 0x0 | NOP | - | 何もしない |
| 0x1 | ADD rd, rs1, rs2 | R | rd = rs1 + rs2 |
| 0x2 | SUB rd, rs1, rs2 | R | rd = rs1 - rs2（2の補数） |
| 0x3 | AND rd, rs1, rs2 | R | rd = rs1 & rs2 |
| 0x4 | OR rd, rs1, rs2 | R | rd = rs1 \| rs2 |
| 0x5 | XOR rd, rs1, rs2 | R | rd = rs1 ^ rs2 |
| 0x6 | SHIFT rd, rs1, funct | R | funct=0: rd = rs1 << 1 / funct=1: rd = rs1 >> 1 |
| 0x7 | LDI rd, imm8 | LI | rd = imm8 |
| 0x8 | ADDI rd, rs1, imm6 | I | rd = rs1 + imm6（符号付き即値） |
| 0x9 | LD rd, [rs1 + imm6] | I | rd = dram[rs1 + imm6] |
| 0xA | ST rd, [rs1 + imm6] | I | dram[rs1 + imm6] = rd |
| 0xB | BEQ ra, rb, imm6 | I | ra == rb なら pc = pc + 1 + imm6（raはrdフィールド、rbはrs1フィールド） |
| 0xC | BNE ra, rb, imm6 | I | ra != rb なら pc = pc + 1 + imm6（同上） |
| 0xD | JAL rd, imm8 | LI | rd = pc + 1; pc = imm8（関数呼び出し） |
| 0xE | JR rs1 | R | pc = rs1（関数からの復帰） |
| 0xF | HALT | - | 停止（halt_led点灯） |

## メモリマップ（LD/STの実効アドレス下位8bit）

| アドレス | 内容 |
|---|---|
| 0x00〜0xFE | データRAM |
| 0xFF | 結果出力ポート（書き込むと下位8bitが `result_out` へ出力される） |

## C言語風コードとの対応

デモプログラム（`src/cpu/program/demo_program.cm`）は次のC風コードを手動コンパイルしたものである。

```c
int twice(int x) { return x + x; }
int main() {
    int sum = 0;
    for (int i = 1; i != 11; i = i + 1) {
        sum = sum + i;              // sum = 1+2+...+10 = 55
    }
    sum = twice(sum);               // sum = 110
    *(int*)16 = sum;                // RAMへストア
    int check = *(int*)16;          // RAMからロード
    *(volatile int*)0xFF = check;   // MMIO: 結果出力
    while (1) {}                    // HALT
}
```

簡単なコンパイラを作る場合の基本パターンは以下の通り。

| C風の構文 | 命令列 |
|---|---|
| 定数代入 `x = 42;` | `LDI rX, 42` |
| 加算 `x = a + b;` | `ADD rX, rA, rB` |
| 変数の増分 `i = i + 1;` | `ADDI rI, rI, 1` |
| メモリ読み書き `*(p+n)` | `LD/ST rX, [rP + n]` |
| if文・ループの条件分岐 | `BEQ` / `BNE`（pc相対±32命令） |
| 関数呼び出し / return | `JAL r7, addr` / `JR r7` |
| スタックのpush/pop | `ADDI r6, r6, -1; ST rX, [r6+0]` / `LD rX, [r6+0]; ADDI r6, r6, 1` |
| 比較 `a < b` など | `SUB` の結果と分岐の組み合わせ（多語比較は今後の拡張） |

## 回路の構成（ファイル分割）

| ファイル | 内容 |
|---|---|
| `src/cpu/core/adder.cm` | 全加算器と32bitリップルキャリー加算器 |
| `src/cpu/core/alu.cm` | ALU（加減算は全加算器ベース、減算は2の補数） |
| `src/cpu/core/decoder.cm` | 命令デコーダとオペコード定義 |
| `src/cpu/core/register_file.cm` | レジスタファイル（r0固定0の読み出し関数付き） |
| `src/cpu/core/core.cm` | フェッチ・デコード・実行コアとpc制御 |
| `src/cpu/memory/ram.cm` | データRAMとMMIO定義 |
| `src/cpu/program/demo_program.cm` | デモプログラム（手書きアセンブリのROMデータ） |
| `src/cpu/simple_cpu.cm` | トップモジュール（クロック・出力ポート・統合テスト） |
| `src/cpu/core/alu_test.cm` | 全加算器・加算器・ALUの検証ラッパー |

## 制限事項（今後の拡張候補）

- シフトは1bit固定（可変シフトはループで表現する）
- 乗除算命令なし（加算ループ・シフトで表現する）
- 比較は等値のみ分岐に直結（大小比較はSUBと符号bit判定の組み合わせが必要）
- 命令ROMは16ワード（imm8の範囲で256ワードまで拡張可能）
