package FetchUnit;

  import Common::*;
  import UnifiedMemory::*;
  import RVCExpand::*;
  import MMU::*;

  interface IfcFetchUnit;
    method Action     start(Bit#(32) pc, FetchSlice fs);
    method FetchSlice at(Bit#(32) pc, Bit#(32) satp, Bool paging, Bool rootOk);
  endinterface

  module mkFetchUnit#(Memory_IFC mem)(IfcFetchUnit);

    function Bit#(32) physRd(Bit#(32) a) = mem.physReadWord(a);
    function Bit#(32) rootRd(Bit#(32) a) = mem.physReadRoot(a);

    // Translate the PC, fetch 32 bits, and handle 16-bit (RVC) or 32-bit instructions
    function FetchSlice slice(Bit#(32) vpc, Bit#(32) satp, Bool paging, Bool rootOk);
      let t0 = sv32TranslateP(vpc, InstFetch, paging, rootOk, satp, rootRd, physRd);

      Bit#(32) w0     = mem.fetchWord(t0.pa);
      // Low parcel: halfword at the PC (PC may be 2-byte aligned)
      Bit#(16) parcel = (vpc[1] == 1'b1) ? w0[31:16] : w0[15:0];
      // High parcel: next halfword, may cross into the next word
      Bit#(16) hi     = (vpc[1] == 1'b1) ? mem.fetchWord(t0.pa + 4)[15:0] : w0[31:16];
      Bool     comp   = isCompressedParcel(parcel);
      // Predecode control-flow type so the predictor can redirect early
      let      pd     = predecodeCF(parcel, hi);

      return FetchSlice { instr:      comp ? expandRVC(parcel) : { hi, parcel },
                          npc:        (t0.fault || !comp) ? vpc + 4 : vpc + 2,
                          isComp:     !t0.fault && comp,
                          fault:      t0.fault,
                          faultCause: t0.cause,
                          pdJal:      pd.jal,
                          pdJalr:     pd.jalr,
                          pdCond:     pd.cond,
                          pdSer:      pd.ser,
                          pdJalImm:   pd.jalImm };
    endfunction

    // Trace-only hook for the fetched slice
    method Action start(Bit#(32) pc, FetchSlice fs);
      if (traceOn) $display("[Fetch] PC: %08x | %s | instr: %08x%s",
               pc, fs.isComp ? "c16" : "i32", fs.instr, fs.fault ? " (xlate fault)" : "");
    endmethod

    method FetchSlice at(Bit#(32) pc, Bit#(32) satp, Bool paging, Bool rootOk);
      return slice(pc, satp, paging, rootOk);
    endmethod

  endmodule

endpackage
