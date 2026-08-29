package LSU;

  import Common::*;
  import Vector::*;

  typedef 8 StoreBufferSize;
  typedef 256 MemSize;

  typedef struct {
    Bit#(32) addr;
    Bit#(32) data;
    ROBTag robTag;
    Bool valid;
  } StoreBufferEntry deriving (Bits, FShow);

  interface IfcLSU;
    method ActionValue#(Bit#(32)) load(Bit#(32) addr);
    method Action enqStore(Bit#(32) addr, Bit#(32) data, ROBTag robTag);
    method Action commitStore(ROBTag robTag);
    method Action directStore(Bit#(32) addr, Bit#(32) data);  
    method Bool storeBufferFull();
  endinterface

  module mkLSU(IfcLSU);

    
    Vector#(StoreBufferSize, Reg#(StoreBufferEntry)) storeBuffer <- replicateM(mkReg(StoreBufferEntry{
      addr: 0, data: 0, robTag: ROBTag{idx: 0}, valid: False
    }));
    
    Reg#(UInt#(4)) sbCount <- mkReg(0);

    
    Vector#(MemSize, Reg#(Bit#(32))) memory <- replicateM(mkReg(0));

    function Maybe#(UInt#(4)) findFreeSlot();
      Maybe#(UInt#(4)) result = tagged Invalid;
      for (Integer i = 0; i < valueOf(StoreBufferSize); i = i + 1) begin
        if (!storeBuffer[i].valid) begin
          result = tagged Valid fromInteger(i);
        end
      end
      return result;
    endfunction

    
    function Maybe#(Bit#(32)) queryStoreBuffer(Bit#(32) addr);
      Maybe#(Bit#(32)) result = tagged Invalid;
      for (Integer i = 0; i < valueOf(StoreBufferSize); i = i + 1) begin
        if (storeBuffer[i].valid && storeBuffer[i].addr == addr) begin
          result = tagged Valid storeBuffer[i].data;
        end
      end
      return result;
    endfunction

    method ActionValue#(Bit#(32)) load(Bit#(32) addr);
      Bit#(32) loadVal = 0;
      Maybe#(Bit#(32)) fwdVal = queryStoreBuffer(addr);
      
      if (fwdVal matches tagged Valid .val) begin
        loadVal = val;
        $display("[LSU] Load from addr=%h FORWARDED from store buffer: data=%h", addr, val);
      end else begin
        UInt#(32) addrUInt = unpack(addr);
        UInt#(9) memIdx = truncate(addrUInt >> 2);
        if (memIdx < fromInteger(valueOf(MemSize))) begin
          loadVal = memory[memIdx];
          $display("[LSU] Load from addr=%h from memory[%0d]: data=%h", addr, memIdx, loadVal);
        end else begin
          $display("[LSU] Load from addr=%h OUT OF BOUNDS", addr);
        end
      end
      
      return loadVal;
    endmethod

    method Action enqStore(Bit#(32) addr, Bit#(32) data, ROBTag robTag);
      Maybe#(UInt#(4)) slot = findFreeSlot();
      
      if (slot matches tagged Valid .idx) begin
        storeBuffer[idx] <= StoreBufferEntry {
          addr: addr,
          data: data,
          robTag: robTag,
          valid: True
        };
        sbCount <= sbCount + 1;
        $display("[LSU] Enqueued store: robTag=%0d addr=%h data=%h to slot %0d", robTag.idx, addr, data, idx);
      end else begin
        $display("[LSU] ERROR: Store buffer full for robTag=%0d", robTag.idx);
      end
    endmethod

    method Action commitStore(ROBTag robTag);
      for (Integer i = 0; i < valueOf(StoreBufferSize); i = i + 1) begin
        if (storeBuffer[i].valid && storeBuffer[i].robTag.idx == robTag.idx) begin
          UInt#(32) addrUInt = unpack(storeBuffer[i].addr);
          UInt#(9) memIdx = truncate(addrUInt >> 2);
          if (memIdx < fromInteger(valueOf(MemSize))) begin
            memory[memIdx] <= storeBuffer[i].data;
            $display("[LSU] Committed store: robTag=%0d addr=%h <- data=%h to memory[%0d]", 
                     robTag.idx, storeBuffer[i].addr, storeBuffer[i].data, memIdx);
          end else begin
            $display("[LSU] ERROR: Store to out-of-bounds addr=%h", storeBuffer[i].addr);
          end
          storeBuffer[i].valid <= False;
          sbCount <= sbCount - 1;
        end
      end
    endmethod

    method Bool storeBufferFull();
      return (sbCount >= fromInteger(valueOf(StoreBufferSize)));
    endmethod

    method Action directStore(Bit#(32) addr, Bit#(32) data);
      UInt#(32) addrUInt = unpack(addr);
      UInt#(9) memIdx = truncate(addrUInt >> 2);
      if (memIdx < fromInteger(valueOf(MemSize))) begin
        memory[memIdx] <= data;
        $display("[LSU] Direct store: addr=%h <- data=%h to memory[%0d]", addr, data, memIdx);
      end else begin
        $display("[LSU] ERROR: Store to out-of-bounds addr=%h", addr);
      end
    endmethod

  endmodule

endpackage