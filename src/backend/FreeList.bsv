package FreeList;

  import Common::*;
  import Vector::*;

  interface FreeList_IFC;
    method ActionValue#(Maybe#(PhysRegTag)) tryAllocate();
    method Action free(PhysRegTag tag);
    method Bool hasFree();
    method Action restoreExact(Vector#(NUM_PHYS_REGS, Bool) freeVec);
  endinterface

  module mkFreeList(FreeList_IFC);

    Vector#(NUM_PHYS_REGS, Reg#(Bool)) freelist <- replicateM(mkReg(True));
    rule init_p0;
      freelist[0] <= False;
    endrule
    
    function Bool orFn(Bool a, Bool b);
      return a || b;
    endfunction


    method ActionValue#(Maybe#(PhysRegTag)) tryAllocate();
      Vector#(8, Bool)     grpAny = newVector;
      Vector#(8, Bit#(3))  grpIdx = newVector;
      Vector#(64, Bool)    inPick = newVector;
      for (Integer g = 0; g < 8; g = g + 1) begin
        Bool below = False;
        Bit#(3) idx = 0;
        for (Integer j = 0; j < 8; j = j + 1) begin
          Bool pk = freelist[g * 8 + j] && !below;
          inPick[g * 8 + j] = pk;
          if (pk) idx = idx | fromInteger(j);
          below = below || freelist[g * 8 + j];
        end
        grpAny[g] = below;
        grpIdx[g] = idx;
      end

      Bool gBelow = False;
      Bit#(3) hi = 0;
      Bit#(3) lo = 0;
      for (Integer g = 0; g < 8; g = g + 1) begin
        Bool gs = grpAny[g] && !gBelow;
        if (gs) begin
          hi = hi | fromInteger(g);
          lo = lo | grpIdx[g];
        end
        for (Integer j = 0; j < 8; j = j + 1)
          if (gs && inPick[g * 8 + j]) freelist[g * 8 + j] <= False;
        gBelow = gBelow || grpAny[g];
      end

      return gBelow ? tagged Valid ({hi, lo}) : tagged Invalid;
    endmethod

    method Action free(PhysRegTag tag);
      freelist[tag] <= True;
    endmethod

    method Bool hasFree();
      return foldl(orFn, False, readVReg(freelist));
    endmethod

    method Action restoreExact(Vector#(NUM_PHYS_REGS, Bool) freeVec);
      for (Integer i = 1; i < valueOf(NUM_PHYS_REGS); i = i + 1)
        freelist[i] <= freeVec[i];
    endmethod

  endmodule

endpackage