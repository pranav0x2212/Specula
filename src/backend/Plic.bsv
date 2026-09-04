package Plic;

  import Common::*;

  Addr plicBase   = 32'h0c000000;
  Addr offPrio1   = 32'h00000004;   // priority[1]  (VIRTIO0_IRQ)
  Addr offPrio10  = 32'h00000028;   // priority[10] (UART0_IRQ)
  Addr offSEnable = 32'h00002080;   // PLIC_SENABLE(hart 0)   = PLIC + 0x2080
  Addr offSThresh = 32'h00201000;   // PLIC_SPRIORITY(hart 0) = PLIC + 0x201000
  Addr offSClaim  = 32'h00201004;   // PLIC_SCLAIM(hart 0)    = PLIC + 0x201004

  Integer irqVirtio = 1;
  Integer irqUart   = 10;

  interface Plic_IFC;
    method Bit#(32) readWord (Addr a);
    method Action   writeWord(Addr a, Bit#(32) data, Bit#(4) be);
    method Action   setPending(Bit#(5) src);   // VirtIO: signal one completed request
    method Bool     extReq();
  endinterface

  module mkPlic#(function Bool uartRx)(Plic_IFC);
    Reg#(Bit#(32)) prio1   <- mkReg(0);
    Reg#(Bit#(32)) prio10  <- mkReg(0);
    Reg#(Bit#(32)) senable <- mkReg(0);
    Reg#(Bit#(32)) sthresh <- mkReg(0);
    Reg#(Bit#(32)) pending <- mkReg(0);

    Reg#(Bit#(16)) virtioDone <- mkReg(0);
    Reg#(Bit#(16)) virtioAck  <- mkReg(0);
    Bool virtioLevel = (virtioDone != virtioAck);

    function Bool active(Integer src, Bit#(32) prio, Bool lvl);
      Bit#(32) b = 32'b1 << src;
      return (((pending & b) != 0) || lvl) && ((senable & b) != 0) && (prio > sthresh);
    endfunction

    function Bit#(32) claimId();
      return active(irqVirtio, prio1,  virtioLevel) ? fromInteger(irqVirtio) :
             active(irqUart,   prio10, uartRx)      ? fromInteger(irqUart)   :
             32'd0;
    endfunction

    method Bit#(32) readWord(Addr a);
      Addr off = a - plicBase;
      return (off == offSClaim)  ? claimId()  :
             (off == offSEnable) ? senable    :
             (off == offSThresh) ? sthresh    :
             (off == offPrio1)   ? prio1      :
             (off == offPrio10)  ? prio10     :
             32'h0;
    endmethod

    method Action writeWord(Addr a, Bit#(32) data, Bit#(4) be);
      Addr off = a - plicBase;
      if      (off == offPrio1)   prio1   <= data;
      else if (off == offPrio10)  prio10  <= data;
      else if (off == offSEnable) senable <= data;
      else if (off == offSThresh) sthresh <= data;
      else if (off == offSClaim) begin
        if (data[4:0] == fromInteger(irqVirtio)) virtioAck <= virtioAck + 1;
        else                                     pending   <= pending & ~(32'b1 << data[4:0]);
      end
      else noAction;
    endmethod

    method Action setPending(Bit#(5) src);
      virtioDone <= virtioDone + 1;
    endmethod

    method Bool extReq() = (claimId() != 0);
  endmodule

endpackage
