// nes_button_map.v
// Maps EBAZ4205 adapter board buttons (3 used) to NES controller buttons.
//
// Bit order required by tarunes_controller ($4016 returns bit 0 first and
// shifts right):
//   bit0=A, bit1=B, bit2=SELECT, bit3=START,
//   bit4=UP, bit5=DOWN, bit6=LEFT, bit7=RIGHT
// (The previous version had this reversed - A on bit 7 - so the board
//  buttons acted as directions instead of A/B/SELECT/START.)
//
// EBAZ4205 button assignment:
//   BTN[0] (T19) -> A
//   BTN[1] (P19) -> B
//   BTN[2] (U19) -> START
//
// SELECT and the D-pad come from the SNES/SFC gamepad, which is OR-merged
// with these buttons in ebaz4205_nes_top. (U20/V20, previously BTN[2] and
// BTN[4], are reused as the gamepad CLK/DATA pins.)
`timescale 1ns / 1ps

module nes_button_map (
    input  wire [2:0] btn_debounced,  // debounced button inputs
    output wire [7:0] nes_buttons     // NES button byte for controller1
);
    assign nes_buttons = {
        1'b0,              // bit7: RIGHT (gamepad only)
        1'b0,              // bit6: LEFT  (gamepad only)
        1'b0,              // bit5: DOWN  (gamepad only)
        1'b0,              // bit4: UP    (gamepad only)
        btn_debounced[2],  // bit3: START  <- BTN[2] (U19)
        1'b0,              // bit2: SELECT (gamepad only)
        btn_debounced[1],  // bit1: B      <- BTN[1] (P19)
        btn_debounced[0]   // bit0: A      <- BTN[0] (T19)
    };
endmodule
