package RenameStage;

  import Common::*;
  import Vector::*;
  import FreeList::*;

  interface RenameStage_IFC;
    method Action start(Decoded d);
    method Decoded getCurrent();
    method ActionValue#(Tuple3#(PhysRegTag, Maybe#(PhysRegTag), Bool)) allocateDestReg(RegIndex rd);
    method Action updateMapping(RegIndex rd, PhysRegTag physTag);
    method PhysRegTag lookupMapping(RegIndex r);
    method Bool isWritten(RegIndex r);
    method Action freeReg(PhysRegTag tag);
    // `alloc` carries the (rd, physTag) allocated for the control-flow instruction
    // that is taking this checkpoint, so the snapshot reflects post-allocation
    // state (its rd mapping and its physreg marked in-use). tagged Invalid when
    // the instruction has no destination (conditional branch, JAL x0, JALR x0).
    method Action checkpoint(Maybe#(Tuple2#(RegIndex, PhysRegTag)) alloc);
    method Action restoreCheckpoint();
  endinterface

  module mkRenameStage(RenameStage_IFC);
    Vector#(32, Reg#(PhysRegTag)) archRegMap <- replicateM(mkReg(0));
    Vector#(32, Reg#(Bool)) archRegWritten <- replicateM(mkReg(False));
    FreeList_IFC freelist <- mkFreeList;

    Reg#(Decoded) currentInstr <- mkRegU;
    Reg#(Vector#(32, PhysRegTag))            shadowMap     <- mkRegU;
    Reg#(Vector#(32, Bool))                  shadowWritten <- mkRegU;
    Reg#(Vector#(NUM_PHYS_REGS, Bool))       shadowFree    <- mkRegU;

    method Action start(Decoded d);
      currentInstr <= d;
      $display("[RENAME] Storing decoded instr: opcode=%0d rd=x%0d rs1=x%0d", d.opcode, d.rd, d.rs1);
    endmethod

    method Decoded getCurrent();
      return currentInstr;
    endmethod

    method ActionValue#(Tuple3#(PhysRegTag, Maybe#(PhysRegTag), Bool)) allocateDestReg(RegIndex rd);
      PhysRegTag destTag = 0;
      Maybe#(PhysRegTag) oldPhysDst = tagged Invalid;
      Bool success = True;
      
      if (rd != 0) begin
        let allocResult <- freelist.tryAllocate();
        if (allocResult matches tagged Valid .tag) begin
          destTag = tag;
          if (archRegWritten[rd]) begin
            PhysRegTag oldReg = archRegMap[rd];
            oldPhysDst = tagged Valid oldReg;
          end
          archRegMap[rd] <= destTag;
          archRegWritten[rd] <= True;
          $display("[RENAME] Allocated p%0d for x%0d", tag, rd);
        end else begin
          success = False;
          $display("[RENAME] No free physical registers for x%0d", rd);
        end
      end else begin
        destTag = 0;
      end
      
      return tuple3(destTag, oldPhysDst, success);
    endmethod

    method Action updateMapping(RegIndex rd, PhysRegTag physTag);
      if (rd != 0) begin
        archRegMap[rd] <= physTag;
        archRegWritten[rd] <= True;
        $display("[RENAME] Updated mapping: x%0d -> p%0d", rd, physTag);
      end
    endmethod

    method PhysRegTag lookupMapping(RegIndex r);
      return archRegMap[r];
    endmethod

    method Bool isWritten(RegIndex r);
      return (r == 0) ? True : archRegWritten[r];
    endmethod

    method Action freeReg(PhysRegTag tag);
      freelist.free(tag);
      $display("[RENAME] Freed physical register p%0d", tag);
    endmethod

    method Action checkpoint(Maybe#(Tuple2#(RegIndex, PhysRegTag)) alloc);
      Vector#(32, PhysRegTag)      m = readVReg(archRegMap);
      Vector#(32, Bool)            w = readVReg(archRegWritten);
      Vector#(NUM_PHYS_REGS, Bool) f = freelist.snapshot();
      // allocateDestReg()'s register writes land next cycle, so fold this
      // instruction's own allocation into the snapshot by hand.
      if (alloc matches tagged Valid {.rd, .tag} &&& rd != 0) begin
        m[rd]  = tag;
        w[rd]  = True;
        f[tag] = False;   // its physreg is in use, not on the free list
      end
      shadowMap     <= m;
      shadowWritten <= w;
      shadowFree    <= f;
      $display("[RENAME] checkpoint taken");
    endmethod

    method Action restoreCheckpoint();
      writeVReg(archRegMap, shadowMap);
      writeVReg(archRegWritten, shadowWritten);
      freelist.restore(shadowFree);
      $display("[RENAME] rename map + free list restored from checkpoint");
    endmethod

  endmodule

endpackage