package SpeculaCore;

  import FetchUnit::*;
  import DecodeUnit::*;
  import Common::*;
  import RenameStage::*;
  import PRF::*;
  import ReservationStation::*;
  import ROB::*;
  import ALU::*;
  import LSU::*;
  import BranchPredictor::*;
  import FIFOF::*;
  import Vector::*;

  module mkSpeculaCore(Empty);
    IfcFetchUnit fetch <- mkFetchUnit;
    IfcDecodeUnit decodeUnit <- mkDecodeUnit;
    RenameStage_IFC rename <- mkRenameStage;
    PRF prf <- mkPRF;
    ReservationStationIfc rs <- mkReservationStation;
    ROB_IFC rob <- mkROB;
    ALU_IFC alu <- mkALU;
    IfcLSU lsu <- mkLSU;
    BranchPredictor_IFC bp <- mkBranchPredictor;

    let maxPC = 32'h00000020;

    Reg#(Bit#(32)) pc <- mkReg(0);
    Reg#(Bool) halted <- mkReg(False);
    Reg#(Bool) flushPending <- mkReg(False);
    Reg#(UInt#(32)) cycleCount <- mkReg(0);

    Vector#(32, Reg#(BranchMetadata)) branchMeta <- replicateM(mkReg(BranchMetadata {
      isBranch: False,
      pc: 0,
      predictedTarget: 0
    }));

    FIFOF#(BranchMetadata) branchMetaQ <- mkFIFOF();

    FIFOF#(Tuple2#(Bit#(32), Instruction)) fetchedQ <- mkFIFOF();
    FIFOF#(Tuple2#(Bit#(32), Decoded))     decodedQ <- mkFIFOF();
    FIFOF#(RenamedInstr) renamedInstrQ <- mkSizedFIFOF(8);

    rule doFetch (!halted && !flushPending && pc < maxPC);
      let instr = getInstruction(pc);
      fetch.start(pc);                     
      fetchedQ.enq(tuple2(pc, instr));
      pc <= pc + 4;                        
    endrule

    rule doDecode (!flushPending);
      match {.fpc, .instr} = fetchedQ.first;
      fetchedQ.deq;
      decodeUnit.start(instr, fpc);        
      decodedQ.enq(tuple2(fpc, decode(instr, fpc)));
    endrule

    rule doRename (!flushPending && renamedInstrQ.notFull);
      match {.fpc, .d} = decodedQ.first;
      decodedQ.deq;
      rename.start(d);                     
      renamedInstrQ.enq(RenamedInstr {
        instr:     d,
        pc:        fpc,
        src1Tag:   0,
        src1Ready: True,
        src2Tag:   0,
        src2Ready: True,
        destTag:   0,
        robTag:    ROBTag{idx: 0}
      });
      $display("[DISPATCH] Enqueued to buffer: rd=x%0d opcode=%0d", d.rd, d.opcode);
    endrule

    rule doFlushQueue (flushPending && renamedInstrQ.notEmpty);
      $display("[FLUSH] Draining stale instruction from queue");
      renamedInstrQ.deq;
    endrule

    rule doClearFlush (flushPending && !renamedInstrQ.notEmpty);
      $display("[FLUSH] Queue drained, pipeline clean");
      flushPending <= False;
    endrule

    (* descending_urgency = "doDispatch, doCommit" *)
    rule doDispatch (renamedInstrQ.notEmpty && !flushPending
                     && rob.canAllocate
                     && (isMemoryOp(renamedInstrQ.first.instr.opcode) || rs.notFull));
      let r = renamedInstrQ.first;
      Bool isMemoryOp = (r.instr.opcode == ALU_LW) || (r.instr.opcode == ALU_SW);
      Bool isLoad = (r.instr.opcode == ALU_LW);
      
      if (isMemoryOp) begin
        PhysRegTag destTag = 0;
        Maybe#(PhysRegTag) oldPhysDst = tagged Invalid;
        Bool canDispatch = True;

        if (isLoad) begin
          let allocResult <- rename.allocateDestReg(r.instr.rd);
          match {.dTag, .oldTag, .success} = allocResult;
          if (success || r.instr.rd == 0) begin
            destTag = dTag;
            oldPhysDst = oldTag;
            canDispatch = True;
          end else begin
            canDispatch = False;
          end
        end
        
        if (canDispatch) begin
          renamedInstrQ.deq; 
          PhysRegTag addrRegTag = rename.lookupMapping(r.instr.rs1);
          Maybe#(Data) maybeAddrVal = prf.read(addrRegTag);
          Data addrValue = 0;
          if (maybeAddrVal matches tagged Valid .val) begin
            addrValue = val + signExtend(r.instr.imm[11:0]);
          end
          
          if (isLoad) begin
            let robTag <- rob.allocate(tagged Valid r.instr.rd, (r.instr.rd != 0 ? tagged Valid destTag : tagged Invalid), oldPhysDst, False, True);

            Data loadData <- lsu.load(addrValue);
            prf.write(destTag, loadData);
            prf.markReady(destTag);
            $display("[LSU] Load from addr %h -> p%0d = %h, rob=%0d", addrValue, destTag, loadData, robTag.idx);
          end else begin
            let robTag <- rob.allocate(tagged Valid r.instr.rd, tagged Invalid, oldPhysDst, True, True);
            
            PhysRegTag dataRegTag = rename.lookupMapping(r.instr.rs2);
            Maybe#(Data) maybeStoreVal = prf.read(dataRegTag);
            Data storeData = 0;
            if (maybeStoreVal matches tagged Valid .val) begin
              storeData = val;
            end
            lsu.directStore(addrValue, storeData);
            $display("[LSU] Store (rob=%0d) addr=%h <- data=%h (IMMEDIATE, marked completed)", robTag.idx, addrValue, storeData);
          end
        end
      end else begin
        if (rs.notFull) begin
          let allocResult <- rename.allocateDestReg(r.instr.rd);
          match {.destTag, .oldPhysDst, .success} = allocResult;
          
          if (r.instr.rd == 0 || success) begin
            renamedInstrQ.deq;
            
            let robTag <- rob.allocate(tagged Valid r.instr.rd, (r.instr.rd == 0 ? tagged Invalid : tagged Valid destTag), oldPhysDst, False, False);
            PhysRegTag src1PhysReg = rename.lookupMapping(r.instr.rs1);
            PhysRegTag src2PhysReg = rename.lookupMapping(r.instr.rs2);
            Bool src1Ready = prf.isReady(src1PhysReg);
            Bool src2Ready = prf.isReady(src2PhysReg);
            
            Bit#(7) actualOpcode = r.instr.raw[6:0];
            Bool shouldUseImm = (actualOpcode == 7'b0010011) || (actualOpcode == 7'b1100011);
            
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
              pc: r.pc
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

    rule doHalt (!halted && ((pc >= maxPC
                              && !fetchedQ.notEmpty && !decodedQ.notEmpty
                              && !renamedInstrQ.notEmpty)
                             || cycleCount > 100000000));
      if (cycleCount > 100000000)
        $display("[Specula] Max cycles reached (%0d), terminating", cycleCount);
      else
        $display("[Specula] Halting at PC: %h", pc);
      halted <= True;
    endrule

    rule doTerminate (halted && !rs.notEmpty && !alu.notEmpty && rob.isEmpty());
      $display("[Specula] Simulation complete - all instructions retired");
      $finish();
    endrule

    rule doCommit;
      let maybeHead = rob.peekHead();
      if (maybeHead matches tagged Valid .headInfo) begin
        match {.tag, .entry} = headInfo;
        if (entry.completed) begin
          if (entry.isStore) begin
            $display("[COMMIT] Retired store, rob=%0d", tag.idx);
          end else if (entry.dst matches tagged Valid .dstReg) begin
            $display("[COMMIT] Committed instr writing to x%0d", dstReg);
          end
          rob.commitHead(rename);
        end
      end
    endrule

    rule doExecute (rs.notEmpty && alu.notFull);
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
        branchOffset: rsEntry.immediate
      };
      
      alu.enq(aluReq);
      $display("[Execute] Sent to ALU: op=%0d a=%0d b=%0d dest=p%0d rob=%0d (useImm=%0d)", rsEntry.opcode, aVal, bVal, rsEntry.dest, rsEntry.robTag.idx, rsEntry.useImmediate);
    endrule

    rule doWriteback (alu.notEmpty);
      let aluResp <- alu.deq();
      
      $display("[Writeback] ALU result: res=%0d dest=p%0d rob=%0d", aluResp.result, aluResp.dest, aluResp.robTag.idx);

      rob.writeResultAndMark(aluResp.robTag, aluResp.result);

      prf.write(aluResp.dest, aluResp.result);
      prf.markReady(aluResp.dest);

      rs.wakeup(aluResp.dest);
      $display("[Writeback] Waking up instructions waiting for p%0d", aluResp.dest);
      
      $display("[Writeback] ROB[%0d] completed with result=%0d, PRF[p%0d] = %0d",
               aluResp.robTag.idx, aluResp.result, aluResp.dest, aluResp.result);
    endrule

  endmodule
endpackage