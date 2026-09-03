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

  Integer mstatusMIE  = 3;    // MIE
  Integer mstatusMPIE = 7;    // MPIE

  Bit#(2) privU = 2'b00;
  Bit#(2) privS = 2'b01;
  Bit#(2) privM = 2'b11;

  typedef struct {
    Bit#(32) nextPC;
    Bit#(2)  nextPriv;
  } MretResult deriving (Bits, FShow);

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

    method Bit#(32) dbgMstatus() = mstatus;
    method Bit#(32) dbgMepc()    = mepc;
    method Bit#(32) satpValue()  = satp;

  endmodule

endpackage
