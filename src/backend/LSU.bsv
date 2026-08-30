package LSU;

  import Common::*;
  import Vector::*;

  typedef 8   SQ_SIZE;
  typedef 256 MemSize;

  typedef UInt#(TLog#(SQ_SIZE)) SQIdx;

  typedef struct {
    ROBTag robTag;
    Bool   addrReady;
    Addr   addr;
    Bool   dataReady;
    Data   data;
  } SQEntry deriving (Bits, FShow);

  interface IfcLSU;
    method ActionValue#(Data) load(Addr addr);         
    method Action sqAllocate(ROBTag robTag);            
    method Action sqExecStore(ROBTag robTag, Addr addr, Data data);  
    method Action storeToMem(Addr addr, Data data);     
    method Action sqPop();                              
    method Bool   sqOlderStorePending(ROBTag loadTag, ROBTag headTag); 
    method Maybe#(Data) sqForward(Addr addr, ROBTag loadTag, ROBTag headTag); 
    method Action sqFlush();                            
    method Bool   sqEmpty();
    method Bool   sqNotFull();
  endinterface

  module mkLSU(IfcLSU);

    Vector#(MemSize, Reg#(Data)) memory <- replicateM(mkReg(0));

    Vector#(SQ_SIZE, Reg#(SQEntry)) sq <- replicateM(mkRegU);
    Vector#(SQ_SIZE, Reg#(Bool))    sqValid <- replicateM(mkReg(False));
    Reg#(SQIdx)      sqHead  <- mkReg(0);
    Reg#(SQIdx)      sqTail  <- mkReg(0);
    Reg#(UInt#(TLog#(TAdd#(SQ_SIZE, 1)))) sqCount <- mkReg(0);

    function UInt#(32) wordIndex(Addr a);
      UInt#(32) au = unpack(a);
      return au >> 2;
    endfunction

    function Bool inBounds(Addr a);
      return (wordIndex(a) < fromInteger(valueOf(MemSize)));
    endfunction

    function UInt#(TLog#(MemSize)) memIndex(Addr a);
      return truncate(wordIndex(a));
    endfunction

    method ActionValue#(Data) load(Addr addr);
      Data v = 0;
      if (inBounds(addr)) begin
        v = memory[memIndex(addr)];
        $display("[LSU] Load addr=%h from memory[%0d] = %h", addr, memIndex(addr), v);
      end else
        $display("[LSU] Load addr=%h OUT OF BOUNDS", addr);
      return v;
    endmethod

    method Action sqAllocate(ROBTag robTag);
      sq[sqTail] <= SQEntry { robTag: robTag, addrReady: False, addr: 0, dataReady: False, data: 0 };
      sqValid[sqTail] <= True;
      sqTail  <= sqTail + 1;
      sqCount <= sqCount + 1;
      $display("[SQ] alloc rob=%0d in slot %0d", robTag.idx, sqTail);
    endmethod

    method Action sqExecStore(ROBTag robTag, Addr addr, Data data);
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
        if (sqValid[i] && sq[i].robTag.idx == robTag.idx) begin
          let e = sq[i];
          e.addr = addr; e.data = data;
          e.addrReady = True; e.dataReady = True;
          sq[i] <= e;
          $display("[SQ] exec rob=%0d slot %0d addr=%h data=%h", robTag.idx, i, addr, data);
        end
      end
    endmethod

    method Action storeToMem(Addr addr, Data data);
      if (inBounds(addr)) begin
        memory[memIndex(addr)] <= data;
        $display("[LSU] Committed store addr=%h <- data=%h to memory[%0d]", addr, data, memIndex(addr));
      end else
        $display("[LSU] Committed store addr=%h OUT OF BOUNDS (dropped)", addr);
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

    method Maybe#(Data) sqForward(Addr addr, ROBTag loadTag, ROBTag headTag);
      Maybe#(Data) res = tagged Invalid;
      UInt#(6) bestAge = 0;
      for (Integer i = 0; i < valueOf(SQ_SIZE); i = i + 1) begin
        if (sqValid[i] && isOlderRob(sq[i].robTag, loadTag, headTag)
            && sq[i].addrReady && sq[i].addr == addr) begin
          UInt#(6) age = sq[i].robTag.idx - headTag.idx;   
          if (!isValid(res) || age >= bestAge) begin
            res = tagged Valid sq[i].data;                 
            bestAge = age;
          end
        end
      end
      return res;
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
