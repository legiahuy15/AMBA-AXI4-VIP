//Hoang Ho: package-level state for one outstanding AXI4 read transaction.
// The slave scheduler keeps one context per accepted AR request and sends one
// R beat at a time. Only the head context of each RID is eligible, which keeps
// same-ID transactions ordered while allowing different RIDs to interleave.
class axi4_read_context;
    axi4_id_t          id;
    axi4_addr_t        addr;
    bit [7:0]          len;
    bit [2:0]          size;
    axi4_burst_type_e  burst;
    axi4_lock_e        lock;
    bit [3:0]          cache;
    bit [2:0]          prot;
    bit [3:0]          region;
    int unsigned       order_idx;
    longint unsigned  arrival_idx;

    axi4_resp_e        resp;
    axi4_data_t        data_q[$];
    int unsigned       beat_idx;

    function new();
        beat_idx = 0;
    endfunction
endclass : axi4_read_context
