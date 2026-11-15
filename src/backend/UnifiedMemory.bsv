package UnifiedMemory;

  import RegFile::*;
  import Common::*;
  import MemImage::*;

  interface Memory_IFC;
    method Bit#(32) readWord (Addr byteAddr);
    method Bit#(32) fetchWord (Addr byteAddr);
    method Action   writeWord (Addr byteAddr, Bit#(32) data, Bit#(4) be);
    method Bool     inRange  (Addr byteAddr);
    method Bit#(32) physReadWord (Addr byteAddr);
    method Bit#(32) physReadRoot (Addr byteAddr);
    method Bool     extIntReq ();
    method Action   uartRxObserved (Bit#(8) b);
  endinterface

  // True if the address falls inside RAM
  function Bool ramContains(Addr a) =
    (a >= fromInteger(memBaseAddr)) &&
    (a <  fromInteger(memBaseAddr + valueOf(MemWords) * 4));

  // Expand a 4-bit byte-enable into a 32-bit mask
  function Bit#(32) laneMask32(Bit#(4) be);
    function Bit#(8) lane(Integer i) = (be[i] == 1'b1) ? 8'hFF : 8'h00;
    return { lane(3), lane(2), lane(1), lane(0) };
  endfunction

  // Word-addressed RAM; a second copy (ptw) gives the page-table walker its own read port
  module mkMemory(Memory_IFC);

    RegFile#(Bit#(TLog#(MemWords)), Bit#(32)) rf <-
      mkRegFileLoad("image.hex", 0, fromInteger(valueOf(MemWords) - 1));
    RegFile#(Bit#(TLog#(MemWords)), Bit#(32)) ptw <-
      mkRegFileLoad("image.hex", 0, fromInteger(valueOf(MemWords) - 1));

    // Byte address -> word index relative to RAM base
    function Bit#(TLog#(MemWords)) wIdx(Addr a) =
      truncate((a - fromInteger(memBaseAddr)) >> 2);

    function Bool rng(Addr a) =
      (a >= fromInteger(memBaseAddr)) &&
      (a <  fromInteger(memBaseAddr + valueOf(MemWords) * 4));

    method Bit#(32) readWord(Addr a) = rng(a) ? rf.sub(wIdx(a)) : 32'h0;
    method Bit#(32) fetchWord(Addr a) = rng(a) ? rf.sub(wIdx(a)) : 32'h0;

    // Read-modify-write using the byte enables; keep both copies in sync
    method Action writeWord(Addr a, Bit#(32) d, Bit#(4) be);
      if (rng(a)) begin
        let old = rf.sub(wIdx(a));
        let m   = laneMask32(be);
        let nw  = (old & ~m) | (d & m);
        rf.upd (wIdx(a), nw);
        ptw.upd(wIdx(a), nw);
      end
    endmethod

    method Bool inRange(Addr a) = rng(a);

    method Bit#(32) physReadWord(Addr a) = rng(a) ? ptw.sub(wIdx(a)) : 32'h0;
    method Bit#(32) physReadRoot(Addr a) = ptw.sub(wIdx(a));

    // Plain RAM raises no interrupts
    method Bool extIntReq() = False;
    method Action uartRxObserved(Bit#(8) b) = noAction;

  endmodule

endpackage
