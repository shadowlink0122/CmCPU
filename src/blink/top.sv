// トップレベルモジュール: 内蔵OSC + Lチカ回路
// Gowin内蔵オシレータ(52.5MHz)をblinkモジュールに供給し、
// CFG LEDのREADY/DONEを同時にトグル
`timescale 1ns / 1ps

module top (
    output logic led_ready,
    output logic led_done
);

    // 内蔵オシレータ (210MHz / 4 = 52.5MHz)
    wire clk;
    OSC #(
        .FREQ_DIV(4)
    ) osc_inst (
        .OSCOUT(clk)
    );

    // Cm生成 blink モジュール
    wire led_out;
    blink blink_inst (
        .clk(clk),
        .led(led_out)
    );

    // CFG LED の READY/DONE 両方に出力
    assign led_ready = led_out;
    assign led_done  = led_out;

endmodule
