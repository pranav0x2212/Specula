package MMU;

  import Common::*;

  typedef enum { InstFetch, DataLoad, DataStore } AccessKind deriving (Bits, Eq, FShow);

  typedef struct {
    Bit#(32) pa;
    Bool     fault;
    Bit#(4)  cause;   // 12 = inst page fault, 13 = load page fault, 15 = store/AMO page fault
  } TransResult deriving (Bits, FShow);

  function Bit#(4) pageFaultCause(AccessKind k);
    return (case (k)
              InstFetch: 4'd12;
              DataLoad:  4'd13;
              default:   4'd15;  
            endcase);
  endfunction

  function Bool isLeafPTE(Bit#(32) pte) = (pte[3:1] != 3'b000);

  function Bool leafPermitted(Bit#(32) pte, AccessKind k);
    Bool r = (pte[1] == 1'b1);
    Bool w = (pte[2] == 1'b1);
    Bool x = (pte[3] == 1'b1);
    Bool reserved = (w && !r);
    Bool okForKind = (case (k)
                        InstFetch: x;
                        DataLoad:  r;
                        default:   w;  
                      endcase);
    return okForKind && !reserved;
  endfunction

  function TransResult transFault(AccessKind k) =
    TransResult { pa: 32'h0, fault: True, cause: pageFaultCause(k) };

  function TransResult transOK(Bit#(32) pa) =
    TransResult { pa: pa, fault: False, cause: 4'd0 };

  function TransResult sv32Translate(Bit#(32)   va,
                                     AccessKind kind,
                                     Bit#(2)    priv,
                                     Bit#(32)   satp,
                                     function Bit#(32) physRead(Bit#(32) byteAddr));
    TransResult res;

    Bool sv32   = (satp[31] == 1'b1);
    Bool mmode  = (priv == 2'b11);
    Bool paging = sv32 && !mmode;

    if (!paging) begin
      res = transOK(va);
    end else begin
      Bit#(32) rootPA = { satp[19:0], 12'd0 };

      Bit#(10) vpn1 = va[31:22];
      Bit#(10) vpn0 = va[21:12];
      Bit#(12) off  = va[11:0];

      Bit#(32) o1   = zeroExtend(vpn1) << 2;
      Bit#(32) pte1 = physRead(rootPA + o1);

      if (pte1[0] != 1'b1) begin                  
        res = transFault(kind);
      end else if (isLeafPTE(pte1)) begin
        if (pte1[19:10] != 10'd0 || !leafPermitted(pte1, kind))
          res = transFault(kind);
        else
          res = transOK({ pte1[29:20], va[21:0] });
      end else begin
        Bit#(32) l0base = { pte1[29:10], 12'd0 };
        Bit#(32) o0     = zeroExtend(vpn0) << 2;
        Bit#(32) pte0   = physRead(l0base + o0);

        if (pte0[0] != 1'b1 || !isLeafPTE(pte0) || !leafPermitted(pte0, kind))
          res = transFault(kind);
        else
          res = transOK({ pte0[29:10], off });
      end
    end

    return res;
  endfunction

endpackage
