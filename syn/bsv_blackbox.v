(* black_box *)
module RegFileLoad #(
    parameter file       = "",
    parameter addr_width = 1,
    parameter data_width = 1,
    parameter lo         = 0,
    parameter hi         = 1,
    parameter binary     = 0
) (
    input                   CLK,
    input  [addr_width-1:0] ADDR_IN, ADDR_1, ADDR_2, ADDR_3, ADDR_4, ADDR_5,
    input  [data_width-1:0] D_IN,
    input                   WE,
    output [data_width-1:0] D_OUT_1, D_OUT_2, D_OUT_3, D_OUT_4, D_OUT_5
);
endmodule
