// ============================================================
// HDMI カラーバー出力回路 (手書き SystemVerilog)
// ============================================================
// ターゲット: Tang Console 138K (GW5AST-LV138PG484)
// クロック: 50MHz 外部 → PLL → pixel_clk + serial_clk (5x)
// 出力: HDMI (DVI モード) 640×480@60Hz 8色カラーバー
//
// Cm 生成 SV の致命的バグ (チャネル間ネスト、非ブロッキング遅延)
// を回避するため、手書きで正しい TMDS エンコーダを実装。
// ============================================================
`timescale 1ns / 1ps

// ============================================================
// TMDS エンコーダモジュール (DVI 1.0 準拠)
// ============================================================
// 構造:
//   入力パイプライン (1段) → 遷移最小化 (組み合わせ) → DC バランス (1段)
//   合計レイテンシ: 2 ピクセルクロック
// ============================================================
module tmds_encoder (
    input  wire       clk,
    input  wire [7:0] din,      // 8-bit ピクセルデータ
    input  wire [1:0] ctrl,     // コントロール信号 (CH0: {VSYNC, HSYNC})
    input  wire       de,       // データイネーブル
    output reg  [9:0] dout      // 10-bit TMDS 出力
);

    // --- 入力パイプライン (タイミング改善用) ---
    reg [7:0] din_q;
    reg [1:0] ctrl_q;
    reg       de_q;

    always @(posedge clk) begin
        din_q  <= din;
        ctrl_q <= ctrl;
        de_q   <= de;
    end

    // --- ステージ 1: 遷移最小化 (組み合わせ論理) ---

    // 入力データの popcount (1 のビット数)
    wire [3:0] n1_din = din_q[0] + din_q[1] + din_q[2] + din_q[3]
                       + din_q[4] + din_q[5] + din_q[6] + din_q[7];

    // XOR/XNOR 選択: 1が多い場合または均等かつbit0=0の場合は XNOR
    wire use_xnor = (n1_din > 4'd4) || (n1_din == 4'd4 && !din_q[0]);

    // q_m[8:0] 構築
    //   q_m[0] = D[0]
    //   q_m[i] = D[i] XOR/XNOR q_m[i-1]  (i=1..7)
    //   q_m[8] = 1(XOR使用) / 0(XNOR使用)
    wire [8:0] q_m;
    assign q_m[0] = din_q[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ din_q[1]) : (q_m[0] ^ din_q[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ din_q[2]) : (q_m[1] ^ din_q[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ din_q[3]) : (q_m[2] ^ din_q[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ din_q[4]) : (q_m[3] ^ din_q[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ din_q[5]) : (q_m[4] ^ din_q[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ din_q[6]) : (q_m[5] ^ din_q[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ din_q[7]) : (q_m[6] ^ din_q[7]);
    assign q_m[8] = ~use_xnor;

    // q_m[7:0] の popcount
    wire [3:0] n1_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3]
                      + q_m[4] + q_m[5] + q_m[6] + q_m[7];

    // --- ステージ 2: DC バランス (レジスタ出力) ---

    // 累積ディスパリティ (符号付き)
    reg signed [5:0] cnt;

    // 演算用中間信号 (符号付き拡張)
    wire signed [5:0] two_n1 = {1'b0, n1_qm, 1'b0};   // 2 * n1_qm (0..16)
    wire signed [5:0] qm8_x2 = q_m[8] ? 6'sd2 : 6'sd0; // 2 * q_m[8] (0 or 2)

    always @(posedge clk) begin
        if (!de_q) begin
            // ブランキング期間: コントロールトークン出力
            cnt <= 6'sd0;
            case (ctrl_q)
                2'b00:   dout <= 10'b1101010100; // {C1=0,C0=0} = 852
                2'b01:   dout <= 10'b0010101011; // {C1=0,C0=1} = 171
                2'b10:   dout <= 10'b0101010100; // {C1=1,C0=0} = 340
                default: dout <= 10'b1010101011; // {C1=1,C0=1} = 683
            endcase
        end else begin
            if (cnt == 6'sd0 || n1_qm == 4'd4) begin
                // ケース 1: ディスパリティ==0 または N0==N1
                dout[9]   <= ~q_m[8];
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (q_m[8])
                    cnt <= cnt + two_n1 - 6'sd8;    // cnt + 2*N1 - 8
                else
                    cnt <= cnt - two_n1 + 6'sd8;    // cnt + 8 - 2*N1
            end else if ((!cnt[5] && n1_qm > 4'd4) ||
                         ( cnt[5] && n1_qm < 4'd4)) begin
                // ケース 2: ディスパリティを減らすためデータ反転
                dout[9]   <= 1'b1;
                dout[8]   <= q_m[8];
                dout[7:0] <= ~q_m[7:0];
                cnt <= cnt + qm8_x2 - two_n1 + 6'sd8; // cnt + 2*qm8 + 8 - 2*N1
            end else begin
                // ケース 3: データそのまま
                dout[9]   <= 1'b0;
                dout[8]   <= q_m[8];
                dout[7:0] <= q_m[7:0];
                cnt <= cnt + qm8_x2 + two_n1 - 6'sd10; // cnt + 2*qm8 + 2*N1 - 10
            end
        end
    end
endmodule

// ============================================================
// トップモジュール: HDMI カラーバー
// ============================================================
module hdmi_colorbar (
    input  wire clk_50m,        // 50MHz システムクロック

    // HDMI TMDS 出力 (差動) — TLVDS_OBUF 経由
    output wire tmds_d2_p,      // Red P
    output wire tmds_d2_n,      // Red N
    output wire tmds_d1_p,      // Green P
    output wire tmds_d1_n,      // Green N
    output wire tmds_d0_p,      // Blue P
    output wire tmds_d0_n,      // Blue N
    output wire tmds_clk_p,     // Clock P
    output wire tmds_clk_n,     // Clock N

    output reg  led             // PLL ロックステータス
);

    // ==========================================================
    // VGA 640×480@60Hz タイミング定数
    // ==========================================================
    localparam H_ACTIVE = 11'd640;
    localparam H_FP     = 11'd16;
    localparam H_SYNC   = 11'd96;
    localparam H_BP     = 11'd48;
    localparam H_TOTAL  = 11'd800;  // 640+16+96+48
    localparam V_ACTIVE = 10'd480;
    localparam V_FP     = 10'd10;
    localparam V_SYNC   = 10'd2;
    localparam V_BP     = 10'd33;
    localparam V_TOTAL  = 10'd525;  // 480+10+2+33

    // ==========================================================
    // PLL: 50MHz → pixel_clk + serial_clk (5x pixel_clk)
    // ==========================================================
    wire pixel_clk;
    wire serial_clk;
    wire pll_lock;

    PLL #(
        .FCLKIN(50),
        .IDIV_SEL(2),
        .FBDIV_SEL(1),
        .MDIV_SEL(30),
        .MDIV_FRAC_SEL(2),
        .ODIV0_SEL(30),
        .ODIV1_SEL(6),
        .CLKOUT0_EN("TRUE"),
        .CLKOUT1_EN("TRUE"),
        .CLKFB_SEL("INTERNAL")
    ) pll_inst (
        .CLKIN(clk_50m),
        .CLKFB(1'b0),
        .RESET(1'b0),
        .PLLPWD(1'b0),
        .RESET_I(1'b0),
        .RESET_O(1'b0),
        .ENCLK0(1'b1),
        .ENCLK1(1'b1),
        .CLKOUT0(pixel_clk),
        .CLKOUT1(serial_clk),
        .LOCK(pll_lock)
    );

    // ==========================================================
    // ビデオタイミング生成
    // ==========================================================
    reg [10:0] hc;
    reg [ 9:0] vc;

    always @(posedge pixel_clk) begin
        if (hc == H_TOTAL - 11'd1) begin
            hc <= 11'd0;
            if (vc == V_TOTAL - 10'd1)
                vc <= 10'd0;
            else
                vc <= vc + 10'd1;
        end else begin
            hc <= hc + 11'd1;
        end
    end

    // 同期信号 (負極性: アクティブ期間中 LOW)
    wire hsync = !((hc >= H_ACTIVE + H_FP) &&
                   (hc <  H_ACTIVE + H_FP + H_SYNC));
    wire vsync = !((vc >= V_ACTIVE + V_FP) &&
                   (vc <  V_ACTIVE + V_FP + V_SYNC));

    // データイネーブル
    wire de = (hc < H_ACTIVE) && (vc < V_ACTIVE);

    // ==========================================================
    // 8色カラーバー生成 (組み合わせ論理)
    // ==========================================================
    // 白 → 黄 → シアン → 緑 → マゼンタ → 赤 → 青 → 黒
    // 各バー幅: 80px (640/8)
    reg [7:0] r_out, g_out, b_out;

    always @(*) begin
        if (de) begin
            if      (hc < 11'd80)  begin r_out = 8'hFF; g_out = 8'hFF; b_out = 8'hFF; end
            else if (hc < 11'd160) begin r_out = 8'hFF; g_out = 8'hFF; b_out = 8'h00; end
            else if (hc < 11'd240) begin r_out = 8'h00; g_out = 8'hFF; b_out = 8'hFF; end
            else if (hc < 11'd320) begin r_out = 8'h00; g_out = 8'hFF; b_out = 8'h00; end
            else if (hc < 11'd400) begin r_out = 8'hFF; g_out = 8'h00; b_out = 8'hFF; end
            else if (hc < 11'd480) begin r_out = 8'hFF; g_out = 8'h00; b_out = 8'h00; end
            else if (hc < 11'd560) begin r_out = 8'h00; g_out = 8'h00; b_out = 8'hFF; end
            else                   begin r_out = 8'h00; g_out = 8'h00; b_out = 8'h00; end
        end else begin
            r_out = 8'h00;
            g_out = 8'h00;
            b_out = 8'h00;
        end
    end

    // ==========================================================
    // TMDS エンコーダ (3チャネル独立)
    // ==========================================================
    wire [9:0] tmds_r, tmds_g, tmds_b;

    // CH2: Red (コントロール: C1=0, C0=0)
    tmds_encoder enc_r (
        .clk(pixel_clk), .din(r_out), .ctrl(2'b00), .de(de), .dout(tmds_r)
    );

    // CH1: Green (コントロール: C1=0, C0=0)
    tmds_encoder enc_g (
        .clk(pixel_clk), .din(g_out), .ctrl(2'b00), .de(de), .dout(tmds_g)
    );

    // CH0: Blue (コントロール: C1=VSYNC, C0=HSYNC)
    tmds_encoder enc_b (
        .clk(pixel_clk), .din(b_out), .ctrl({vsync, hsync}), .de(de), .dout(tmds_b)
    );

    // ==========================================================
    // 10:1 DDR シリアライザ (Gowin OSER10 プリミティブ)
    // ==========================================================
    wire ser_d2, ser_d1, ser_d0, ser_ck;

    OSER10 oser_r (
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(1'b0),
        .D0(tmds_r[0]), .D1(tmds_r[1]), .D2(tmds_r[2]), .D3(tmds_r[3]),
        .D4(tmds_r[4]), .D5(tmds_r[5]), .D6(tmds_r[6]), .D7(tmds_r[7]),
        .D8(tmds_r[8]), .D9(tmds_r[9]),
        .Q(ser_d2)
    );

    OSER10 oser_g (
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(1'b0),
        .D0(tmds_g[0]), .D1(tmds_g[1]), .D2(tmds_g[2]), .D3(tmds_g[3]),
        .D4(tmds_g[4]), .D5(tmds_g[5]), .D6(tmds_g[6]), .D7(tmds_g[7]),
        .D8(tmds_g[8]), .D9(tmds_g[9]),
        .Q(ser_d1)
    );

    OSER10 oser_b (
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(1'b0),
        .D0(tmds_b[0]), .D1(tmds_b[1]), .D2(tmds_b[2]), .D3(tmds_b[3]),
        .D4(tmds_b[4]), .D5(tmds_b[5]), .D6(tmds_b[6]), .D7(tmds_b[7]),
        .D8(tmds_b[8]), .D9(tmds_b[9]),
        .Q(ser_d0)
    );

    // クロックチャネル: 1111100000 パターン (DDR ピクセルクロック再生)
    OSER10 oser_ck (
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(1'b0),
        .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
        .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
        .Q(ser_ck)
    );

    // ==========================================================
    // LVDS 差動出力バッファ (Gowin TLVDS_OBUF プリミティブ)
    // ==========================================================
    TLVDS_OBUF tlvds_d2 (.I(ser_d2), .O(tmds_d2_p), .OB(tmds_d2_n));
    TLVDS_OBUF tlvds_d1 (.I(ser_d1), .O(tmds_d1_p), .OB(tmds_d1_n));
    TLVDS_OBUF tlvds_d0 (.I(ser_d0), .O(tmds_d0_p), .OB(tmds_d0_n));
    TLVDS_OBUF tlvds_ck (.I(ser_ck), .O(tmds_clk_p), .OB(tmds_clk_n));

    // ==========================================================
    // LED: PLL ロック表示
    // ==========================================================
    always @(posedge pixel_clk) begin
        led <= pll_lock;
    end

endmodule
