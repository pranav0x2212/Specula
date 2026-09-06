package VirtioBlkTest;

  import Common::*;
  import UnifiedMemory::*;
  import Plic::*;
  import VirtioStub::*;
  import RegFile::*;

  Addr rbase   = 32'h80000000;
  Addr qbase   = 32'h80000000;
  Addr availA  = 32'h80000080;
  Addr usedA   = 32'h80001000;
  Addr hdrA    = 32'h80001800;
  Addr dataA   = 32'h80001c00;
  Addr statusA = 32'h80002000;

  Addr vBase   = 32'h10001000;
  Addr pBase   = 32'h0c000000;

  module mkBenchRam(Memory_IFC);
    RegFile#(Bit#(13), Bit#(32)) m <- mkRegFileLoad("fs.hex", 0, 8191);
    function Bit#(13) ix(Addr a) = truncate((a - rbase) >> 2);
    function Bool rng(Addr a) = (a >= rbase) && (a < rbase + 32768);
    method Bit#(32) readWord(Addr a) = rng(a) ? m.sub(ix(a)) : 32'h0;
    method Action writeWord(Addr a, Bit#(32) d, Bit#(4) be);
      if (rng(a)) begin
        let o = m.sub(ix(a));
        let k = laneMask32(be);
        m.upd(ix(a), (o & ~k) | (d & k));
      end
    endmethod
    method Bool inRange(Addr a) = rng(a);
    method Bit#(32) physReadWord(Addr a) = rng(a) ? m.sub(ix(a)) : 32'h0;
    method Bool extIntReq() = False;
  endmodule

  function Bool noRx() = False;

  module mkVirtioBlkTest(Empty);
    Memory_IFC ram  <- mkBenchRam;
    Plic_IFC   plic <- mkPlic(noRx);
    Virtio_IFC v    <- mkVirtioBlk(ram, plic);

    Reg#(Bit#(16)) ph    <- mkReg(0);
    Reg#(Bit#(16)) fails <- mkReg(0);
    Reg#(Bit#(16)) kk    <- mkReg(0);
    Reg#(Bool)     doKick <- mkReg(False);

    Reg#(Addr)     rdA <- mkReg(rbase);
    Reg#(FsIdx)    fsA <- mkReg(0);
    Reg#(Bit#(32)) rr  <- mkReg(0);
    Reg#(Bit#(32)) fr  <- mkReg(0);

    Reg#(Bit#(32)) rStat  <- mkReg(0);  Reg#(Bit#(32)) rUid  <- mkReg(0);
    Reg#(Bit#(32)) rEid   <- mkReg(0);  Reg#(Bit#(32)) rElen <- mkReg(0);
    Reg#(Bit#(32)) rDisk0 <- mkReg(0);  Reg#(Bit#(32)) rDiskN<- mkReg(0);
    Reg#(Bit#(32)) rG0    <- mkReg(0);  Reg#(Bit#(32)) rGN   <- mkReg(0);

    function ActionValue#(Bit#(16)) chk(String tag, Bit#(32) got, Bit#(32) want);
      actionvalue
        if (got == want) begin $display("[VIRTIO-TEST] ok   %s : %08h", tag, got); return 0; end
        else begin $display("[VIRTIO-TEST] FAIL %s : got %08h want %08h", tag, got, want); return 1; end
      endactionvalue
    endfunction

    rule run (v.dbgState == S_IDLE && !doKick);
      rr <= ram.readWord(rdA);
      fr <= v.dbgFsimg(fsA);

      Bool hold = False;
      Bit#(16) nf = 0;
      Bit#(16) t  = 0;

      case (ph)
        0:  ram.writeWord(qbase + 0,  hdrA,         4'hF);
        1:  ram.writeWord(qbase + 12, 32'h00010001, 4'hF);   // desc0 {flags=NEXT, next=1}
        2:  ram.writeWord(qbase + 16, dataA,        4'hF);
        3:  ram.writeWord(qbase + 28, 32'h00020001, 4'hF);   // desc1 {flags=NEXT, next=2}
        4:  ram.writeWord(qbase + 32, statusA,      4'hF);
        5:  ram.writeWord(qbase + 44, 32'h00000002, 4'hF);   // desc2 {flags=WRITE, next=0}
        6:  ram.writeWord(availA + 4, 32'h00000000, 4'hF);   // ring[0]=0, ring[1]=0
        7:  ram.writeWord(statusA,    32'hFFFFFFFF, 4'hF);   // poison status byte
        8:  plic.writeWord(pBase + 32'h4,      32'd1, 4'hF); // priority[1] = 1
        9:  plic.writeWord(pBase + 32'h2080,   32'd2, 4'hF); // SENABLE = 1<<1
        10: plic.writeWord(pBase + 32'h201000, 32'd0, 4'hF); // threshold = 0
        11: v.writeWord(vBase + 32'h40, 32'h00080000, 4'hF); // QUEUE_PFN = 0x80000
        12: ram.writeWord(hdrA + 0, 32'h00000001, 4'hF);     // outhdr.type = T_OUT
        13: ram.writeWord(hdrA + 8, 32'h00000000, 4'hF);     // outhdr.sector = 0
        14: begin
              ram.writeWord(dataA + (zeroExtend(kk) << 2), 32'hA5A50000 | zeroExtend(kk), 4'hF);
              if (kk == 255) kk <= 0; else begin kk <= kk + 1; hold = True; end
            end
        15: ram.writeWord(availA, 32'h00010000, 4'hF);       // avail {flags=0, idx=1}
        16: doKick <= True;                                  // -> kick rule issues QUEUE_NOTIFY
        17: begin if (kk == 500) kk <= 0; else begin kk <= kk + 1; hold = True; end end
        18: rdA <= statusA;
        19: rdA <= usedA;
        20: begin rStat <= rr; rdA <= usedA + 4; end
        21: begin rUid  <= rr; rdA <= usedA + 8; end
        22: begin rEid  <= rr; fsA <= 0;   end
        23: begin rElen <= rr; fsA <= 255; end
        24: rDisk0 <= fr;
        25: rDiskN <= fr;
        26: begin
              t <- chk("t_out status OK",     rStat & 32'hFF,               32'h0);        nf=nf+t;
              t <- chk("t_out used.id",       rUid >> 16,                   32'd1);        nf=nf+t;
              t <- chk("t_out used elem.id",  rEid,                         32'd0);        nf=nf+t;
              t <- chk("t_out used elem.len", rElen,                        32'd1024);     nf=nf+t;
              t <- chk("t_out plic claim",    plic.readWord(pBase+32'h201004), 32'd1);     nf=nf+t;
              t <- chk("t_out plic extReq",   zeroExtend(pack(plic.extReq)), 32'd1);       nf=nf+t;
              t <- chk("t_out disk word 0",   rDisk0,                       32'hA5A50000); nf=nf+t;
              t <- chk("t_out disk word 255", rDiskN,                       32'hA5A500FF); nf=nf+t;
            end
        27: plic.writeWord(pBase + 32'h201004, 32'd1, 4'hF); // complete
        28: begin
              t <- chk("plic extReq cleared", zeroExtend(pack(plic.extReq)), 32'd0);      nf=nf+t;
            end
        29: begin
              ram.writeWord(dataA + (zeroExtend(kk) << 2), 32'hDEADBEEF, 4'hF);
              if (kk == 255) kk <= 0; else begin kk <= kk + 1; hold = True; end
            end
        30: ram.writeWord(hdrA + 0, 32'h00000000, 4'hF);
        31: ram.writeWord(availA, 32'h00020000, 4'hF);
        32: doKick <= True;
        33: begin if (kk == 500) kk <= 0; else begin kk <= kk + 1; hold = True; end end

        34: rdA <= statusA;
        35: rdA <= usedA;
        36: begin rStat <= rr; rdA <= dataA + 0;    end
        37: begin rUid  <= rr; rdA <= dataA + 1020; end
        38: rG0 <= rr;
        39: rGN <= rr;
        40: begin
              t <- chk("t_in status OK",       rStat & 32'hFF, 32'h0);       nf=nf+t;
              t <- chk("t_in used.id",         rUid >> 16,     32'd2);       nf=nf+t;
              t <- chk("t_in guest word 0",    rG0,            32'hA5A50000); nf=nf+t;
              t <- chk("t_in guest word 255",  rGN,            32'hA5A500FF); nf=nf+t;
            end
        41: plic.writeWord(pBase + 32'h201004, 32'd1, 4'hF);
        42: begin
              t <- chk("m19f level idle (req1,req2 acked)", zeroExtend(pack(plic.extReq)), 32'd0); nf=nf+t;
              ram.writeWord(availA + 8, 32'h00000000, 4'hF);
            end
        43: ram.writeWord(hdrA + 0, 32'h00000001, 4'hF);
        44: ram.writeWord(hdrA + 8, 32'h00000001, 4'hF);
        45: begin
              ram.writeWord(dataA + (zeroExtend(kk) << 2), 32'h5A5A0000 | zeroExtend(kk), 4'hF);
              if (kk == 255) kk <= 0; else begin kk <= kk + 1; hold = True; end
            end
        46: ram.writeWord(availA, 32'h00030000, 4'hF);
        47: doKick <= True;
        48: begin if (kk == 500) kk <= 0; else begin kk <= kk + 1; hold = True; end end
        49: ram.writeWord(hdrA + 0, 32'h00000000, 4'hF);
        50: begin
              ram.writeWord(dataA + (zeroExtend(kk) << 2), 32'hCACACACA, 4'hF);
              if (kk == 255) kk <= 0; else begin kk <= kk + 1; hold = True; end
            end
        51: ram.writeWord(availA, 32'h00040000, 4'hF);
        52: doKick <= True;
        53: begin if (kk == 500) kk <= 0; else begin kk <= kk + 1; hold = True; end end
        54: begin
              t <- chk("m19f extReq high, 2 unacked", zeroExtend(pack(plic.extReq)),         32'd1); nf=nf+t;
              t <- chk("m19f claim offers src 1",     plic.readWord(pBase + 32'h201004),      32'd1); nf=nf+t;
            end
        55: plic.writeWord(pBase + 32'h201004, 32'd1, 4'hF);
        56: begin
              t <- chk("m19f extReq STILL high after 1/2 acks", zeroExtend(pack(plic.extReq)),  32'd1); nf=nf+t;
              t <- chk("m19f claim still offers src 1",         plic.readWord(pBase+32'h201004), 32'd1); nf=nf+t;
            end
        57: plic.writeWord(pBase + 32'h201004, 32'd1, 4'hF);
        58: begin
              t <- chk("m19f extReq clear after 2/2 acks", zeroExtend(pack(plic.extReq)), 32'd0); nf=nf+t;
              rdA <= usedA;
            end
        59: rdA <= dataA + 0;
        60: begin rUid <= rr; rdA <= dataA + 1020; end
        61: begin rG0  <= rr; fsA <= 128; end
        62: begin rGN  <= rr; fsA <= 383; end
        63: rDisk0 <= fr;
        64: rDiskN <= fr;
        65: begin
              t <- chk("m19f used.id == 4 (both retired)", rUid >> 16, 32'd4);        nf=nf+t;
              t <- chk("m19f req3 T_OUT disk word 0",      rDisk0,     32'h5A5A0000); nf=nf+t;
              t <- chk("m19f req3 T_OUT disk word 255",    rDiskN,     32'h5A5A00FF); nf=nf+t;
              t <- chk("m19f req4 T_IN  guest word 0",     rG0,        32'h5A5A0000); nf=nf+t;
              t <- chk("m19f req4 T_IN  guest word 255",   rGN,        32'h5A5A00FF); nf=nf+t;
            end

        default: begin
          if (fails == 0) $display("[VIRTIO-TEST] PASS - all checks ok");
          else            $display("[VIRTIO-TEST] FAIL - %0d checks wrong", fails);
          $finish(0);
        end
      endcase

      fails <= fails + nf;
      if (!hold) ph <= ph + 1;
    endrule

    (* descending_urgency = "v_virtioStep, run" *)
    rule kick (v.dbgState == S_IDLE && doKick);
      v.writeWord(vBase + 32'h50, 32'd0, 4'hF);
      doKick <= False;
    endrule

  endmodule

endpackage
