// ebaz4205_nes_top.v
// Top-level wrapper for NES (tarunes) on EBAZ4205 board
//
// Clock architecture:
//   - Input: 33.33MHz from board (N18)
//   - MMCM generates:
//       clk_27m  : 27.000MHz -> NES core clock + I2S clock
//       clk_135m : 135.000MHz -> TMDS serializer (5x pixel clock)
//
//   MMCM parameters (VCO = 33.333MHz * 24 / 1 = 800MHz):
//     CLKOUT0: 800 / 29.630 ≈ 27.0 MHz  (pixel clock)
//     CLKOUT1: 800 / 6      = 133.3 MHz  (TMDS serializer)
//   Note: exact 27MHz is achieved with CLKFBOUT_MULT_F=24.0, CLKOUT0_DIVIDE_F=29.630
//         For Vivado MMCM, use Clocking Wizard IP for precise configuration.
//
// NTSC composite + PWM audio (user GPIO header on adapter board):
//   COMP_DAC[2:0] -> 3-bit binary-weighted resistor DAC -> composite video
//   AUDIO_PWM     -> RC low-pass filter -> audio
//   A second MMCM + PLL cascade generates the NTSC sample clock:
//     33.333MHz x27 = 900MHz VCO, /22 = 40.909091MHz
//     40.909091MHz x21 = 859.091MHz VCO, /20 = 42.954545MHz
//     = exactly 12 x 3.579545MHz NTSC colorburst
//   (I2S output was replaced by these pins; the I2S encoder still runs
//    inside the core as the audio sample-rate pacer.)
//
// AXI BRAM interface (from PS via Block Design):
//   PS writes PRG ROM (32KB) to bram_prg_* ports before releasing nes_rst_n
//   PS writes CHR ROM (8KB) to bram_chr_* ports before releasing nes_rst_n
`timescale 1ns / 1ps

module ebaz4205_nes_top (
    // System clock (33.33MHz from board)
    input  wire        CLK,

    // HDMI TMDS output (differential)
    output wire        HDMI_CLK_P,
    output wire        HDMI_CLK_N,
    output wire [2:0]  HDMI_P,
    output wire [2:0]  HDMI_N,

    // Push buttons (active high): BTN[0]=T19 A, BTN[1]=P19 B, BTN[2]=U19 START
    // (U20/V20 of the original 5-button set are reused for the gamepad)
    input  wire [2:0]  BTN,

    // SNES/SFC gamepad (3-wire shift register interface)
    output wire        SFC_LATCH,
    output wire        SFC_CLK,
    input  wire        SFC_DATA,

    // NTSC composite video: 3-bit resistor DAC (COMP_DAC[2] = MSB)
    output wire [2:0]  COMP_DAC,

    // PWM audio output (105.5 kHz carrier, external RC filter)
    output wire        AUDIO_PWM,

    // RGB LED (active low)
    // LED_RGB[0]: MMCM locked indicator (green)
    // LED_RGB[1]: NES running indicator (blue)
    // LED_RGB[2]: unused (off)
    output wire [2:0]  LED_RGB,

    // Dual-port BRAM interface for PRG ROM (Port A: PS 32-bit, Port B: NES 8-bit)
    // Managed by Vivado Block Design / AXI BRAM Controller
    input  wire        bram_prg_clk,
    input  wire        bram_prg_en,
    input  wire [3:0]  bram_prg_we,
    input  wire [14:0] bram_prg_addr,   // word address (32-bit words)
    input  wire [31:0] bram_prg_din,
    output wire [31:0] bram_prg_dout,

    // Dual-port BRAM interface for CHR ROM (Port A: PS 32-bit, Port B: NES 8-bit)
    input  wire        bram_chr_clk,
    input  wire        bram_chr_en,
    input  wire [3:0]  bram_chr_we,
    input  wire [12:0] bram_chr_addr,   // word address (32-bit words)
    input  wire [31:0] bram_chr_din,
    output wire [31:0] bram_chr_dout,

    // NES core control from PS
    input  wire        nes_rst_n,   // active-low: PS holds low until ROM loaded
    output wire        nes_ready    // high when NES core is running
);

    //=========================================================================
    // Clock generation (MMCM)
    // Target: clk_27m = 27MHz, clk_135m = 135MHz (5x)
    // Input: 33.333MHz
    // VCO = 33.333 * 24 = 800MHz
    // CLKOUT0 = 800 / 29.630 ≈ 27.0 MHz
    // CLKOUT1 = 800 / 6 ≈ 133.3 MHz (close enough for TMDS)
    //=========================================================================
    wire clk_27m_raw, clk_135m_raw;
    wire clk_27m, clk_135m;
    wire mmcm_locked;
    wire mmcm_fb_out, mmcm_fb_in;

    MMCME2_ADV #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (30.000),       // 33.333MHz
        .CLKFBOUT_MULT_F    (24.000),       // VCO = 33.333 * 24 = 800MHz
        .DIVCLK_DIVIDE      (1),
        .CLKOUT0_DIVIDE_F   (29.630),       // 800 / 29.630 ≈ 27.0MHz
        .CLKOUT1_DIVIDE     (6),            // 800 / 6 = 133.3MHz (TMDS)
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKFBOUT_PHASE     (0.0),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE"),
        .CLKOUT4_CASCADE    ("FALSE"),
        .COMPENSATION       ("ZHOLD")
    ) mmcm_inst (
        .CLKIN1   (CLK),
        .CLKIN2   (1'b0),
        .CLKINSEL (1'b1),
        .CLKFBIN  (mmcm_fb_in),
        .CLKFBOUT (mmcm_fb_out),
        .CLKOUT0  (clk_27m_raw),
        .CLKOUT1  (clk_135m_raw),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0),
        .DADDR    (7'h0),
        .DCLK     (1'b0),
        .DEN      (1'b0),
        .DI       (16'h0),
        .DWE      (1'b0),
        .DO       (),
        .DRDY     (),
        .PSEN     (1'b0),
        .PSINCDEC (1'b0),
        .PSDONE   (),
        .CLKINSTOPPED(),
        .CLKFBSTOPPED()
    );

    BUFG bufg_fb  (.I(mmcm_fb_out),  .O(mmcm_fb_in));
    BUFG bufg_27m (.I(clk_27m_raw),  .O(clk_27m));
    BUFG bufg_135m(.I(clk_135m_raw), .O(clk_135m));

    //=========================================================================
    // Reset generation
    // Hold reset for 16 cycles after MMCM lock
    //=========================================================================
    reg [3:0] rst_cnt;
    wire      sys_rst_n;

    always @(posedge clk_27m or negedge mmcm_locked) begin
        if (!mmcm_locked)
            rst_cnt <= 4'hF;
        else if (rst_cnt != 4'h0)
            rst_cnt <= rst_cnt - 4'h1;
    end
    assign sys_rst_n = (rst_cnt == 4'h0);

    // NES core reset: held until PS asserts nes_rst_n AND MMCM is locked.
    // NOTE: tarunes uses an active-LOW synchronous reset (`if (!rst)` resets),
    // so the core runs while nes_run == 1.
    wire nes_run;
    assign nes_run   = sys_rst_n && nes_rst_n;
    assign nes_ready = nes_run;

    //=========================================================================
    // Button debounce (3 buttons)
    //=========================================================================
    wire [2:0] btn_debounced;

    genvar gi;
    generate
        for (gi = 0; gi < 3; gi = gi + 1) begin : gen_debounce
            button_debounce #(
                .DEBOUNCE_CYCLES(270000)   // ~10ms at 27MHz
            ) u_debounce (
                .clk    (clk_27m),
                .rst_n  (sys_rst_n),
                .btn_in (BTN[gi]),
                .btn_out(btn_debounced[gi])
            );
        end
    endgenerate

    //=========================================================================
    // NES button mapping + SNES/SFC gamepad (OR-merged)
    //=========================================================================
    wire [7:0] nes_buttons;
    wire [7:0] sfc_buttons;
    wire [7:0] nes_buttons_merged;

    nes_button_map u_btn_map (
        .btn_debounced(btn_debounced),
        .nes_buttons  (nes_buttons)
    );

    // Polls a SNES/SFC pad every ~1ms (83kHz shift clock) and outputs the
    // NES button byte (bit0=A ... bit7=RIGHT, matching tarunes_controller).
    // Runs from sys reset so the pad works as soon as the clocks are up.
    tarunes_sfc_controller u_sfc_pad (
        .clk      (clk_27m),
        .rst      (sys_rst_n),      // tarunes reset is active-low
        .sfc_data (SFC_DATA),
        .sfc_latch(SFC_LATCH),
        .sfc_clk  (SFC_CLK),
        .buttons  (sfc_buttons)
    );

    assign nes_buttons_merged = nes_buttons | sfc_buttons;

    //=========================================================================
    // PRG ROM BRAM (32KB)
    // Port A: PS write (32-bit wide, byte-enable)
    // Port B: NES CPU read (8-bit)
    //=========================================================================
    wire [14:0] prg_addr_core;  // 15-bit byte address from NES CPU
    wire [7:0]  prg_rdata_core;

    // Port A: 32-bit interface from PS (word-addressed)
    // Port B: 8-bit interface from NES (byte-addressed)
    // BRAM depth: 8192 words (32-bit) = 32768 bytes
    // Port A addr width: 13 bits (8192 words)
    // Port B addr width: 15 bits (32768 bytes)
    bram_tdp_32kx8 u_prg_rom (
        // Port A: PS write interface (32-bit)
        .clka (bram_prg_clk),
        .ena  (bram_prg_en),
        .wea  (bram_prg_we),
        .addra(bram_prg_addr[12:0]),  // 13-bit word address
        .dina (bram_prg_din),
        .douta(bram_prg_dout),
        // Port B: NES CPU read interface (8-bit)
        .clkb (clk_27m),
        .enb  (1'b1),
        .web  (4'b0000),
        .addrb(prg_addr_core),        // 15-bit byte address
        .dinb (32'h0),
        .doutb(prg_rdata_core)
    );

    //=========================================================================
    // CHR ROM BRAM (8KB)
    // Port A: PS write (32-bit wide, byte-enable)
    // Port B: NES PPU read (8-bit)
    //=========================================================================
    wire [12:0] chr_addr_core;  // 13-bit byte address from NES PPU
    wire [7:0]  chr_rdata_core;

    // BRAM depth: 2048 words (32-bit) = 8192 bytes
    // Port A addr width: 11 bits (2048 words)
    // Port B addr width: 13 bits (8192 bytes)
    bram_tdp_8kx8 u_chr_rom (
        // Port A: PS write interface (32-bit)
        .clka (bram_chr_clk),
        .ena  (bram_chr_en),
        .wea  (bram_chr_we),
        .addra(bram_chr_addr[10:0]),  // 11-bit word address
        .dina (bram_chr_din),
        .douta(bram_chr_dout),
        // Port B: NES PPU read interface (8-bit)
        .clkb (clk_27m),
        .enb  (1'b1),
        .web  (4'b0000),
        .addrb(chr_addr_core),        // 13-bit byte address
        .dinb (32'h0),
        .doutb(chr_rdata_core)
    );

    //=========================================================================
    // NES Core (modified tarunes top for EBAZ4205)
    //=========================================================================
    wire [7:0]  hdmi_r, hdmi_g, hdmi_b;
    wire        hdmi_hsync, hdmi_vsync, hdmi_de;
    wire [9:0]  hdmi_video_x, hdmi_video_y;
    wire [7:0]  audio_pcm;
    wire [8:0]  scanline, cycle_out;
    wire [5:0]  pixel_index;

    // frame_sync: falling edge of vsync
    reg vsync_prev;
    reg frame_sync_r;
    always @(posedge clk_27m) begin
        vsync_prev   <= hdmi_vsync;
        frame_sync_r <= vsync_prev & ~hdmi_vsync;
    end

    nes_top_ebaz4205 #(
        .ENABLE_APU   (1'b1),
        .I2S_TEST_TONE(1'b0)
    ) u_nes_core (
        .clk                     (clk_27m),
        .rst                     (nes_run),
        .frame_sync              (frame_sync_r),
        .controller1_btns        (nes_buttons_merged),
        .scanline                (scanline),
        .cycle                   (cycle_out),
        .pixel_index             (pixel_index),
        .hdmi_r                  (hdmi_r),
        .hdmi_g                  (hdmi_g),
        .hdmi_b                  (hdmi_b),
        .hdmi_hsync              (hdmi_hsync),
        .hdmi_vsync              (hdmi_vsync),
        .hdmi_de                 (hdmi_de),
        .hdmi_video_x            (hdmi_video_x),
        .hdmi_video_y            (hdmi_video_y),
        .audio_sample            (),
        .audio_pcm               (audio_pcm),
        .i2s_bclk                (),
        .i2s_lrck                (),
        .i2s_dout                (),
        .prg_addr                (prg_addr_core),
        .prg_rdata               (prg_rdata_core),
        .chr_addr                (chr_addr_core),
        .chr_rdata               (chr_rdata_core),
        .debug_cpu_pc            (),
        .logic_analizer          (),
        .debug_palette0          (),
        .debug_palette1          (),
        .debug_palette2          (),
        .debug_palette3          (),
        .debug_bg_palette_addr   (),
        .debug_bg_palette_data   (),
        .debug_palette_write     (),
        .debug_palette_write_addr(),
        .debug_palette_write_data()
    );

    //=========================================================================
    // HDMI output via rgb2dvi
    // rgb2dvi expects: vid_pData = {R[7:0], B[7:0], G[7:0]} (24-bit)
    //=========================================================================
    rgb2dvi #(
        .kGenerateSerialClk("FALSE"),  // use external 5x clock (clk_135m)
        .kClkRange         (2),        // 120-160 MHz range for TMDS
        .kRstActiveHigh    ("FALSE")   // active-low reset
    ) u_rgb2dvi (
        .TMDS_Clk_p    (HDMI_CLK_P),
        .TMDS_Clk_n    (HDMI_CLK_N),
        .TMDS_Data_p   (HDMI_P),
        .TMDS_Data_n   (HDMI_N),
        .aRst_or_aRst_n(sys_rst_n),
        .vid_pData     ({hdmi_r, hdmi_b, hdmi_g}),
        .vid_pVDE      (hdmi_de),
        .vid_pHSync    (hdmi_hsync),
        .vid_pVSync    (hdmi_vsync),
        .PixelClk      (clk_27m),
        .SerialClk     (clk_135m)
    );

    //=========================================================================
    // NTSC sample clock generation: 42.954545 MHz = 12 x colorburst (exact)
    //   Stage 1 (MMCM): 33.333MHz x 27 = 900MHz VCO, /22 = 40.909091MHz
    //   Stage 2 (PLL):  40.909091MHz x 21 = 859.091MHz VCO, /20 = 42.954545MHz
    // Two stages are needed because the required ratio 567/440 cannot be
    // reached by a single MMCM (even with fractional dividers).
    //=========================================================================
    wire clk_41m_raw, clk_41m;
    wire clk_ntsc_raw, clk_ntsc;
    wire mmcm_ntsc_fb;
    wire pll_ntsc_fb;
    wire mmcm_ntsc_locked, pll_ntsc_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKIN1_PERIOD    (30.000),        // 33.333MHz
        .CLKFBOUT_MULT_F  (27.000),        // VCO = 900MHz
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (22.000),        // 900 / 22 = 40.909091MHz
        .CLKFBOUT_PHASE   (0.0),
        .CLKOUT0_PHASE    (0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .REF_JITTER1      (0.010),
        .STARTUP_WAIT     ("FALSE")
    ) mmcm_ntsc_inst (
        .CLKIN1   (CLK),
        .CLKFBIN  (mmcm_ntsc_fb),
        .CLKFBOUT (mmcm_ntsc_fb),          // internal feedback (no phase align)
        .CLKFBOUTB(),
        .CLKOUT0  (clk_41m_raw),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .LOCKED   (mmcm_ntsc_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG bufg_41m (.I(clk_41m_raw), .O(clk_41m));

    PLLE2_BASE #(
        .BANDWIDTH      ("OPTIMIZED"),
        .CLKIN1_PERIOD  (24.444),          // 40.909091MHz
        .CLKFBOUT_MULT  (21),              // VCO = 859.091MHz
        .DIVCLK_DIVIDE  (1),
        .CLKOUT0_DIVIDE (20),              // 859.091 / 20 = 42.954545MHz
        .CLKFBOUT_PHASE (0.0),
        .CLKOUT0_PHASE  (0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .REF_JITTER1    (0.010),
        .STARTUP_WAIT   ("FALSE")
    ) pll_ntsc_inst (
        .CLKIN1  (clk_41m),
        .CLKFBIN (pll_ntsc_fb),
        .CLKFBOUT(pll_ntsc_fb),            // internal feedback
        .CLKOUT0 (clk_ntsc_raw),
        .CLKOUT1 (),
        .CLKOUT2 (),
        .CLKOUT3 (),
        .CLKOUT4 (),
        .CLKOUT5 (),
        .LOCKED  (pll_ntsc_locked),
        .PWRDWN  (1'b0),
        .RST     (~mmcm_ntsc_locked)
    );

    BUFG bufg_ntsc (.I(clk_ntsc_raw), .O(clk_ntsc));

    // Reset synchronizer for the NTSC domain
    wire ntsc_clocks_ok = mmcm_ntsc_locked & pll_ntsc_locked;
    reg [1:0] ntsc_rst_sync;
    always @(posedge clk_ntsc or negedge ntsc_clocks_ok) begin
        if (!ntsc_clocks_ok)
            ntsc_rst_sync <= 2'b00;
        else
            ntsc_rst_sync <= {ntsc_rst_sync[0], 1'b1};
    end
    wire rst_ntsc_n = ntsc_rst_sync[1];

    //=========================================================================
    // NTSC composite encoder (3-bit resistor DAC output)
    //=========================================================================
    ntsc_encoder u_ntsc (
        .clk_core        (clk_27m),
        .core_cycle      (cycle_out),
        .core_scanline   (scanline),
        .core_pixel_index(pixel_index),
        .clk_ntsc        (clk_ntsc),
        .rst_ntsc_n      (rst_ntsc_n),
        .dac_out         (COMP_DAC)
    );

    //=========================================================================
    // PWM audio: 8-bit PWM, 27MHz / 256 = 105.47 kHz carrier.
    // audio_pcm is the buffered, rate-matched (~46.9 kHz) sample stream.
    //=========================================================================
    reg [7:0] pwm_cnt;
    reg       pwm_out;
    always @(posedge clk_27m) begin
        pwm_cnt <= pwm_cnt + 8'd1;
        pwm_out <= (audio_pcm > pwm_cnt);
    end
    assign AUDIO_PWM = pwm_out;

    //=========================================================================
    // LED status (active low)
    //=========================================================================
    assign LED_RGB[0] = ~mmcm_locked;      // green: MMCM locked
    assign LED_RGB[1] = ~nes_ready;        // blue:  NES running
    assign LED_RGB[2] = ~ntsc_clocks_ok;   // red:   NTSC clocks locked

endmodule
