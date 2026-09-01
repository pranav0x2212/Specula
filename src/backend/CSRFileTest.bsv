package CSRFileTest;

  // ==========================================================================
  // M8: standalone bench for the machine-mode CSR file.
  //
  //   make csrtest
  //
  // Verifies:
  //   - CSR write / read for the required CSRs
  //   - mhartid reads 0 (and ignores writes)
  //   - unimplemented CSR reads 0
  //   - mstatus MPP read-modify-write (the start() sequence)
  //   - mepc read / write
  //   - mret target PC
  //   - mret privilege transition (M -> MPP)
  //   - mret mstatus side effects (MIE<-MPIE, MPIE<-1, MPP<-0)
  //   - csrNewValue / csrWriteEnabled pure helpers (CSRRW/S/C + imm forms)
  // ==========================================================================

  import CSRFile::*;

  module mkCSRFileTest(Empty);
    CSRFile_IFC     csr   <- mkCSRFile;
    Reg#(Bit#(8))   step  <- mkReg(0);
    Reg#(Bit#(16))  fails <- mkReg(0);

    function ActionValue#(Bit#(16)) chk(String tag, Bit#(32) got, Bit#(32) want);
      actionvalue
        Bool ok = (got == want);
        if (ok) $display("[CSR-TEST] ok   %s : %08h", tag, got);
        else    $display("[CSR-TEST] FAIL %s : got %08h want %08h", tag, got, want);
        return ok ? 16'd0 : 16'd1;
      endactionvalue
    endfunction

    function ActionValue#(Bit#(16)) chkB(String tag, Bool got, Bool want);
      actionvalue
        Bool ok = (got == want);
        if (ok) $display("[CSR-TEST] ok   %s", tag);
        else    $display("[CSR-TEST] FAIL %s : got %0d want %0d", tag, got, want);
        return ok ? 16'd0 : 16'd1;
      endactionvalue
    endfunction

    rule run;
      Bit#(16) nf = 0;
      case (step)
        0: csr.csrWrite(12'h300, 32'h00001800);                         // mstatus <- 0x1800

        1: begin
             let a <- chk("mstatus rw", csr.csrRead(12'h300), 32'h00001800);
             nf = a;
             csr.csrWrite(12'h341, 32'h80000d54);                       // mepc <- main
           end

        2: begin
             let a <- chk("mepc rw", csr.csrRead(12'h341), 32'h80000d54);
             nf = a;
             csr.csrWrite(12'hF14, 32'hdeadbeef);                       // mhartid write (ignored)
           end

        3: begin
             let a <- chk("mhartid ro0", csr.csrRead(12'hF14), 32'h0);
             let b <- chk("unimpl csr rd0", csr.csrRead(12'h999), 32'h0);
             nf = a + b;
           end

        // start()'s MPP RMW: mstatus = (mstatus & ~MPP_MASK) | MPP_S
        4: csr.csrWrite(12'h300, (csr.csrRead(12'h300) & ~32'h00001800) | 32'h00000800);

        5: begin
             let a <- chk("mstatus MPP=S", csr.csrRead(12'h300) & 32'h00001800, 32'h00000800);
             nf = a;
           end

        // mret setup: MPP=S (0x800), MPIE=1 (0x80), MIE=0
        6: csr.csrWrite(12'h300, 32'h00000880);

        7: begin
             let mr <- csr.doMret();
             let a <- chk("mret target",  mr.nextPC, 32'h80000d54);
             let b <- chk("mret priv=S",  zeroExtend(mr.nextPriv), 32'h00000001);
             nf = a + b;
           end

        8: begin
             let ms = csr.csrRead(12'h300);
             let a <- chk("mret MPP<-0",    ms & 32'h00001800, 32'h0);
             let b <- chk("mret MPIE<-1",   ms & 32'h00000080, 32'h00000080);
             let c <- chk("mret MIE<-MPIE", ms & 32'h00000008, 32'h00000008);
             nf = a + b + c;
           end

        9: begin
             let a <- chk ("csrNewValue RW", csrNewValue(3'b001, 32'hF0F0F0F0, 32'h0000FFFF), 32'h0000FFFF);
             let b <- chk ("csrNewValue RS", csrNewValue(3'b010, 32'hF0F0F0F0, 32'h0000FFFF), 32'hF0F0FFFF);
             let c <- chk ("csrNewValue RC", csrNewValue(3'b011, 32'hF0F0F0F0, 32'h0000FFFF), 32'hF0F00000);
             let d <- chkB("wen CSRRW z0",   csrWriteEnabled(3'b001, 5'd0), True);
             let e <- chkB("wen CSRRS z0",   csrWriteEnabled(3'b010, 5'd0), False);
             let f <- chkB("wen CSRRS z5",   csrWriteEnabled(3'b010, 5'd5), True);
             let g <- chkB("wen CSRRC z0",   csrWriteEnabled(3'b011, 5'd0), False);
             let h <- chkB("wen CSRRWI z0",  csrWriteEnabled(3'b101, 5'd0), True);
             let i <- chkB("wen CSRRSI z0",  csrWriteEnabled(3'b110, 5'd0), False);
             nf = a + b + c + d + e + f + g + h + i;
           end

        default: begin
          if (fails == 0) $display("[CSR-TEST] PASS - all checks ok");
          else            $display("[CSR-TEST] FAIL - %0d checks wrong", fails);
          $finish(0);
        end
      endcase
      fails <= fails + nf;
      step  <= step + 1;
    endrule

  endmodule

endpackage
