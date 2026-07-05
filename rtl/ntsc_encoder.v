// ntsc_encoder.v
// NTSC composite video encoder for the EBAZ4205 NES port.
//
// Generates a 262-line progressive ("240p", same as a real NES) NTSC
// composite signal from the NES PPU pixel-index stream, using the same
// square-wave chroma scheme as the real 2C02 PPU
// (see NESdev wiki: "NTSC video").
//
// Clocking:
//   clk_core : 27 MHz NES/PPU domain (framebuffer write side)
//   clk_ntsc : 42.954545 MHz = 12 x 3.579545 MHz colorburst (exact).
//              Each clock is 1/12 of a subcarrier period. Each NES pixel
//              lasts 8 clocks (5.3695 MHz dot rate), each line is
//              341 pixel slots = 2728 clocks (63.51 us), 262 lines per
//              frame -> 60.10 Hz, identical to a real NTSC NES.
//
// The PPU renders into the internal framebuffer paced by the HDMI scaler
// (59.94 Hz) while this encoder scans out at 60.10 Hz, so a slowly moving
// tear line can appear on the composite output. This is cosmetic; making
// the NTSC vsync the core frame_sync source would remove it (at the cost
// of moving the tear to the HDMI output instead).
//
// Output: 3-bit unsigned level for an external binary-weighted resistor
// DAC. dac_out[2] is the MSB (smallest / half-impedance resistor).
// The mapping assumes the DAC produces ~1.1 V full scale (code 7) into
// the 75 ohm TV termination, i.e. ~0.157 V per step:
//
//   2C02 signal      volts   3-bit code
//   ---------------  -----   ----------
//   sync tip         0.048   0
//   colorburst low   0.148   1
//   blank / black    0.312   2
//   colorburst high  0.524   3
//   luma low  0..3   0.228, 0.312, 0.552, 0.880  ->  1, 2, 4, 6
//   luma high 0..3   0.616, 0.840, 1.100, 1.100  ->  4, 5, 7, 7

