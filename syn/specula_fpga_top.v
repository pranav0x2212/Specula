`default_nettype none
module specula_fpga_top (
    input wire clk,
    input wire rst_n
);

    (* DONT_TOUCH = "yes" *)
    mkSpeculaCore u_core (
        .CLK   (clk),
        .RST_N (rst_n)
    );

endmodule
`default_nettype wire
