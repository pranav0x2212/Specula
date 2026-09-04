package Uart;

  import Common::*;
  import Vector::*;
  import FIFOF::*;

  Addr uartBase = 32'h10000000;

  interface Uart_IFC;
    method Bit#(32) readWord (Addr a);
    method Action   writeWord(Addr a, Bit#(32) data, Bit#(4) be);
    method Action   rxObserved(Bit#(8) b);   // publish the byte a committed RHR load saw
    method Bool     rxIrq();
    method Bool     dbgDlab();
  endinterface

  module mkUart(Uart_IFC);
    Reg#(Bool)                  dlab <- mkReg(False);
    Vector#(128, Reg#(Bit#(8))) lbuf <- replicateM(mkReg(0));
    Reg#(Bit#(7))               lcol <- mkReg(0);

    FIFOF#(Bit#(8))             rxq    <- mkUGSizedFIFOF(16);
    Reg#(Bool)                  rxRdy  <- mkReg(False);   // registered rxq.notEmpty
    Reg#(Bit#(8))               rxHead <- mkReg(0);       // registered rxq.first
    Wire#(Maybe#(Bit#(8)))      rxObs  <- mkDWire(tagged Invalid);  // committed-RHR byte, published by doCommit
    Reg#(Bit#(8))               nls  <- mkReg(0);
    Reg#(File)                  inf  <- mkReg(InvalidFile);
    Reg#(Bool)                  opened <- mkReg(False);

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
          nls  <= nls + 1;
        end else if (lcol < 127) begin
          lbuf[lcol] <= c;
          lcol <= lcol + 1;
        end
      endaction
    endfunction

    rule openIn (!opened);
      let f <- $fopen("uart_rx.in", "r");
      inf <= f;
      opened <= True;
    endrule

    rule mirrorRdy;
      rxRdy  <= rxq.notEmpty;
      rxHead <= rxq.first;
    endrule

    rule feedIn (opened && rxq.notFull && nls >= 4 && inf != InvalidFile);
      int c <- $fgetc(inf);
      if (c >= 0)
        rxq.enq(truncate(pack(c)));
    endrule

    rule rxConsume (isValid(rxObs));
      if (rxq.notEmpty && rxq.first == validValue(rxObs))
        rxq.deq;
    endrule

    method Bit#(32) readWord(Addr a);
      Bit#(3) off = truncate(a - uartBase);
      return (off == 0) ? (rxRdy ? zeroExtend(rxHead) : 32'h0) :
             (off == 5) ? (rxRdy ? 32'h61616161 : 32'h60606060) :
                          32'h0;
    endmethod

    method Action writeWord(Addr a, Bit#(32) data, Bit#(4) be);
      Bit#(3) off = truncate(a - uartBase);
      Bit#(8) b   = truncate(data >> {a[1:0], 3'b000});
      case (off)
        0: if (!dlab) emitByte(b);
        3: dlab <= unpack(b[7]);
        default: noAction;
      endcase
    endmethod

    method Action rxObserved(Bit#(8) b);
      rxObs <= tagged Valid b;
    endmethod

    method Bool rxIrq() = rxRdy;

    method Bool dbgDlab() = dlab;
  endmodule

endpackage