`timescale 1ns / 1ps

module ntsc_encoder (
    // Write side: NES PPU pixel stream (core clock domain)
    input  wire        clk_core,
    input  wire [8:0]  core_cycle,
    input  wire [8:0]  core_scanline,
    input  wire [5:0]  core_pixel_index,

    // Read side: NTSC sample clock domain (42.954545 MHz)
    input  wire        clk_ntsc,
    input  wire        rst_ntsc_n,
    output reg  [2:0]  dac_out
);

    //=========================================================================
    // Timing constants (in 42.954545 MHz samples, 23.28 ns each)
    //=========================================================================
    localparam integer H_TOTAL       = 2728;             // 341 pixel slots * 8
    localparam integer H_SYNC_END    = 200;              // 4.66 us hsync
    localparam integer H_BURST_START = 218;              // 0.42 us breezeway
    localparam integer H_BURST_END   = 326;              // 9 subcarrier cycles
    localparam integer H_ACT_START   = 384;              // 8.9 us after sync edge
    localparam integer H_ACT_END     = H_ACT_START + 256*8;
    localparam integer H_HALF        = 1364;             // half line (broad pulses)

    localparam integer V_TOTAL       = 262;
    localparam integer V_SYNC_END    = 3;                // lines 0-2: vsync
    localparam integer V_ACT_START   = 20;               // picture: lines 20-259
    localparam integer V_ACT_END     = V_ACT_START + 240;

    // 3-bit composite levels (see header table)
    localparam [2:0] LVL_SYNC    = 3'd0;
    localparam [2:0] LVL_BLANK   = 3'd2;
    localparam [2:0] LVL_BURST_L = 3'd1;
    localparam [2:0] LVL_BURST_H = 3'd3;

    //=========================================================================
    // Framebuffer: 256x240 x 6-bit palette index.
    // Simple dual-port, dual-clock BRAM: PPU writes at 27 MHz, NTSC
    // scanout reads at 42.95 MHz. The BRAM primitive handles the CDC.
    //=========================================================================
    (* ram_style = "block" *) reg [5:0] fb [0:256*240-1];

    wire        wr_en   = (core_cycle < 9'd256) && (core_scanline < 9'd240);
    wire [15:0] wr_addr = {core_scanline[7:0], core_cycle[7:0]};

    always @(posedge clk_core) begin
        if (wr_en) begin
            fb[wr_addr] <= core_pixel_index;
        end
    end

    //=========================================================================
    // NTSC sample / line counters and free-running subcarrier phase
    //=========================================================================
    reg [11:0] hcnt;    // 0 .. H_TOTAL-1
    reg [8:0]  vcnt;    // 0 .. V_TOTAL-1
    reg [3:0]  phase;   // subcarrier phase, 1/12 cycle per clock, free-running

    always @(posedge clk_ntsc) begin
        if (!rst_ntsc_n) begin
            hcnt  <= 12'd0;
            vcnt  <= 9'd0;
            phase <= 4'd0;
        end else begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= 12'd0;
                vcnt <= (vcnt == V_TOTAL - 1) ? 9'd0 : vcnt + 9'd1;
            end else begin
                hcnt <= hcnt + 12'd1;
            end
            phase <= (phase == 4'd11) ? 4'd0 : phase + 4'd1;
        end
    end

    // 2C02 chroma square wave: wave(phase, color) = ((color + phase) % 12) < 6
    function chroma_wave;
        input [3:0] ph;
        input [3:0] hue;
        reg   [4:0] s;
        begin
            s = {1'b0, ph} + {1'b0, hue};        // 0..23 (hue <= 12 here)
            if (s >= 5'd12) s = s - 5'd12;
            chroma_wave = (s < 5'd6);
        end
    endfunction

    // 2C02 luma levels quantized to the 3-bit DAC
    function [2:0] luma_lo;
        input [1:0] l;
        case (l)
            2'd0: luma_lo = 3'd1;   // 0.228 V
            2'd1: luma_lo = 3'd2;   // 0.312 V
            2'd2: luma_lo = 3'd4;   // 0.552 V
            2'd3: luma_lo = 3'd6;   // 0.880 V
        endcase
    endfunction

    function [2:0] luma_hi;
        input [1:0] l;
        case (l)
            2'd0: luma_hi = 3'd4;   // 0.616 V
            2'd1: luma_hi = 3'd5;   // 0.840 V
            2'd2: luma_hi = 3'd7;   // 1.100 V
            2'd3: luma_hi = 3'd7;   // 1.100 V
        endcase
    endfunction

    //=========================================================================
    // Framebuffer scanout (2-cycle read pipeline; the ~47 ns skew vs. the
    // blanking flags is far below anything visible)
    //=========================================================================
    wire        active_h = (hcnt >= H_ACT_START) && (hcnt < H_ACT_END);
    wire        active_v = (vcnt >= V_ACT_START) && (vcnt < V_ACT_END);
    wire [11:0] act_off  = hcnt - H_ACT_START;
    wire [7:0]  pix_x    = act_off[10:3];              // 8 samples per pixel
    wire [8:0]  row9     = vcnt - V_ACT_START;
    wire [7:0]  pix_y    = row9[7:0];

    reg  [15:0] rd_addr;
    reg  [5:0]  rd_pix;
    reg         show_d1, show_d2;

    always @(posedge clk_ntsc) begin
        rd_addr <= {pix_y, pix_x};
        rd_pix  <= fb[rd_addr];
        show_d1 <= active_h && active_v;
        show_d2 <= show_d1;
    end

    //=========================================================================
    // Composite level generation
    //=========================================================================
    wire [3:0] hue = rd_pix[3:0];
    wire [1:0] lum = rd_pix[5:4];

    wire in_vsync = (vcnt < V_SYNC_END);
    wire in_hsync = (hcnt < H_SYNC_END);
    wire in_burst = (hcnt >= H_BURST_START) && (hcnt < H_BURST_END);
    // vsync broad pulses: sync level with a 4.66 us serration at the end
    // of each half line
    wire serration = ((hcnt >= H_HALF - H_SYNC_END) && (hcnt < H_HALF)) ||
                     (hcnt >= H_TOTAL - H_SYNC_END);

    wire burst_hi = chroma_wave(phase, 4'd8);   // colorburst = color 8 phase
    wire pix_hi   = chroma_wave(phase, hue);

    reg [2:0] pix_level;
    always @* begin
        if (hue == 4'd0)                       // $x0: no chroma, high level
            pix_level = luma_hi(lum);
        else if (hue <= 4'd12)                 // $x1-$xC: chroma square wave
            pix_level = pix_hi ? luma_hi(lum) : luma_lo(lum);
        else if (hue == 4'd13)                 // $xD: no chroma, low level
            pix_level = luma_lo(lum);
        else                                   // $xE/$xF: black
            pix_level = LVL_BLANK;
    end

    always @(posedge clk_ntsc) begin
        if (!rst_ntsc_n) begin
            dac_out <= LVL_BLANK;
        end else if (in_vsync) begin
            dac_out <= serration ? LVL_BLANK : LVL_SYNC;
        end else if (in_hsync) begin
            dac_out <= LVL_SYNC;
        end else if (in_burst) begin
            dac_out <= burst_hi ? LVL_BURST_H : LVL_BURST_L;
        end else if (show_d2) begin
            dac_out <= pix_level;
        end else begin
            dac_out <= LVL_BLANK;
        end
    end

endmodule
