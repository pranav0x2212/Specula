package CSRFile;

  import Common::*;

  // ---- CSR addresses actually touched by xv6 _entry/start
  Bit#(12) csrMstatus  = 12'h300;
  Bit#(12) csrMedeleg  = 12'h302;
  Bit#(12) csrMideleg  = 12'h303;
  Bit#(12) csrMie      = 12'h304;
  Bit#(12) csrMtvec    = 12'h305;
  Bit#(12) csrMscratch = 12'h340;
  Bit#(12) csrMepc     = 12'h341;
  Bit#(12) csrSatp     = 12'h180;
  Bit#(12) csrMhartid  = 12'hF14;

  Bit#(12) csrSstatus  = 12'h100;
  Bit#(12) csrSie      = 12'h104;
  Bit#(12) csrStvec    = 12'h105;
  Bit#(12) csrSscratch = 12'h140;
  Bit#(12) csrSepc     = 12'h141;
  Bit#(12) csrScause   = 12'h142;
  Bit#(12) csrStval    = 12'h143;
  Bit#(12) csrSip      = 12'h144;

  Integer mstatusMIE  = 3;    // MIE
  Integer mstatusMPIE = 7;    // MPIE
  Integer sstatusSIEb  = 1;   // SIE
  Integer sstatusSPIEb = 5;   // SPIE
  Integer sstatusSPPb  = 8;   // SPP  (1 = S, 0 = U)
  Integer sieSEIEb     = 9;   // supervisor external interrupt enable

  Bit#(2) privU = 2'b00;
  Bit#(2) privS = 2'b01;
  Bit#(2) privM = 2'b11;

  typedef struct {
    Bit#(32) nextPC;
    Bit#(2)  nextPriv;
  } MretResult deriving (Bits, FShow);

  typedef struct {
    Bit#(32) nextPC;
    Bit#(2)  nextPriv;
  } SretResult deriving (Bits, FShow);

  function Bit#(32) csrNewValue(Bit#(3) funct3, Bit#(32) oldv, Bit#(32) src);
    return (case (funct3[1:0])
              2'b01:   src;                 // CSRRW / CSRRWI
              2'b10:   (oldv | src);        // CSRRS / CSRRSI
              2'b11:   (oldv & ~src);       // CSRRC / CSRRCI
              default: oldv;
            endcase);
  endfunction

  function Bool csrWriteEnabled(Bit#(3) funct3, Bit#(5) rs1OrZimm);
    return (funct3[1:0] == 2'b01) || (rs1OrZimm != 0);
  endfunction

  interface CSRFile_IFC;
    method Bit#(32) csrRead (Bit#(12) addr);
    method Action   csrWrite(Bit#(12) addr, Bit#(32) value);
    method ActionValue#(MretResult) doMret();
    method ActionValue#(Bit#(32)) takeTrap(Bit#(1) isInterrupt, Bit#(6) cause,
                                           Bit#(32) epc, Bit#(32) tval, Bit#(2) fromPriv);
    method ActionValue#(SretResult) doSret();
    method Bool sstatusSIE();
    method Bool sieSEIE();
    method Bit#(32) dbgMstatus();
    method Bit#(32) dbgMepc();
    method Bit#(32) satpValue();
  endinterface

  module mkCSRFile(CSRFile_IFC);

    Reg#(Bit#(32)) mstatus  <- mkReg(0);
    Reg#(Bit#(32)) mepc     <- mkReg(0);
    Reg#(Bit#(32)) mtvec    <- mkReg(0);
    Reg#(Bit#(32)) mie      <- mkReg(0);
    Reg#(Bit#(32)) mscratch <- mkReg(0);
    Reg#(Bit#(32)) medeleg  <- mkReg(0);
    Reg#(Bit#(32)) mideleg  <- mkReg(0);
    Reg#(Bit#(32)) satp     <- mkReg(0);
    Reg#(Bit#(32)) sstatus  <- mkReg(0);
    Reg#(Bit#(32)) sie      <- mkReg(0);
    Reg#(Bit#(32)) sip      <- mkReg(0);
    Reg#(Bit#(32)) stvec    <- mkReg(0);
    Reg#(Bit#(32)) sscratch <- mkReg(0);
    Reg#(Bit#(32)) sepc     <- mkReg(0);
    Reg#(Bit#(32)) scause   <- mkReg(0);
    Reg#(Bit#(32)) stval    <- mkReg(0);

    method Bit#(32) csrRead(Bit#(12) addr);
      return (case (addr)
                csrMstatus:  mstatus;
                csrMepc:     mepc;
                csrMtvec:    mtvec;
                csrMie:      mie;
                csrMscratch: mscratch;
                csrMedeleg:  medeleg;
                csrMideleg:  mideleg;
                csrSatp:     satp;
                csrMhartid:  32'h0;
                csrSstatus:  sstatus;
                csrSie:      sie;
                csrSip:      sip;
                csrStvec:    stvec;
                csrSscratch: sscratch;
                csrSepc:     sepc;
                csrScause:   scause;
                csrStval:    stval;
                default:     32'h0;
              endcase);
    endmethod

    method Action csrWrite(Bit#(12) addr, Bit#(32) value);
      case (addr)
        csrMstatus:  mstatus  <= value;
        csrMepc:     mepc     <= value;
        csrMtvec:    mtvec    <= value;
        csrMie:      mie      <= value;
        csrMscratch: mscratch <= value;
        csrMedeleg:  medeleg  <= value;
        csrMideleg:  mideleg  <= value;
        csrSatp:     satp     <= value;
        csrMhartid:  noAction;
        csrSstatus:  sstatus  <= value;
        csrSie:      sie      <= value;
        csrSip:      sip      <= value;
        csrStvec:    stvec    <= value;
        csrSscratch: sscratch <= value;
        csrSepc:     sepc     <= value;
        csrScause:   scause   <= value;
        csrStval:    stval    <= value;
        default:     noAction;
      endcase
    endmethod

    method ActionValue#(MretResult) doMret();
      Bit#(2)  mpp  = mstatus[12:11];
      Bit#(1)  mpie = mstatus[mstatusMPIE];
      Bit#(32) ns   = mstatus;
      ns[mstatusMIE]  = mpie;    // MIE  <- MPIE
      ns[mstatusMPIE] = 1'b1;    // MPIE <- 1
      ns[12]          = 1'b0;    // MPP  <- U (0)
      ns[11]          = 1'b0;
      mstatus <= ns;
      return MretResult { nextPC: mepc, nextPriv: mpp };
    endmethod

    method ActionValue#(Bit#(32)) takeTrap(Bit#(1) isInterrupt, Bit#(6) cause,
                                           Bit#(32) epc, Bit#(32) tval, Bit#(2) fromPriv);
      scause <= {isInterrupt, 25'd0, cause};
      sepc   <= epc;
      stval  <= tval;
      Bit#(32) ns = sstatus;
      Bit#(1) oldSIE = ns[sstatusSIEb];
      ns[sstatusSPPb]  = (fromPriv == privU) ? 1'b0 : 1'b1;  // SPP <- 1 unless trap from U
      ns[sstatusSPIEb] = oldSIE;                             // SPIE <- SIE
      ns[sstatusSIEb]  = 1'b0;                               // SIE  <- 0
      sstatus <= ns;
      return (stvec & ~32'h3);
    endmethod

    method ActionValue#(SretResult) doSret();
      Bit#(1) spp  = sstatus[sstatusSPPb];
      Bit#(1) spie = sstatus[sstatusSPIEb];
      Bit#(32) ns = sstatus;
      ns[sstatusSIEb]  = spie;   // SIE  <- SPIE
      ns[sstatusSPIEb] = 1'b1;   // SPIE <- 1
      ns[sstatusSPPb]  = 1'b0;   // SPP  <- U
      sstatus <= ns;
      Bit#(2) np = (spp == 1'b1) ? privS : privU;
      return SretResult { nextPC: sepc, nextPriv: np };
    endmethod

    method Bool sstatusSIE() = (sstatus[sstatusSIEb] == 1'b1);
    method Bool sieSEIE()    = (sie[sieSEIEb]        == 1'b1);

    method Bit#(32) dbgMstatus() = mstatus;
    method Bit#(32) dbgMepc()    = mepc;
    method Bit#(32) satpValue()  = satp;

  endmodule

endpackage
