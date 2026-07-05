// system_top.v
// True top level for the EBAZ4205 NES design.
//
// Stitches together:
//   - zynq_ps_bd_wrapper : Block Design (Zynq PS, AXI BRAM controllers,
//                          EMIO GPIO for NES control)
//   - ebaz4205_nes_top   : all PL logic (NES core, HDMI, NTSC composite,
//                          PWM audio, buttons, LEDs)
//
// The DDR / FIXED_IO ports are the Zynq PS hard pins and are passed
// through to the BD wrapper untouched.

`timescale 1ns / 1ps

module system_top (
    // Zynq PS DDR / fixed IO
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // Board / adapter board IO
    input  wire        CLK,          // 33.33MHz PL clock (N18)
    output wire        HDMI_CLK_P,
    output wire        HDMI_CLK_N,
    output wire [2:0]  HDMI_P,
    output wire [2:0]  HDMI_N,
    input  wire [4:0]  BTN,
    output wire [2:0]  COMP_DAC,     // NTSC composite 3-bit resistor DAC
    output wire        AUDIO_PWM,    // PWM audio
    output wire [2:0]  LED_RGB
);

    // PS <-> PL BRAM loader interface
    wire        bram_prg_clk, bram_prg_en;
    wire [3:0]  bram_prg_we;
    wire [14:0] bram_prg_addr;
    wire [31:0] bram_prg_din, bram_prg_dout;

    wire        bram_chr_clk, bram_chr_en;
    wire [3:0]  bram_chr_we;
    wire [12:0] bram_chr_addr;
    wire [31:0] bram_chr_din, bram_chr_dout;

    wire        nes_rst_n;
    wire        nes_ready;

    zynq_ps_bd_wrapper u_ps (
        .DDR_addr         (DDR_addr),
        .DDR_ba           (DDR_ba),
        .DDR_cas_n        (DDR_cas_n),
        .DDR_ck_n         (DDR_ck_n),
        .DDR_ck_p         (DDR_ck_p),
        .DDR_cke          (DDR_cke),
        .DDR_cs_n         (DDR_cs_n),
        .DDR_dm           (DDR_dm),
        .DDR_dq           (DDR_dq),
        .DDR_dqs_n        (DDR_dqs_n),
        .DDR_dqs_p        (DDR_dqs_p),
        .DDR_odt          (DDR_odt),
        .DDR_ras_n        (DDR_ras_n),
        .DDR_reset_n      (DDR_reset_n),
        .DDR_we_n         (DDR_we_n),
        .FIXED_IO_ddr_vrn (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio     (FIXED_IO_mio),
        .FIXED_IO_ps_clk  (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .bram_prg_clk     (bram_prg_clk),
        .bram_prg_en      (bram_prg_en),
        .bram_prg_we      (bram_prg_we),
        .bram_prg_addr    (bram_prg_addr),
        .bram_prg_din     (bram_prg_din),
        .bram_prg_dout    (bram_prg_dout),
        .bram_chr_clk     (bram_chr_clk),
        .bram_chr_en      (bram_chr_en),
        .bram_chr_we      (bram_chr_we),
        .bram_chr_addr    (bram_chr_addr),
        .bram_chr_din     (bram_chr_din),
        .bram_chr_dout    (bram_chr_dout),
        .nes_rst_n        (nes_rst_n),
        .nes_ready        (nes_ready)
    );

    ebaz4205_nes_top u_pl (
        .CLK          (CLK),
        .HDMI_CLK_P   (HDMI_CLK_P),
        .HDMI_CLK_N   (HDMI_CLK_N),
        .HDMI_P       (HDMI_P),
        .HDMI_N       (HDMI_N),
        .BTN          (BTN),
        .COMP_DAC     (COMP_DAC),
        .AUDIO_PWM    (AUDIO_PWM),
        .LED_RGB      (LED_RGB),
        .bram_prg_clk (bram_prg_clk),
        .bram_prg_en  (bram_prg_en),
        .bram_prg_we  (bram_prg_we),
        .bram_prg_addr(bram_prg_addr),
        .bram_prg_din (bram_prg_din),
        .bram_prg_dout(bram_prg_dout),
        .bram_chr_clk (bram_chr_clk),
        .bram_chr_en  (bram_chr_en),
        .bram_chr_we  (bram_chr_we),
        .bram_chr_addr(bram_chr_addr),
        .bram_chr_din (bram_chr_din),
        .bram_chr_dout(bram_chr_dout),
        .nes_rst_n    (nes_rst_n),
        .nes_ready    (nes_ready)
    );

endmodule
