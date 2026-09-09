package LSU;

  import Common::*;
  import Vector::*;
  import UnifiedMemory::*;

  typedef 8 SQ_SIZE;

  typedef struct {
    Bool    addrReady;
    Addr    addr;
    Bool    dataReady;
    Data    data;
    Bit#(4) be;
  } SQEntry deriving (Bits, FShow);

  function Bit#(4) storeByteEnable(Bit#(3) funct3, Bit#(2) off);
    return (case (funct3)
              3'b000:  (4'b0001 << off);   // SB
              3'b001:  (4'b0011 << off);   // SH
              default: 4'b1111;            // SW
            endcase);
  endfunction

  function Data positionStoreData(Data raw, Bit#(2) off);
    return raw << {off, 3'b000};
  endfunction

  function Data sext8 (Bit#(8)  x) = (x[7]  == 1'b1) ? { 24'hFFFFFF, x } : { 24'h000000, x };
  function Data zext8 (Bit#(8)  x) = { 24'h000000, x };
  function Data sext16(Bit#(16) x) = (x[15] == 1'b1) ? { 16'hFFFF, x }   : { 16'h0000, x };
  function Data zext16(Bit#(16) x) = { 16'h0000, x };

  function Data loadExtract(Data word, Bit#(2) off, Bit#(3) funct3);
    Bit#(8)  b  = truncate(word >> {off, 3'b000});
    Bit#(16) hw = truncate(word >> {off, 3'b000});
    return (case (funct3)
              3'b000:  sext8(b);    // LB
              3'b001:  sext16(hw);  // LH
              3'b100:  zext8(b);    // LBU
              3'b101:  zext16(hw);  // LHU
              default: word;        // LW
            endcase);
  endfunction

  function Bool isMisalignedAccess(Bit#(3) funct3, Addr addr);
    return (case (funct3)
              3'b001, 3'b101: (addr[0]   != 1'b0);
              3'b010:         (addr[1:0] != 2'b0);
              default:        False;
            endcase);
  endfunction

  typedef struct {
    Bit#(4) key;
    Bit#(8) byt;
  } FwdCand deriving (Bits);

  function FwdCand fwdPick(FwdCand a, FwdCand b) = (a.key >= b.key) ? a : b;

  interface IfcLSU;
    method ActionValue#(Data) load(Addr addr);
    method Action sqAllocate();
    method SQPtr  sqTailMark();
    method Action sqExecStore(SQPtr slot, Addr addr, Data rawData, Bit#(3) funct3);
    method Action storeToMem(Addr addr, Data rawData, Bit#(3) funct3);
    method Action sqPop();
    method Bool   sqOlderStorePending(SQPtr loadWm);
    method Tuple2#(Bit#(4), Data) sqForward(Addr addr, SQPtr loadWm);
    method Action sqFlush();
    method Bool   sqEmpty();
    method Bool   sqNotFull();
  endinterface

  module mkLSU#(Memory_IFC mem)(IfcLSU);

    Vector#(SQ_SIZE, Reg#(SQEntry)) sq <- replicateM(mkRegU);
    Vector#(SQ_SIZE, Reg#(Bool))    sqValid <- replicateM(mkReg(False));
    Reg#(SQPtr) sqHead <- mkReg(0);
    Reg#(SQPtr) sqTail <- mkReg(0);

    Array#(Reg#(Bit#(SQ_SIZE))) sqExecd <- mkCReg(3, 0);

    function Bit#(3) slotOf(SQPtr p) = truncate(p);

    method ActionValue#(Data) load(Addr addr);
      Data v = mem.readWord(addr);
      if (!mem.inRange(addr)) begin
        if (!interactiveMode) $display("[LSU] Load addr=%h OUT OF RANGE (returns 0)", addr);
      end
      else if (traceOn)
        $display("[LSU] Load addr=%h -> word %h", addr, v);
      return v;
    endmethod

    method Action sqAllocate();
      sq[slotOf(sqTail)] <= SQEntry { addrReady: False, addr: 0, dataReady: False, data: 0, be: 0 };
      sqValid[slotOf(sqTail)] <= True;
      sqExecd[2] <= sqExecd[2] & ~(8'b1 << slotOf(sqTail));
      sqTail <= sqTail + 1;
      if (traceOn) $display("[SQ] alloc in slot %0d", slotOf(sqTail));
    endmethod

    method SQPtr sqTailMark() = sqTail;

    method Action sqExecStore(SQPtr slot, Addr addr, Data rawData, Bit#(3) funct3);
      Bit#(2) off = addr[1:0];
      Bit#(4) be  = storeByteEnable(funct3, off);
      Data    pos = positionStoreData(rawData, off);
      Bit#(3) s   = slotOf(slot);
      if (sqValid[s]) begin
        let e = sq[s];
        e.addr = addr; e.data = pos; e.be = be;
        e.addrReady = True; e.dataReady = True;
        sq[s] <= e;
        sqExecd[0] <= sqExecd[0] | (8'b1 << s);
        if (traceOn) $display("[SQ] exec slot %0d addr=%h be=%b pos-data=%h", s, addr, be, pos);
      end
    endmethod

    method Action storeToMem(Addr addr, Data rawData, Bit#(3) funct3);
      Bit#(2) off = addr[1:0];
      Bit#(4) be  = storeByteEnable(funct3, off);
      Data    pos = positionStoreData(rawData, off);
      if (mem.inRange(addr)) begin
        mem.writeWord(addr, pos, be);
        if (traceOn) $display("[LSU] Committed store addr=%h be=%b <- raw=%h (positioned=%h)", addr, be, rawData, pos);
      end else begin
        if (!interactiveMode) $display("[LSU] Committed store addr=%h OUT OF RANGE (dropped)", addr);
      end
    endmethod

    method Action sqPop();
      sqValid[slotOf(sqHead)] <= False;
      sqHead <= sqHead + 1;
    endmethod

    method Bool sqOlderStorePending(SQPtr loadWm);
      Bit#(3) h3        = slotOf(sqHead);
      SQPtr   olderLive = loadWm - sqHead;
      Bool pend = False;
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
        Bit#(3) ii  = fromInteger(i);
        SQPtr   age = zeroExtend(ii - h3);
        if (sqValid[i] && (age < olderLive) && (sqExecd[1][ii] == 1'b0))
          pend = True;
      end
      return pend;
    endmethod

    method Tuple2#(Bit#(4), Data) sqForward(Addr addr, SQPtr loadWm);
      Bit#(30) loadWord  = addr[31:2];
      Bit#(3)  h3        = slotOf(sqHead);
      SQPtr    olderLive = loadWm - sqHead;

      Vector#(SQ_SIZE, Bool)    wordHit = newVector;
      Vector#(SQ_SIZE, Bit#(3)) sqAge   = newVector;
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
        Bit#(3) ii  = fromInteger(i);
        Bit#(3) age = ii - h3;
        sqAge[i] = age;
        wordHit[i] = sqValid[i] && (zeroExtend(age) < olderLive) && sq[i].addrReady
                     && (sq[i].addr[31:2] == loadWord);
      end

      Bit#(4) covered = 0;
      Data    merged  = 0;
      for (Integer lane = 0; lane < 4; lane = lane + 1) begin
        Vector#(SQ_SIZE, FwdCand) c = newVector;
        for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
          Bool m = wordHit[i] && (sq[i].be[lane] == 1'b1);
          c[i] = FwdCand { key: m ? { 1'b1, sqAge[i] } : 4'd0,
                           byt: truncate(sq[i].data >> (8 * lane)) };
        end
        Vector#(4, FwdCand) r1 = newVector;
        for (Integer i = 0; i < 4; i = i + 1) r1[i] = fwdPick(c[2*i], c[2*i + 1]);
        Vector#(2, FwdCand) r2 = newVector;
        for (Integer i = 0; i < 2; i = i + 1) r2[i] = fwdPick(r1[2*i], r1[2*i + 1]);
        FwdCand win = fwdPick(r2[0], r2[1]);

        if (win.key[3] == 1'b1) begin
          covered[lane] = 1'b1;
          Bit#(32) laneMask = 32'hFF << (8 * lane);
          merged = (merged & ~laneMask) | ((zeroExtend(win.byt) << (8 * lane)) & laneMask);
        end
      end
      return tuple2(covered, merged);
    endmethod

    method Action sqFlush();
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1)
        sqValid[i] <= False;
      sqExecd[2] <= 0;
      sqHead <= 0;
      sqTail <= 0;
      if (traceOn) $display("[SQ] flushed");
    endmethod

    method Bool sqEmpty()   = (sqHead == sqTail);
    method Bool sqNotFull() = ((sqTail - sqHead) != 4'd8);

  endmodule

endpackage
