package FetchUnit;

  import Common::*;
  import UnifiedMemory::*;
  import RVCExpand::*;

  interface IfcFetchUnit;
    method Action     start(Bit#(32) pc);
    method FetchSlice at(Bit#(32) pc);
  endinterface

  module mkFetchUnit#(Memory_IFC mem)(IfcFetchUnit);

    function FetchSlice slice(Bit#(32) pc);
      Bit#(32) w0     = mem.readWord(pc);
      Bit#(16) parcel = (pc[1] == 1'b1) ? w0[31:16] : w0[15:0];

      FetchSlice fs;
      if (isCompressedParcel(parcel)) begin
        fs.instr  = expandRVC(parcel);
        fs.npc    = pc + 2;
        fs.isComp = True;
      end else begin
        Bit#(16) hi = (pc[1] == 1'b1) ? mem.readWord(pc + 2)[15:0] : w0[31:16];
        fs.instr  = { hi, parcel };
        fs.npc    = pc + 4;
        fs.isComp = False;
      end
      return fs;
    endfunction

    method Action start(Bit#(32) pc);
      let fs = slice(pc);
      if (traceOn) $display("[Fetch] PC: %08x | %s | instr: %08x",
               pc, fs.isComp ? "c16" : "i32", fs.instr);
    endmethod

    method FetchSlice at(Bit#(32) pc);
      return slice(pc);
    endmethod

  endmodule

endpackage
