package SystemBus;

  import Common::*;
  import UnifiedMemory::*;
  import Uart::*;

  Addr uartLo = 32'h10000000;
  Addr uartHi = 32'h10000008;

  module mkSystemBus(Memory_IFC);
    Memory_IFC ram  <- mkMemory;
    Uart_IFC   uart <- mkUart;

    function Bool isUart(Addr a) = (a >= uartLo) && (a < uartHi);

    method Bit#(32) readWord(Addr a);
      return isUart(a) ? uart.readWord(a) : ram.readWord(a);
    endmethod

    method Action writeWord(Addr a, Bit#(32) d, Bit#(4) be);
      if (isUart(a)) uart.writeWord(a, d, be);
      else           ram.writeWord(a, d, be);
    endmethod

    method Bool inRange(Addr a) = isUart(a) || ram.inRange(a);
  endmodule

endpackage
