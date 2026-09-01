package SpeculaCore;

  import FetchUnit::*;
  import DecodeUnit::*;
  import Common::*;
  import UnifiedMemory::*;
  import MemImage::*;
  import RenameStage::*;
  import PRF::*;
  import ReservationStation::*;
  import ROB::*;
  import ALU::*;
  import LSU::*;
  import MemQueue::*;
  import BranchPredictor::*;
  import FIFOF::*;
  import Vector::*;

  typedef struct {
    Bool       isLoad;
    PhysRegTag dest;
    Data       data;   
    Addr       addr;   
    ROBTag     robTag;
  } MemResult deriving (Bits, FShow);

  module mkSpeculaCore(Empty);
    Memory_IFC mem <- mkMemory;

    IfcFetchUnit fetch <- mkFetchUnit(mem);
    IfcDecodeUnit decodeUnit <- mkDecodeUnit;
    RenameStage_IFC rename <- mkRenameStage;
    PRF prf <- mkPRF;
    ReservationStationIfc rs <- mkReservationStation;
    ROB_IFC rob <- mkROB;
    ALU_IFC alu <- mkALU;
    IfcLSU lsu <- mkLSU(mem);
    MemQueue_IFC memQ <- mkMemQueue;
    BranchPredictor_IFC bp <- mkBranchPredictor;

    FIFOF#(MemResult) memResultQ <- mkSizedFIFOF(4);
    Addr      tohostAddr = 32'h10000000;
    Bit#(32)  maxPC      = fromInteger(memBaseAddr + valueOf(MemWords) * 4);

    Reg#(Bit#(32)) pc <- mkReg(fromInteger(memBaseAddr));
    Reg#(Bool) halted <- mkReg(False);
    Reg#(Bool) flushPending <- mkReg(False);
    Reg#(UInt#(32)) cycleCount <- mkReg(0);

    Array#(Reg#(Bit#(32))) brPredNextPC  <- mkCReg(2, 0);
    Array#(Reg#(Bool))  brOutstanding    <- mkCReg(2, False);
    Reg#(Bit#(32))      recoverPC        <- mkReg(0);
    Reg#(Bool)          recoveryComplete <- mkReg(False);

    Array#(Reg#(Bool))  cfInFlight       <- mkCReg(3, False);

    FIFOF#(Tuple3#(Bit#(32), Instruction, Bit#(32))) fetchedQ <- mkFIFOF();
    FIFOF#(Tuple3#(Bit#(32), Decoded, Bit#(32)))     decodedQ <- mkFIFOF();
    FIFOF#(RenamedInstr) renamedInstrQ <- mkSizedFIFOF(8);

    rule doFetch (!halted && !flushPending && pc < maxPC
                  && !(cfInFlight[0] && isControlFlowInstr(fetch.at(pc).instr)));
      let fs = fetch.at(pc);
      let instr = fs.instr;
      let pr <- bp.predict(pc);
      Bool predTaken = pr.prediction && pr.isValid;

      Bool isCondBranch = (instr[6:0] == 7'b1100011);
      Bool isCF         = isControlFlowInstr(instr);

      Bit#(32) predNext = (isCondBranch && predTaken) ? pr.targetAddr : fs.npc;

      if (isCF) begin
        brPredNextPC[1] <= predNext;
        cfInFlight[0]   <= True;
        $display("[FETCH] control-flow @ %h (%s): predicted-next PC = %h",
                 pc, isCondBranch ? "branch" : "jump", predNext);
      end

      fetch.start(pc);
      fetchedQ.enq(tuple3(pc, instr, fs.npc));
      pc <= predNext;
    endrule

    rule doDecode (!flushPending);
      match {.fpc, .instr, .fallpc} = fetchedQ.first;
      fetchedQ.deq;
      decodeUnit.start(instr, fpc);
      decodedQ.enq(tuple3(fpc, decode(instr, fpc), fallpc));
    endrule

    rule doRename (!flushPending && renamedInstrQ.notFull);
      match {.fpc, .d, .fallpc} = decodedQ.first;
      decodedQ.deq;
      rename.start(d);
      renamedInstrQ.enq(RenamedInstr {
        instr:     d,
        pc:        fpc,
        fallPC:    fallpc,
        src1Tag:   0,
        src1Ready: True,
        src2Tag:   0,
        src2Ready: True,
        destTag:   0,
        robTag:    ROBTag{idx: 0}
      });
      $display("[DISPATCH] Enqueued to buffer: rd=x%0d opcode=%0d", d.rd, d.opcode);
    endrule

    rule doRecover (flushPending && !recoveryComplete);
      $display("[RECOVER] misprediction: flushing backend, restoring rename state, redirect PC -> %h", recoverPC);
      rob.flushAll;
      rs.flush;
      alu.flush;
      memQ.flush;
      lsu.sqFlush;
      memResultQ.clear;
      fetchedQ.clear;
      decodedQ.clear;
      renamedInstrQ.clear;
      rename.restoreCheckpoint;
      bp.flushHistory;
      pc <= recoverPC;
      halted <= False;
      brOutstanding[1] <= False;
      cfInFlight[2] <= False;
      recoveryComplete <= True;
    endrule

    rule doRecoverDone (flushPending && recoveryComplete && !alu.busy);
      $display("[RECOVER] backend clean, resuming fetch at %h", recoverPC);
      flushPending <= False;
      recoveryComplete <= False;
    endrule

    rule doDispatch (renamedInstrQ.notEmpty && !flushPending
                     && rob.canAllocate
                     && (isMemoryOp(renamedInstrQ.first.instr.opcode)
                          ? (memQ.notFull && (isLoadOp(renamedInstrQ.first.instr.opcode) || lsu.sqNotFull))
                          : rs.notFull)
                     && !(isControlFlowOp(renamedInstrQ.first.instr.opcode) && brOutstanding[0]));
      let r = renamedInstrQ.first;
      Bool isMemoryOp = (r.instr.opcode == ALU_LW) || (r.instr.opcode == ALU_SW);
      Bool isLoad = (r.instr.opcode == ALU_LW);

      if (isMemoryOp) begin
        PhysRegTag destTag = 0;
        Maybe#(PhysRegTag) oldPhysDst = tagged Invalid;
        Bool canDispatch = True;

        if (isLoad && r.instr.rd != 0) begin
          let allocResult <- rename.allocateDestReg(r.instr.rd);
          match {.dTag, .oldTag, .success} = allocResult;
          destTag = dTag;
          oldPhysDst = oldTag;
          canDispatch = success;
        end

        if (canDispatch) begin
          renamedInstrQ.deq;

          if (isLoad && r.instr.rd != 0)
            prf.clear(destTag);

          let robTag <- rob.allocate(
            (isLoad ? tagged Valid r.instr.rd : tagged Invalid),
            (isLoad && r.instr.rd != 0 ? tagged Valid destTag : tagged Invalid),
            oldPhysDst,
            !isLoad,
            False,
            False,
            r.instr.funct3);

          PhysRegTag basePhys = rename.lookupMapping(r.instr.rs1);
          PhysRegTag dataPhys = rename.lookupMapping(r.instr.rs2);

          if (!isLoad)
            lsu.sqAllocate(robTag);

          memQ.enq(MemQEntry {
            isLoad: isLoad,
            base:   basePhys,
            sdata:  dataPhys,
            imm:    r.instr.imm,
            dest:   destTag,
            funct3: r.instr.funct3,
            robTag: robTag
          });
          $display("[DISPATCH] %s rob=%0d -> MemQueue (base=x%0d data=x%0d imm=%0d)",
                   isLoad ? "LOAD" : "STORE", robTag.idx, r.instr.rs1, r.instr.rs2, r.instr.imm);
        end
      end else begin
        if (rs.notFull) begin
          let allocResult <- rename.allocateDestReg(r.instr.rd);
          match {.destTag, .oldPhysDst, .success} = allocResult;
          
          if (r.instr.rd == 0 || success) begin
            renamedInstrQ.deq;

            Bool isCF   = isControlFlowOp(r.instr.opcode);
            Bool isJump = isJumpOp(r.instr.opcode);

            if (r.instr.rd != 0)
              prf.clear(destTag);

            let robTag <- rob.allocate(tagged Valid r.instr.rd, (r.instr.rd == 0 ? tagged Invalid : tagged Valid destTag), oldPhysDst, False, False, isCF, 3'b000);

            if (isCF) begin
              rename.checkpoint(r.instr.rd != 0 ? tagged Valid tuple2(r.instr.rd, destTag) : tagged Invalid);
              brOutstanding[0] <= True;
              $display("[DISPATCH] %s rob=%0d : rename + free-list checkpoint taken",
                       isJump ? "jump" : "branch", robTag.idx);
            end

            PhysRegTag src1PhysReg = rename.lookupMapping(r.instr.rs1);
            PhysRegTag src2PhysReg = rename.lookupMapping(r.instr.rs2);
            Bool src1Ready = prf.isReady(src1PhysReg);
            Bool src2Ready = prf.isReady(src2PhysReg);

            Bit#(7) actualOpcode = r.instr.raw[6:0];
            Bool shouldUseImm = (actualOpcode == 7'b0010011) || (actualOpcode == 7'b0110111);

            let rsEntry = RSEntry {
              opcode: r.instr.opcode,
              src1: src1PhysReg,
              src1Ready: src1Ready,
              src2: src2PhysReg,
              src2Ready: src2Ready,
              immediate: r.instr.imm,
              useImmediate: shouldUseImm,
              dest: destTag,
              robTag: robTag,
              pc: r.pc,
              fallPC: r.fallPC
            };
            
            rs.enq(rsEntry);
            $display("[DISPATCH] Sent to RS: dest=p%0d rob=%0d opcode=%0d", destTag, robTag.idx, r.instr.opcode);
          end
        end
      end
    endrule


    rule incrementCycles;
      $display("=== cycle %0d ===", cycleCount);
      cycleCount <= cycleCount + 1;
    endrule

    rule doHalt (!halted && !flushPending && ((pc >= maxPC
                              && !fetchedQ.notEmpty && !decodedQ.notEmpty
                              && !renamedInstrQ.notEmpty)
                             || cycleCount > 100000000));
      if (cycleCount > 100000000)
        $display("[Specula] Max cycles reached (%0d), terminating", cycleCount);
      else
        $display("[Specula] WARNING: fetch reached end of physical memory (%h) without a tohost write - halting", maxPC);
      halted <= True;
    endrule

    rule doTerminate (halted && !flushPending && !rs.notEmpty && !alu.notEmpty
                      && !memQ.notEmpty && lsu.sqEmpty && !memResultQ.notEmpty
                      && rob.isEmpty());
      $display("[Specula] Simulation complete - all instructions retired");
      $finish();
    endrule

    rule doCommit (!flushPending);
      let maybeHead = rob.peekHead();
      if (maybeHead matches tagged Valid .headInfo) begin
        match {.tag, .entry} = headInfo;
        if (entry.completed) begin
          if (entry.isBranch) begin
            if (entry.mispredicted) begin
              $display("[COMMIT] branch rob=%0d MISPREDICTED -> trigger recovery, redirect PC = %h", tag.idx, entry.redirectPC);
              recoverPC    <= entry.redirectPC;
              flushPending <= True;
            end else begin
              $display("[COMMIT] branch rob=%0d resolved correctly", tag.idx);
            end
          end else if (entry.isStore) begin
            lsu.sqPop();
            if (entry.memAddr == tohostAddr) begin
              // M2: explicit program termination signal.
              $display("[Specula] tohost store retired: addr=%h data=%0d", entry.memAddr, entry.data);
              if (entry.data == 1)
                $display("[Specula] TEST PASSED (tohost = 1)");
              else
                $display("[Specula] TEST FAILED (tohost = %0d)", entry.data);
              $display("[Specula] Simulation complete - terminated by tohost");
              $finish(0);
            end else begin
              lsu.storeToMem(entry.memAddr, entry.data, entry.memFunct3);
              $display("[COMMIT] store rob=%0d retired (addr=%h funct3=%b raw=%h)", tag.idx, entry.memAddr, entry.memFunct3, entry.data);
            end
          end else if (entry.dst matches tagged Valid .dstReg) begin
            $display("[COMMIT] rob=%0d committed: x%0d <- %0d", tag.idx, dstReg, entry.data);
          end
          rob.commitHead(rename);
        end
      end
    endrule

    rule doExecute (rs.notEmpty && alu.notFull && !flushPending);
      let rsEntry <- rs.deq();
      $display("[Execute] Dequeued RS entry: op=%0d dest=p%0d rob=%0d", rsEntry.opcode, rsEntry.dest, rsEntry.robTag.idx);

      let src1Val = prf.read(rsEntry.src1);
      let src2Val = prf.read(rsEntry.src2);
      
      let aVal = (src1Val matches tagged Valid .v ? v : 32'h0);
      let bVal = rsEntry.useImmediate ? rsEntry.immediate : (src2Val matches tagged Valid .v ? v : 32'h0);

      ALUReq aluReq = ALUReq {
        opcode: rsEntry.opcode,
        a: aVal,
        b: bVal,
        dest: rsEntry.dest,
        robTag: rsEntry.robTag,
        pc: rsEntry.pc,
        fallPC: rsEntry.fallPC,
        branchOffset: rsEntry.immediate
      };
      
      alu.enq(aluReq);
      $display("[Execute] Sent to ALU: op=%0d a=%0d b=%0d dest=p%0d rob=%0d (useImm=%0d)", rsEntry.opcode, aVal, bVal, rsEntry.dest, rsEntry.robTag.idx, rsEntry.useImmediate);
    endrule

    function Vector#(MEMQ_SIZE, Bool) memIssuableMask();
      ROBTag hTag = rob.headTag;
      Vector#(MEMQ_SIZE, Bool)      vmask   = memQ.validMask;
      Vector#(MEMQ_SIZE, MemQEntry) entries = memQ.peekAll;
      Vector#(MEMQ_SIZE, Bool) m = newVector;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1) begin
        Bool ok = False;
        if (vmask[i]) begin
          let e = entries[i];
          Bool baseRdy = prf.isReady(e.base);
          Bool dataRdy = e.isLoad || prf.isReady(e.sdata);
          Bool ordOK   = !e.isLoad || !lsu.sqOlderStorePending(e.robTag, hTag);
          ok = baseRdy && dataRdy && ordOK;
        end
        m[i] = ok;
      end
      return m;
    endfunction

    function Bool memIssuableExists();
      Vector#(MEMQ_SIZE, Bool) m = memIssuableMask();
      Bool any = False;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1) any = any || m[i];
      return any;
    endfunction

    rule doMemIssue (!flushPending && memResultQ.notFull && memIssuableExists);
      ROBTag hTag = rob.headTag;
      Vector#(MEMQ_SIZE, MemQEntry) entries = memQ.peekAll;
      Vector#(MEMQ_SIZE, Bool)      issuable = memIssuableMask();

      Maybe#(MemQIdx) pick = tagged Invalid;
      UInt#(7) bestAge = 7'd127;
      for (Integer i = 0; i < valueOf(MEMQ_SIZE); i = i + 1) begin
        if (issuable[i]) begin
          let e = entries[i];
          UInt#(7) age = extend(e.robTag.idx - hTag.idx);
          if (age < bestAge) begin
            bestAge = age;
            pick = tagged Valid fromInteger(i);
          end
        end
      end

      if (pick matches tagged Valid .idx) begin
        let e = entries[idx];
        Data baseVal = fromMaybe(0, prf.read(e.base));
        Addr addr = baseVal + e.imm;

        if (isMisalignedAccess(e.funct3, addr))
          $display("[LSU] MISALIGNED %s addr=%h funct3=%b - unsupported (M5), operating on the containing word only",
                   e.isLoad ? "load" : "store", addr, e.funct3);

        if (e.isLoad) begin
          match {.covered, .fwdWord} = lsu.sqForward(addr, e.robTag, hTag);
          Data full = fwdWord;
          if (covered != 4'b1111) begin
            let mw <- lsu.load(addr);
            for (Integer lane = 0; lane < 4; lane = lane + 1)
              if (covered[lane] == 1'b0) begin
                Bit#(32) laneMask = 32'hFF << (8 * lane);
                full = (full & ~laneMask) | (mw & laneMask);
              end
          end
          Data result = loadExtract(full, addr[1:0], e.funct3);
          if (covered != 0)
            $display("[LSU] Load rob=%0d addr=%h : forwarded lanes=%b fwd=%h merged-word=%h",
                     e.robTag.idx, addr, covered, fwdWord, full);
          memResultQ.enq(MemResult { isLoad: True, dest: e.dest, data: result, addr: 0, robTag: e.robTag });
          $display("[MEMQ] load rob=%0d issued: addr=%h funct3=%b result=%h", e.robTag.idx, addr, e.funct3, result);
        end else begin
          Data sdata = fromMaybe(0, prf.read(e.sdata));
          lsu.sqExecStore(e.robTag, addr, sdata, e.funct3);
          memResultQ.enq(MemResult { isLoad: False, dest: 0, data: sdata, addr: addr, robTag: e.robTag });
          $display("[MEMQ] store rob=%0d issued: addr=%h funct3=%b raw-data=%h", e.robTag.idx, addr, e.funct3, sdata);
        end
        memQ.issue(idx);
      end
    endrule

    rule doWriteback (alu.notEmpty);
      let aluResp <- alu.deq();

      if (aluResp.isBranch) begin
        Bit#(32) actualNextPC = aluResp.actualTaken ? aluResp.actualTarget : aluResp.fallPC;
        Bool mispred = (actualNextPC != brPredNextPC[0]);

        rob.completeEntry(aluResp.robTag, aluResp.result, 0, mispred, actualNextPC);

        if (aluResp.dest != 0) begin
          prf.write(aluResp.dest, aluResp.result);
          prf.markReady(aluResp.dest);
        end
        rs.wakeup(aluResp.dest);

        if (!aluResp.isJump)
          bp.update(BranchUpdate {
            pc:         aluResp.pc,
            targetAddr: aluResp.actualTarget,
            taken:      aluResp.actualTaken,
            newHistory: 0
          });

        if (!mispred)
          brOutstanding[1] <= False;
        cfInFlight[1] <= False;

        if (aluResp.isJump)
          $display("[Writeback] jump rob=%0d : link=%h target=%h predicted-next=%h -> %s",
                   aluResp.robTag.idx, aluResp.result, actualNextPC, brPredNextPC[0],
                   mispred ? "REDIRECT" : "sequential");
        else
          $display("[Writeback] branch rob=%0d : actualTaken=%0d actual-next=%h predicted-next=%h -> %s",
                   aluResp.robTag.idx, aluResp.actualTaken, actualNextPC, brPredNextPC[0],
                   mispred ? "MISPREDICT" : "correct");
      end else begin
        $display("[Writeback] ALU result: res=%0d dest=p%0d rob=%0d", aluResp.result, aluResp.dest, aluResp.robTag.idx);

        rob.completeEntry(aluResp.robTag, aluResp.result, 0, False, 0);

        if (aluResp.dest != 0) begin
          prf.write(aluResp.dest, aluResp.result);
          prf.markReady(aluResp.dest);
        end

        rs.wakeup(aluResp.dest);
        $display("[Writeback] Waking up instructions waiting for p%0d", aluResp.dest);

        $display("[Writeback] ROB[%0d] completed with result=%0d, PRF[p%0d] = %0d",
                 aluResp.robTag.idx, aluResp.result, aluResp.dest, aluResp.result);
      end
    endrule

    (* descending_urgency = "doRecover, doWriteback" *)
    (* descending_urgency = "doRecover, doDispatch, doCommit" *)
    (* descending_urgency = "doWriteback, doMemWriteback" *)
    (* descending_urgency = "doMemWriteback, doMemIssue" *)
    rule doMemWriteback (memResultQ.notEmpty);
      let mr = memResultQ.first; memResultQ.deq;
      rob.completeEntry(mr.robTag, mr.data, mr.addr, False, 0);
      if (mr.isLoad) begin
        if (mr.dest != 0) begin
          prf.write(mr.dest, mr.data);
          prf.markReady(mr.dest);
        end
        rs.wakeup(mr.dest);
        $display("[Writeback] load rob=%0d result -> p%0d = %h", mr.robTag.idx, mr.dest, mr.data);
      end else begin
        $display("[Writeback] store rob=%0d marked complete", mr.robTag.idx);
      end
    endrule

  endmodule
endpackage