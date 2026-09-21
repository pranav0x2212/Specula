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

  function TransResult sv32TranslateP(Bit#(32)   va,
                                      AccessKind kind,
                                      Bool       paging,
                                      Bool       rootOk,
                                      Bit#(32)   satp,
                                      function Bit#(32) rootRead(Bit#(32) byteAddr),
                                      function Bit#(32) physRead(Bit#(32) byteAddr));
    TransResult res;

    if (!paging) begin
      res = transOK(va);
    end else begin
      Bit#(10) vpn1 = va[31:22];
      Bit#(10) vpn0 = va[21:12];
      Bit#(12) off  = va[11:0];

      Bit#(32) pte1  = rootRead({ satp[19:0], vpn1, 2'b00 });
      Bit#(32) pte0  = physRead({ pte1[29:10], vpn0, 2'b00 });
      Bool     leaf1 = isLeafPTE(pte1);

      Bool bad1  = !rootOk || pte1[0] != 1'b1;
      Bool badL1 = pte1[19:10] != 10'd0 || !leafPermitted(pte1, kind);
      Bool bad0  = pte0[0] != 1'b1 || !isLeafPTE(pte0) || !leafPermitted(pte0, kind);
      Bool flt   = bad1 || (leaf1 ? badL1 : bad0);

      res = TransResult { pa:    leaf1 ? { pte1[29:20], va[21:0] } : { pte0[29:10], off },
                          fault: flt,
                          cause: flt ? pageFaultCause(kind) : 4'd0 };
    end

    return res;
  endfunction

  function TransResult sv32Translate(Bit#(32)   va,
                                     AccessKind kind,
                                     Bit#(2)    priv,
                                     Bit#(32)   satp,
                                     function Bit#(32) physRead(Bit#(32) byteAddr));
    let r = sv32TranslateP(va, kind, satp[31] == 1'b1 && priv != 2'b11, True, satp, physRead, physRead);
    return TransResult { pa: r.fault ? 32'h0 : r.pa, fault: r.fault, cause: r.cause };
  endfunction

endpackage
