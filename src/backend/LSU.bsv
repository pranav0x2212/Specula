package LSU;

  import Common::*;
  import Vector::*;
  import UnifiedMemory::*;

  typedef 8 SQ_SIZE;

  typedef UInt#(TLog#(SQ_SIZE)) SQIdx;

  typedef struct {
    ROBTag  robTag;
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

  interface IfcLSU;
    method ActionValue#(Data) load(Addr addr);
    method Action sqAllocate(ROBTag robTag);
    method Action sqExecStore(ROBTag robTag, Addr addr, Data rawData, Bit#(3) funct3);
    method Action storeToMem(Addr addr, Data rawData, Bit#(3) funct3);
    method Action sqPop();
    method Bool   sqOlderStorePending(ROBTag loadTag, ROBTag headTag);
    method Tuple2#(Bit#(4), Data) sqForward(Addr addr, ROBTag loadTag, ROBTag headTag);
    method Action sqFlush();
    method Bool   sqEmpty();
    method Bool   sqNotFull();
  endinterface

  module mkLSU#(Memory_IFC mem)(IfcLSU);

    Vector#(SQ_SIZE, Reg#(SQEntry)) sq <- replicateM(mkRegU);
    Vector#(SQ_SIZE, Reg#(Bool))    sqValid <- replicateM(mkReg(False));
    Reg#(SQIdx)      sqHead  <- mkReg(0);
    Reg#(SQIdx)      sqTail  <- mkReg(0);
    Reg#(UInt#(TLog#(TAdd#(SQ_SIZE, 1)))) sqCount <- mkReg(0);

    method ActionValue#(Data) load(Addr addr);
      Data v = mem.readWord(addr);
      if (!mem.inRange(addr))
        $display("[LSU] Load addr=%h OUT OF RANGE (returns 0)", addr);
      else
        $display("[LSU] Load addr=%h -> word %h", addr, v);
      return v;
    endmethod

    method Action sqAllocate(ROBTag robTag);
      sq[sqTail] <= SQEntry { robTag: robTag, addrReady: False, addr: 0, dataReady: False, data: 0, be: 0 };
      sqValid[sqTail] <= True;
      sqTail  <= sqTail + 1;
      sqCount <= sqCount + 1;
      $display("[SQ] alloc rob=%0d in slot %0d", robTag.idx, sqTail);
    endmethod

    method Action sqExecStore(ROBTag robTag, Addr addr, Data rawData, Bit#(3) funct3);
      Bit#(2) off = addr[1:0];
      Bit#(4) be  = storeByteEnable(funct3, off);
      Data    pos = positionStoreData(rawData, off);
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
        if (sqValid[i] && sq[i].robTag.idx == robTag.idx) begin
          let e = sq[i];
          e.addr = addr; e.data = pos; e.be = be;
          e.addrReady = True; e.dataReady = True;
          sq[i] <= e;
          $display("[SQ] exec rob=%0d slot %0d addr=%h be=%b pos-data=%h", robTag.idx, i, addr, be, pos);
        end
      end
    endmethod

    method Action storeToMem(Addr addr, Data rawData, Bit#(3) funct3);
      Bit#(2) off = addr[1:0];
      Bit#(4) be  = storeByteEnable(funct3, off);
      Data    pos = positionStoreData(rawData, off);
      if (mem.inRange(addr)) begin
        mem.writeWord(addr, pos, be);
        $display("[LSU] Committed store addr=%h be=%b <- raw=%h (positioned=%h)", addr, be, rawData, pos);
      end else
        $display("[LSU] Committed store addr=%h OUT OF RANGE (dropped)", addr);
    endmethod

    method Action sqPop();
      sqValid[sqHead] <= False;
      sqHead  <= sqHead + 1;
      sqCount <= sqCount - 1;
    endmethod

    method Bool sqOlderStorePending(ROBTag loadTag, ROBTag headTag);
      Bool pend = False;
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1)
        if (sqValid[i] && isOlderRob(sq[i].robTag, loadTag, headTag) && !sq[i].addrReady)
          pend = True;
      return pend;
    endmethod

    method Tuple2#(Bit#(4), Data) sqForward(Addr addr, ROBTag loadTag, ROBTag headTag);
      Bit#(30) loadWord = addr[31:2];
      Bit#(4)  covered = 0;
      Data     merged  = 0;
      for (Integer lane = 0; lane < 4; lane = lane + 1) begin
        UInt#(6) bestAge = 0;
        for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
          if (sqValid[i] && isOlderRob(sq[i].robTag, loadTag, headTag)
              && sq[i].addrReady
              && (sq[i].addr[31:2] == loadWord)
              && (sq[i].be[lane] == 1'b1)) begin
            UInt#(6) age = sq[i].robTag.idx - headTag.idx;
            if ((covered[lane] == 1'b0) || (age >= bestAge)) begin
              covered[lane] = 1'b1;
              bestAge = age;
              Bit#(8)  srcByte = truncate(sq[i].data >> (8 * lane));
              Bit#(32) laneMask = 32'hFF << (8 * lane);
              merged = (merged & ~laneMask) | ((zeroExtend(srcByte) << (8 * lane)) & laneMask);
            end
          end
        end
      end
      return tuple2(covered, merged);
    endmethod

    method Action sqFlush();
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1)
        sqValid[i] <= False;
      sqHead  <= 0;
      sqTail  <= 0;
      sqCount <= 0;
      $display("[SQ] flushed");
    endmethod

    method Bool sqEmpty()   = (sqCount == 0);
    method Bool sqNotFull() = (sqCount < fromInteger(valueOf(SQ_SIZE)));

  endmodule

endpackage
