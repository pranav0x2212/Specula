package UartTest;

  import Uart::*;

  module mkUartTest(Empty);
    Uart_IFC       uart  <- mkUart;
    Reg#(Bit#(8))  step  <- mkReg(0);
    Reg#(Bit#(16)) fails <- mkReg(0);

    function ActionValue#(Bit#(16)) chk(String tag, Bool ok);
      actionvalue
        if (ok) $display("[UART-TEST] ok   %s", tag);
        else    $display("[UART-TEST] FAIL %s", tag);
        return ok ? 16'd0 : 16'd1;
      endactionvalue
    endfunction

    rule run;
      Bit#(16) nf = 0;
      case (step)
        0: begin
             let a <- chk("LSR reads 0x60", uart.readWord(32'h10000005) == 32'h60606060);
             nf = a;
           end
        1: uart.writeWord(32'h10000003, 32'h80000000, 4'b1000);   // LCR <- 0x80 (set DLAB)
        2: begin
             let a <- chk("DLAB set by LCR bit7", uart.dbgDlab());
             nf = a;
             uart.writeWord(32'h10000000, 32'h00000003, 4'b0001); // offset 0 with DLAB=1 -> DLL, must not emit
           end
        3: uart.writeWord(32'h10000003, 32'h03000000, 4'b1000);   // LCR <- 0x03 (clear DLAB)
        4: begin
             let a <- chk("DLAB cleared by LCR bit7", !uart.dbgDlab());
             nf = a;
           end
        5: uart.writeWord(32'h10000000, 32'h0000004f, 4'b0001);   // 'O'
        6: uart.writeWord(32'h10000000, 32'h0000004b, 4'b0001);   // 'K'
        7: uart.writeWord(32'h10000000, 32'h0000000a, 4'b0001);   // '\n' -> flush ("[UART] OK" proves DLL was not emitted)
        default: begin
          if (fails == 0) $display("[UART-TEST] PASS - all checks ok");
          else            $display("[UART-TEST] FAIL - %0d checks wrong", fails);
          $finish(0);
        end
      endcase
      fails <= fails + nf;
      step  <= step + 1;
    endrule

  endmodule

endpackage
