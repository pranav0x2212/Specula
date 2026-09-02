package VirtioStub;

  import Common::*;

  Addr virtioBase = 32'h10001000;

  interface Virtio_IFC;
    method Bit#(32) readWord (Addr a);
    method Action   writeWord(Addr a, Bit#(32) data, Bit#(4) be);
  endinterface

  module mkVirtioStub(Virtio_IFC);

    method Bit#(32) readWord(Addr a);
      Bit#(7) off = truncate(a - virtioBase);
      return (case (off)
                7'h00:   32'h74726976;  // MAGIC_VALUE
                7'h04:   32'h00000001;  // VERSION
                7'h08:   32'h00000002;  // DEVICE_ID
                7'h0c:   32'h554d4551;  // VENDOR_ID
                7'h10:   32'h00000000;  // DEVICE_FEATURES
                7'h34:   32'h00000008;  // QUEUE_NUM_MAX
                default: 32'h0;
              endcase);
    endmethod

    method Action writeWord(Addr a, Bit#(32) data, Bit#(4) be);
      noAction;
    endmethod

  endmodule

endpackage
