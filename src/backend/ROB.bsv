package ROB;

import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Common::*;
import RenameStage::*;

typedef 64 NumEntries;

typedef struct {
  ROBTag tag;
  Maybe#(RegIndex) dst;
  Maybe#(PhysRegTag) physDst;
  Maybe#(PhysRegTag) oldPhysDst;
  Bool completed;
  Data data;
  Bool isStore;
  Addr memAddr;        
  Bool isBranch;
  Bool mispredicted;
  Addr redirectPC;
} ROBEntry deriving (Bits, FShow);

interface ROB_IFC;
  method Bool canAllocate();
  method Bool isEmpty();
  method ActionValue#(ROBTag) allocate(Maybe#(RegIndex) dst, Maybe#(PhysRegTag) physDst, Maybe#(PhysRegTag) oldPhysDst, Bool isStore, Bool startCompleted, Bool isBranch);
  method Action writeResult(ROBTag tag, Data data);
  method Action markCompleted(ROBTag tag);
  method Action writeResultAndMark(ROBTag tag, Data data);
  method Action completeEntry(ROBTag tag, Data data, Addr memAddr, Bool mispredicted, Addr redirectPC);
  method Maybe#(Tuple2#(ROBTag, ROBEntry)) peekHead();
  method ROBTag headTag();     
  method Action commitHead(RenameStage_IFC rename);
  method Action flushAll();
endinterface

module mkROB(ROB_IFC);

  Vector#(NumEntries, Reg#(ROBEntry)) robEntries <- replicateM(mkRegU);
  Vector#(NumEntries, Reg#(Bool)) completionFlags <- replicateM(mkReg(False));
  Reg#(UInt#(6)) head <- mkReg(0);
  Reg#(UInt#(6)) tail <- mkReg(0);
  Reg#(UInt#(7)) count <- mkReg(0); 

  function ROBTag mkTag(UInt#(6) idx);
    return ROBTag { idx: idx };
  endfunction

  method Bool canAllocate();
    return (count < fromInteger(valueOf(NumEntries)));
  endmethod

  method Bool isEmpty();
    return (count == 0);
  endmethod

  method ActionValue#(ROBTag) allocate(Maybe#(RegIndex) dst, Maybe#(PhysRegTag) physDst, Maybe#(PhysRegTag) oldPhysDst, Bool isStore, Bool startCompleted, Bool isBranch);
    if (!(count < fromInteger(valueOf(NumEntries))))
      $fatal(1, "ROB full!");

    let tag = mkTag(tail);
    robEntries[tail] <= ROBEntry {
      tag: tag,
      dst: dst,
      physDst: physDst,
      oldPhysDst: oldPhysDst,
      completed: False,
      data: unpack(0),
      isStore: isStore,
      memAddr: 0,
      isBranch: isBranch,
      mispredicted: False,
      redirectPC: 0
    };
    completionFlags[tail] <= startCompleted;
    tail <= tail + 1;
    count <= count + 1;
    return tag;
  endmethod

  method Action writeResult(ROBTag tag, Data data);
    robEntries[tag.idx].data <= data;
  endmethod

  method Action markCompleted(ROBTag tag);
    completionFlags[tag.idx] <= True;
  endmethod

  method Action writeResultAndMark(ROBTag tag, Data data);
    robEntries[tag.idx].data <= data;
    completionFlags[tag.idx] <= True;
  endmethod

  method Action completeEntry(ROBTag tag, Data data, Addr memAddr, Bool mispredicted, Addr redirectPC);
    let e = robEntries[tag.idx];
    e.data         = data;
    e.memAddr      = memAddr;
    e.mispredicted = mispredicted;
    e.redirectPC   = redirectPC;
    robEntries[tag.idx] <= e;
    completionFlags[tag.idx] <= True;
  endmethod

  method Maybe#(Tuple2#(ROBTag, ROBEntry)) peekHead();
    Maybe#(Tuple2#(ROBTag, ROBEntry)) result = tagged Invalid;
    if (count > 0) begin
      let entry = robEntries[head];
      let completedEntry = ROBEntry {
        tag: entry.tag,
        dst: entry.dst,
        physDst: entry.physDst,
        oldPhysDst: entry.oldPhysDst,
        completed: completionFlags[head],
        data: entry.data,
        isStore: entry.isStore,
        memAddr: entry.memAddr,
        isBranch: entry.isBranch,
        mispredicted: entry.mispredicted,
        redirectPC: entry.redirectPC
      };
      result = tagged Valid tuple2(entry.tag, completedEntry);
    end
    return result;
  endmethod

  method ROBTag headTag();
    return mkTag(head);
  endmethod

  method Action commitHead(RenameStage_IFC rename);
    if (count > 0 && completionFlags[head]) begin
      if (robEntries[head].oldPhysDst matches tagged Valid .oldPhysReg) begin
        rename.freeReg(oldPhysReg);
        $display("[ROB] Committing ROB[%0d]: freed old physical register p%0d", head, oldPhysReg);
      end else begin
        $display("[ROB] Committing ROB[%0d]: no old physical register to free", head);
      end
      
      head <= head + 1;
      count <= count - 1;
    end
  endmethod

  method Action flushAll();
    head  <= 0;
    tail  <= 0;
    count <= 0;
    $display("[ROB] flushed all entries");
  endmethod

endmodule

endpackage