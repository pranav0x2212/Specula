package MemQueue;

  import Common::*;
  import Vector::*;

  typedef 8 MEMQ_SIZE;
  typedef UInt#(TLog#(MEMQ_SIZE)) MemQIdx;

  typedef struct {
    Bool       isLoad;
    Bool       isAmo;
    PhysRegTag base;
    PhysRegTag sdata;
    Data       imm;
    PhysRegTag dest;
    Bit#(3)    funct3;
    ROBTag     robTag;
  } MemQEntry deriving (Bits, FShow);

  interface MemQueue_IFC;
    method Action enq(MemQEntry e);
    method Bool notFull;
    method Bool notEmpty;
    method Vector#(MEMQ_SIZE, Bool) validMask;
    method Vector#(MEMQ_SIZE, MemQEntry) peekAll;
    method Action issue(MemQIdx i);
    method Action flush();
  endinterface

  module mkMemQueue(MemQueue_IFC);
    Vector#(MEMQ_SIZE, Reg#(MemQEntry))    payload <- replicateM(mkRegU);
    Vector#(MEMQ_SIZE, Array#(Reg#(Bool))) valid   <- replicateM(mkCReg(3, False));

    function Maybe#(MemQIdx) firstFree();
      Maybe#(MemQIdx) r = tagged Invalid;
      for (Integer i = valueOf(MEMQ_SIZE) - 1; i >= 0; i = i - 1)
        if (!valid[i][1]) r = tagged Valid fromInteger(i);
      return r;
    endfunction

    method Action enq(MemQEntry e);
      let f = firstFree();
      if (f matches tagged Valid .idx) begin
        payload[idx]  <= e;
        valid[idx][1] <= True;
        if (traceOn) $display("[MEMQ] enq %s rob=%0d base=p%0d sdata=p%0d dest=p%0d imm=%0d funct3=%b",
                 e.isAmo ? "amoswap" : (e.isLoad ? "load" : "store"), e.robTag.idx, e.base, e.sdata, e.dest, e.imm, e.funct3);
      end else
        $display("[MEMQ] enq FAILED: full");
    endmethod

    method Bool notFull = isValid(firstFree());

    method Bool notEmpty;
      Bool any = False;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1)
        if (valid[i][0]) any = True;
      return any;
    endmethod

    method Vector#(MEMQ_SIZE, Bool) validMask;
      Vector#(MEMQ_SIZE, Bool) v = newVector;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1)
        v[i] = valid[i][0];
      return v;
    endmethod

    method Vector#(MEMQ_SIZE, MemQEntry) peekAll;
      Vector#(MEMQ_SIZE, MemQEntry) v = newVector;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1)
        v[i] = payload[i];
      return v;
    endmethod

    method Action issue(MemQIdx i);
      valid[i][0] <= False;
      if (traceOn) $display("[MEMQ] issue slot %0d (rob=%0d)", i, payload[i].robTag.idx);
    endmethod

    method Action flush();
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1)
        valid[i][2] <= False;
      if (traceOn) $display("[MEMQ] flushed");
    endmethod

  endmodule

endpackage
