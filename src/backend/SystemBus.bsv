package SystemBus;

  import Common::*;
  import UnifiedMemory::*;
  import Uart::*;
  import VirtioStub::*;

  Addr uartLo = 32'h10000000;
  Addr uartHi = 32'h10000008;

  Addr virtioLo = 32'h10001000;
  Addr virtioHi = 32'h10001080;

  module mkSystemBus(Memory_IFC);
    Memory_IFC ram    <- mkMemory;
    Uart_IFC   uart   <- mkUart;
    Virtio_IFC virtio <- mkVirtioStub;

    function Bool isUart(Addr a)   = (a >= uartLo)   && (a < uartHi);
    function Bool isVirtio(Addr a) = (a >= virtioLo) && (a < virtioHi);

    method Bit#(32) readWord(Addr a);
      return isUart(a)   ? uart.readWord(a) :
             isVirtio(a)  ? virtio.readWord(a) :
                             ram.readWord(a);
    endmethod

    method Action writeWord(Addr a, Bit#(32) d, Bit#(4) be);
      if (isUart(a))        uart.writeWord(a, d, be);
      else if (isVirtio(a)) virtio.writeWord(a, d, be);
      else                  ram.writeWord(a, d, be);
    endmethod

    method Bool inRange(Addr a) = isUart(a) || isVirtio(a) || ram.inRange(a);
  endmodule

endpackage
