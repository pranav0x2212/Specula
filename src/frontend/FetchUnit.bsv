package FetchUnit;

  import Common::*;
  import UnifiedMemory::*;
  import RVCExpand::*;
  import MMU::*;

  interface IfcFetchUnit;
    method Action     start(Bit#(32) pc, FetchSlice fs);
    method FetchSlice at(Bit#(32) pc, Bit#(32) satp, Bit#(2) priv);
  endinterface

  module mkFetchUnit#(Memory_IFC mem)(IfcFetchUnit);

    function Bit#(32) physRd(Bit#(32) a) = mem.physReadWord(a);

    function FetchSlice slice(Bit#(32) vpc, Bit#(32) satp, Bit#(2) priv);
      FetchSlice fs = FetchSlice { instr: 32'h00000013, npc: vpc + 4,
                                   isComp: False, fault: False, faultCause: 0 };

      let t0 = sv32Translate(vpc, InstFetch, priv, satp, physRd);
      if (t0.fault) begin
        fs.instr = 32'h0;
        fs.fault = True;
        fs.faultCause = t0.cause;
      end else begin
        Bit#(32) w0     = mem.readWord(t0.pa);
        Bit#(16) parcel = (vpc[1] == 1'b1) ? w0[31:16] : w0[15:0];

        if (isCompressedParcel(parcel)) begin
          fs.instr  = expandRVC(parcel);
          fs.npc    = vpc + 2;
          fs.isComp = True;
        end else begin
          Bit#(16) hi = (vpc[1] == 1'b1) ? mem.readWord(t0.pa + 4)[15:0]
                                         : w0[31:16];
          fs.instr  = { hi, parcel };
          fs.npc    = vpc + 4;
          fs.isComp = False;
        end
      end
      return fs;
    endfunction

    method Action start(Bit#(32) pc, FetchSlice fs);
      if (traceOn) $display("[Fetch] PC: %08x | %s | instr: %08x%s",
               pc, fs.isComp ? "c16" : "i32", fs.instr, fs.fault ? " (xlate fault)" : "");
    endmethod

    method FetchSlice at(Bit#(32) pc, Bit#(32) satp, Bit#(2) priv);
      return slice(pc, satp, priv);
    endmethod

  endmodule

endpackage
