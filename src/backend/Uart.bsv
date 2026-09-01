package Uart;

  import Common::*;
  import Vector::*;

  Addr uartBase = 32'h10000000;

  interface Uart_IFC;
    method Bit#(32) readWord (Addr a);
    method Action   writeWord(Addr a, Bit#(32) data, Bit#(4) be);
    method Bool     dbgDlab();
  endinterface

  module mkUart(Uart_IFC);
    Reg#(Bool)                  dlab <- mkReg(False);
    Vector#(128, Reg#(Bit#(8))) lbuf <- replicateM(mkReg(0));
    Reg#(Bit#(7))               lcol <- mkReg(0);

    function Action emitByte(Bit#(8) c);
      action
        if (c == 8'h0a) begin
          $write("[UART] ");
          for (Integer i = 0; i < 128; i = i + 1) begin
            Bit#(7) ii = fromInteger(i);
            if (ii < lcol) $write("%c", lbuf[i]);
          end
          $write("\n");
          lcol <= 0;
        end else if (lcol < 127) begin
          lbuf[lcol] <= c;
          lcol <= lcol + 1;
        end
      endaction
    endfunction

    method Bit#(32) readWord(Addr a);
      Bit#(3) off = truncate(a - uartBase);
      return (off == 5) ? 32'h60606060 : 32'h0;
    endmethod

    method Action writeWord(Addr a, Bit#(32) data, Bit#(4) be);
      Bit#(3) off = truncate(a - uartBase);
      Bit#(8) b   = truncate(data >> {a[1:0], 3'b000});
      case (off)
        0: if (!dlab) emitByte(b);   // THR (DLAB=1 -> DLL, ignored)
        3: dlab <= unpack(b[7]);     // LCR bit 7 = DLAB
        default: noAction;
      endcase
    endmethod

    method Bool dbgDlab() = dlab;
  endmodule

endpackage
