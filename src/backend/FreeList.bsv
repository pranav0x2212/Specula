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
      Maybe#(PhysRegTag) result = tagged Invalid;
      Bool allocated = False;

      action
        for (Integer i = 0; i < valueOf(NUM_PHYS_REGS); i = i + 1) begin
          if (!allocated && freelist[i]) begin
            freelist[i] <= False;
            result = tagged Valid fromInteger(i);
            allocated = True;
          end
        end
      endaction
      return result;
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