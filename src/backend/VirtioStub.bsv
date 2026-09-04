package VirtioStub;

  import Common::*;
  import UnifiedMemory::*;
  import Plic::*;
  import RegFile::*;

  Addr virtioBase = 32'h10001000;

  typedef 262144 FsImgWords;
  typedef Bit#(TLog#(FsImgWords)) FsIdx;

  typedef enum {
    S_IDLE, S_AVAIL, S_RING,
    S_DESC0, S_HDR, S_DESC1, S_DESC2,
    S_COPY, S_STATUS, S_USEDELEM, S_USEDIDX, S_DONE
  } VState deriving (Bits, Eq, FShow);

  interface Virtio_IFC;
    method Bit#(32) readWord (Addr a);
    method Action   writeWord(Addr a, Bit#(32) data, Bit#(4) be);
    method Bit#(32) dbgFsimg (FsIdx idx);
    method VState   dbgState ();
  endinterface

  module mkVirtioBlk#(Memory_IFC ram, Plic_IFC plic)(Virtio_IFC);

    RegFile#(FsIdx, Bit#(32)) fsimg <-
      mkRegFileLoad("fs.hex", 0, fromInteger(valueOf(FsImgWords) - 1));

    Reg#(Bit#(32)) pfnBase   <- mkReg(0);
    Array#(Reg#(Bool)) kickPending <- mkCReg(2, False);

    Reg#(VState)   st         <- mkReg(S_IDLE);
    Reg#(Bit#(9))  wi         <- mkReg(0);
    Reg#(Bit#(16)) lastAvail  <- mkReg(0);
    Reg#(Bit#(16)) usedIdx    <- mkReg(0);
    Reg#(Bit#(16)) descHead   <- mkReg(0);
    Reg#(Bit#(32)) hdrAddr    <- mkReg(0);
    Reg#(Bit#(16)) next0      <- mkReg(0);
    Reg#(Bit#(32)) dataAddr   <- mkReg(0);
    Reg#(Bit#(16)) next1      <- mkReg(0);
    Reg#(Bit#(32)) statusAddr <- mkReg(0);
    Reg#(Bit#(32)) reqType    <- mkReg(0);
    Reg#(Bit#(32)) fsWordBase <- mkReg(0);

    function Addr descWordAddr(Bit#(16) d, Bit#(9) w) =
      pfnBase + (zeroExtend(d) << 4) + (zeroExtend(w) << 2);

    rule virtioStep (st != S_IDLE || kickPending[1]);
      Addr rdAddr = ?;
      case (st)
        S_AVAIL:  rdAddr = pfnBase + 32'd128;
        S_RING:   rdAddr = pfnBase + ((32'd132 + (zeroExtend(lastAvail[2:0]) << 1)) & ~32'd3);
        S_DESC0:  rdAddr = descWordAddr(descHead, wi);
        S_HDR:    rdAddr = hdrAddr + (zeroExtend(wi) << 2);
        S_DESC1:  rdAddr = descWordAddr(next0, wi);
        S_DESC2:  rdAddr = descWordAddr(next1, 0);
        S_COPY:   rdAddr = dataAddr + (zeroExtend(wi) << 2);
        default:  rdAddr = 0;
      endcase
      Bit#(32) rw = ram.readWord(rdAddr);

      FsIdx fi = truncate(fsWordBase) + zeroExtend(wi[7:0]);

      Bool     doWr   = False;
      Addr     wrAddr = 0;
      Bit#(32) wrData = 0;
      Bit#(4)  wrBe   = 4'b1111;

      case (st)
        S_IDLE:
          if (kickPending[1]) begin kickPending[1] <= False; st <= S_AVAIL; end

        S_AVAIL:
          st <= (rw[31:16] == lastAvail) ? S_IDLE : S_RING;

        S_RING: begin
          descHead <= (lastAvail[0] == 1'b1) ? rw[31:16] : rw[15:0];
          wi <= 0; st <= S_DESC0;
        end

        S_DESC0:
          if (wi == 0) begin hdrAddr <= rw; wi <= 3; end
          else begin next0 <= rw[31:16]; wi <= 0; st <= S_HDR; end

        S_HDR:
          if (wi == 0) begin reqType <= rw; wi <= 2; end
          else begin fsWordBase <= (rw << 7); wi <= 0; st <= S_DESC1; end

        S_DESC1:
          if (wi == 0) begin dataAddr <= rw; wi <= 3; end
          else begin next1 <= rw[31:16]; wi <= 0; st <= S_DESC2; end

        S_DESC2: begin
          statusAddr <= rw; wi <= 0; st <= S_COPY;
        end

        S_COPY: begin
          if (reqType == 0) begin
            doWr = True; wrAddr = dataAddr + (zeroExtend(wi) << 2);
            wrData = fsimg.sub(fi); wrBe = 4'b1111;
          end else begin
            fsimg.upd(fi, rw);
          end
          if (wi == 255) begin wi <= 0; st <= S_STATUS; end
          else wi <= wi + 1;
        end

        S_STATUS: begin
          doWr = True; wrAddr = statusAddr;
          wrData = 32'h0; wrBe = 4'b0001 << statusAddr[1:0];
          wi <= 0; st <= S_USEDELEM;
        end

        S_USEDELEM: begin
          Addr eBase = pfnBase + 32'd4100 + (zeroExtend(usedIdx[2:0]) << 3);
          doWr = True; wrBe = 4'b1111;
          if (wi == 0) begin wrAddr = eBase;     wrData = zeroExtend(descHead); wi <= 1; end
          else begin        wrAddr = eBase + 4;  wrData = 32'd1024; wi <= 0; st <= S_USEDIDX; end
        end

        S_USEDIDX: begin
          Bit#(16) nu = usedIdx + 1;
          doWr = True; wrAddr = pfnBase + 32'd4096; wrData = {nu, 16'd0}; wrBe = 4'b1100;
          usedIdx   <= nu;
          lastAvail <= lastAvail + 1;
          st <= S_DONE;
        end

        S_DONE: begin
          plic.setPending(5'd1);
          st <= S_AVAIL;
        end
      endcase

      if (doWr) ram.writeWord(wrAddr, wrData, wrBe);
    endrule

    method Bit#(32) readWord(Addr a);
      Bit#(8) off = truncate(a - virtioBase);
      return (case (off)
                8'h00:   32'h74726976;   // MAGIC_VALUE
                8'h04:   32'h00000001;   // VERSION (1 = legacy)
                8'h08:   32'h00000002;   // DEVICE_ID (2 = block)
                8'h0c:   32'h554d4551;   // VENDOR_ID
                8'h10:   32'h00000000;   // DEVICE_FEATURES
                8'h34:   32'h00000008;   // QUEUE_NUM_MAX
                8'h60:   32'h00000001;   // INTERRUPT_STATUS
                default: 32'h0;
              endcase);
    endmethod

    method Action writeWord(Addr a, Bit#(32) data, Bit#(4) be);
      Bit#(8) off = truncate(a - virtioBase);
      case (off)
        8'h40:   pfnBase <= data << 12;  // QUEUE_PFN -> queue-area physical base
        8'h50:   kickPending[0] <= True;  // QUEUE_NOTIFY -> kick the engine
        default: noAction;               // PAGE_SIZE / SEL / NUM / DRIVER_FEATURES / ACK / STATUS
      endcase
    endmethod

    method Bit#(32) dbgFsimg(FsIdx idx) = fsimg.sub(idx);
    method VState   dbgState()          = st;

  endmodule

endpackage
