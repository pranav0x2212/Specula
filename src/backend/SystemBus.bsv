package SystemBus;

  import Common::*;
  import UnifiedMemory::*;
  import Uart::*;
  import VirtioStub::*;
  import Plic::*;

  // Memory map: UART, VirtIO-blk and PLIC; everything else goes to RAM
  Addr uartLo = 32'h10000000;
  Addr uartHi = 32'h10000008;

  Addr virtioLo = 32'h10001000;
  Addr virtioHi = 32'h10001080;

  Addr plicLo = 32'h0c000000;
  Addr plicHi = 32'h0c400000;

  // Address decoder that routes accesses to RAM or an MMIO device
  module mkSystemBus(Memory_IFC);
    Memory_IFC ram    <- mkMemory;
    Uart_IFC   uart   <- mkUart;
    Plic_IFC   plic   <- mkPlic(uart.rxIrq);
    // VirtIO DMAs directly into RAM and raises its IRQ through the PLIC
    Virtio_IFC virtio <- mkVirtioBlk(ram, plic);

    function Bool isUart(Addr a)   = (a >= uartLo)   && (a < uartHi);
    function Bool isVirtio(Addr a) = (a >= virtioLo) && (a < virtioHi);
    function Bool isPlic(Addr a)   = (a >= plicLo)   && (a < plicHi);

    method Bit#(32) readWord(Addr a);
      return isUart(a)   ? uart.readWord(a)   :
             isVirtio(a) ? virtio.readWord(a) :
             isPlic(a)   ? plic.readWord(a)   :
                           ram.readWord(a);
    endmethod

    // Instruction fetch only ever reads RAM
    method Bit#(32) fetchWord(Addr a) = ram.fetchWord(a);

    method Action writeWord(Addr a, Bit#(32) d, Bit#(4) be);
      if      (isUart(a))   uart.writeWord(a, d, be);
      else if (isVirtio(a)) virtio.writeWord(a, d, be);
      else if (isPlic(a))   plic.writeWord(a, d, be);
      else                  ram.writeWord(a, d, be);
    endmethod

    method Bool inRange(Addr a) = isUart(a) || isVirtio(a) || isPlic(a) || ram.inRange(a);
    method Bit#(32) physReadWord(Addr a) = ram.physReadWord(a);
    method Bit#(32) physReadRoot(Addr a) = ram.physReadRoot(a);
    // External-interrupt line comes from the PLIC
    method Bool extIntReq() = plic.extReq();
    method Action uartRxObserved(Bit#(8) b) = uart.rxObserved(b);
  endmodule

endpackage
