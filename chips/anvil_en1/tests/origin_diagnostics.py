"""Observational-only monitors for disposable RTL copies, never an oracle.

These local monitors attribute an error to its first producing interface.
Acceptance still uses the unchanged public-top transactor and reference.
"""

import hashlib
import re


MONITORS = {
    "anvil_en1_allocation_admission": r"""
    reg [63:0] diagnostic_text_peak = 0, diagnostic_text_shadow_peak = 0;
    reg [63:0] diagnostic_scratch_peak = 0, diagnostic_scratch_shadow_peak = 0;
    reg [63:0] diagnostic_equivalent_peak = 0, diagnostic_equivalent_shadow_peak = 0;
    reg [63:0] diagnostic_reports = 0, diagnostic_denials = 0;
    always @(posedge clk) if (rst_n) begin
        if (state == WAIT_REPORT && report_valid) begin
            diagnostic_reports <= diagnostic_reports + 1'b1;
            if (text_workspace > diagnostic_text_peak)
                diagnostic_text_peak <= text_workspace;
            if (text_workspace_shadow > diagnostic_text_shadow_peak)
                diagnostic_text_shadow_peak <= text_workspace_shadow;
            if (scratch > diagnostic_scratch_peak)
                diagnostic_scratch_peak <= scratch;
            if (scratch_shadow > diagnostic_scratch_shadow_peak)
                diagnostic_scratch_shadow_peak <= scratch_shadow;
            if (equivalent > diagnostic_equivalent_peak)
                diagnostic_equivalent_peak <= equivalent;
            if (equivalent_shadow > diagnostic_equivalent_shadow_peak)
                diagnostic_equivalent_shadow_peak <= equivalent_shadow;
        end
        if (state == WAIT_REPORT && report_valid &&
            (report_partition_error || report_overlap ||
             scratch > scratch_limit || scratch_shadow > scratch_limit ||
             text_workspace > text_limit || text_workspace_shadow > text_limit ||
             equivalent_shadow < equivalent))
            $display("ORIGIN cycle=%0d path=%m event=prospective_limit component=%0d candidate=%0d shadow=%0d equivalent=%0d equivalent_shadow=%0d baseline=%0d scratch=%0d scratch_shadow=%0d scratch_limit=%0d text=%0d text_shadow=%0d text_limit=%0d fallback=%0d overlap=%0d partition=%0d",
                diagnostic_cycle, candidate_component, candidate_bytes,
                candidate_shadow_bytes, equivalent, equivalent_shadow, baseline_hold,
                scratch, scratch_shadow, scratch_limit, text_workspace,
                text_workspace_shadow, text_limit, report_fallback,
                report_overlap, report_partition_error);
        if (rsp_valid && rsp_ready && !rsp_allowed) begin
            diagnostic_denials <= diagnostic_denials + 1'b1;
            $display("ORIGIN cycle=%0d path=%m event=denied component=%0d candidate=%0d shadow=%0d legal=%0d limit_failure=%0d payload_scaled=%0d shadow_scaled=%0d baseline_scaled=%0d",
                diagnostic_cycle, candidate_component, candidate_bytes,
                candidate_shadow_bytes, candidate_legal_hold, limit_failure,
                scaled_payload, scaled_shadow, scaled_baseline);
            for (integer d=0; d<25; d=d+1)
                $display("ALLOCATION component=%0d live=%0d shadow=%0d",
                    d, prospective_live[64*d+:64], prospective_shadow[64*d+:64]);
        end
    end
    final begin
        $display("ALLOCATION_SUMMARY path=%m reports=%0d denials=%0d text_peak=%0d text_shadow_peak=%0d scratch_peak=%0d scratch_shadow_peak=%0d equivalent_peak=%0d equivalent_shadow_peak=%0d",
            diagnostic_reports, diagnostic_denials, diagnostic_text_peak,
            diagnostic_text_shadow_peak, diagnostic_scratch_peak,
            diagnostic_scratch_shadow_peak, diagnostic_equivalent_peak,
            diagnostic_equivalent_shadow_peak);
    end
""",
    "anvil_en1_frontier_execute": r"""
    reg diagnostic_overrun_seen = 0;
    always @(posedge clk) if (rst_n) begin
        if (task_valid && task_ready)
            $display("ORIGIN cycle=%0d path=%m event=task op=%0d layer=%0d token=%0d",
                diagnostic_cycle, task_op, task_layer, task_token);
        if (reservation_overrun && !diagnostic_overrun_seen) begin
            diagnostic_overrun_seen <= 1;
            $display("ORIGIN cycle=%0d path=%m event=reservation_overrun state=%0d op=%0d layer=%0d token=%0d ple_fault=%0d frontier_reserved=%0d frontier=%0d frontier_limit=%0d ring_reserved=%0d ring=%0d ring_limit=%0d anchor_reserved=%0d anchor=%0d vector_reserved=%0d vector=%0d vector_limit=%0d vector_shadow=%0d vector_shadow_limit=%0d embedding_reserved=%0d embedding=%0d embedding_limit=%0d embedding_shadow=%0d embedding_shadow_limit=%0d layer_reserved=%0d layer=%0d layer_limit=%0d layer_shadow=%0d layer_shadow_limit=%0d",
                diagnostic_cycle, state, operation, layer_hold, token_hold,
                shared_ple_fault, frontier_reserved, actual_frontier_bytes,
                frontier_reservation_hold, ring_reserved, actual_ring_bytes,
                ring_reservation_hold, anchor_reserved, actual_anchor_bytes,
                vector_reserved, actual_vector_bytes, vector_reservation_bytes,
                actual_vector_shadow, vector_reservation_shadow,
                embedding_reserved, child_execution_bytes[0+:64], embedding_bytes,
                child_execution_shadow[0+:64], embedding_shadow,
                layer_reserved, child_execution_bytes[64+:64], layer_bytes,
                child_execution_shadow[64+:64], layer_shadow);
        end
        if (source_state == S_RESPONSE && source_error_hold)
            $display("ORIGIN cycle=%0d path=%m event=source_error state=%0d layer=%0d token=%0d index=%0d ple=%0d normalized=%0d frontier=%0d final_valid=%0d",
                diagnostic_cycle, state, layer_hold, token_hold, source_index_hold,
                source_is_ple_hold, source_is_normalized_hold, source_frontier,
                final_vector_valid);
        if (task_done_valid && task_done_ready && task_done_error != 0)
            $display("ORIGIN cycle=%0d path=%m event=task_error error=%0d op=%0d layer=%0d token=%0d admission_fault=%0d overrun=%0d child=%0d h_bad=%0d h_complete=%0d h_count=%0d",
                diagnostic_cycle, task_done_error, operation, layer_hold, token_hold,
                admission_fault, reservation_overrun, child_error,
                h_bad, h_complete, h_count);
    end
""",
    "anvil_en1_native": r"""
    reg diagnostic_fault_seen = 0;
    always @(posedge clk) if (rst_n) begin
        if (protocol_error && !diagnostic_fault_seen) begin
            diagnostic_fault_seen <= 1;
            $display("ORIGIN cycle=%0d path=%m event=protocol_error memory=%0d binding=%0d vector=%0d grant=%0d hidden=%0d overlap=%0d vector_access=%0d embedding_access=%0d",
                diagnostic_cycle, memory_fault, binding_fault, vector_ram_fault,
                grant_fault, hidden_access_fault, text_ram_overlap,
                vector_access_fault, embedding_access_fault);
        end
        if (cache_valid && meta_state == META_WAIT && cache_response[5:2] != 0)
            $display("ORIGIN cycle=%0d path=%m event=cache_error error=%0d request=%h",
                diagnostic_cycle, cache_response[5:2], meta_request);
        if (fetch_rsp_valid && fetch_rsp_ready && fetch_error != 0)
            $display("ORIGIN cycle=%0d path=%m event=fetch_error error=%0d model=%0d owner=%0d token=%0d value=%0d head=%0d component=%0d",
                diagnostic_cycle, fetch_error, fetch_model, fetch_owner,
                fetch_token, fetch_value, fetch_head, fetch_component);
        if (regen_rsp_valid && regen_rsp_ready && regen_error != 0)
            $display("ORIGIN cycle=%0d path=%m event=regen_error error=%0d owner=%0d token=%0d value=%0d head=%0d component=%0d",
                diagnostic_cycle, regen_error, regen_owner, regen_token,
                regen_value, regen_head, regen_component);
        if (schedule_done && state == SCHEDULE_WAIT && schedule_error != 0)
            $display("ORIGIN cycle=%0d path=%m event=schedule_error error=%0d",
                diagnostic_cycle, schedule_error);
    end
""",
    "anvil_en1_top": r"""
    reg diagnostic_allocation_seen = 0;
    always @(posedge clk) if (rst_n) begin
        if (allocation_failed && !diagnostic_allocation_seen) begin
            diagnostic_allocation_seen <= 1;
            $display("ORIGIN cycle=%0d path=%m event=allocation_failed equivalent=%0d shadow=%0d scratch=%0d scratch_shadow=%0d baseline=%0d partition=%0d overlap=%0d",
                diagnostic_cycle, allocation_equivalent_bytes, allocation_shadow_bytes,
                native_scratch_bytes, native_scratch_shadow_bytes,
                production_baseline_payload, allocation_report_partition_error,
                allocation_report_overlap);
        end
        if (native_done && state == NATIVE_WAIT)
            $display("ORIGIN cycle=%0d path=%m event=native_completion error=%0d fault=%0d allocation_failed=%0d",
                diagnostic_cycle, native_error, native_fault, allocation_failed);
    end
""",
}


def instrument(source, destination, public_only=False):
    """Append diagnostic observers without replacing any functional RTL."""
    original = source.read_text()
    name = source.stem
    monitor = "" if public_only else MONITORS.get(name, "")
    # Only public completion ports, not guessed internal aliases, qualify.
    ports = original.split(");", 1)[0]
    if all(re.search(r"\b" + port + r"\b", ports)
           for port in ("clk", "rst_n", "done_valid", "done_ready", "done_error")):
        monitor += r"""
    reg diagnostic_completion_seen = 0;
    always @(posedge clk) if (rst_n && done_valid && done_ready &&
                             done_error != 0 && !diagnostic_completion_seen) begin
        diagnostic_completion_seen <= 1;
        $display("ORIGIN cycle=%0d path=%m event=done_error error=%0d",
            diagnostic_cycle, done_error);
    end
"""
    if public_only and all(re.search(r"\b" + port + r"\b", ports)
                          for port in ("clk", "rst_n", "rsp_valid", "rsp_ready", "rsp_error")):
        monitor += r"""
    reg diagnostic_response_seen = 0;
    always @(posedge clk) if (rst_n && rsp_valid && rsp_ready &&
                             rsp_error != 0 && !diagnostic_response_seen) begin
        diagnostic_response_seen <= 1;
        $display("ORIGIN cycle=%0d path=%m event=rsp_error error=%0d",
            diagnostic_cycle, rsp_error);
    end
"""
    if not monitor:
        return None
    monitor = """
    // Diagnostic copy only: these registers are not product allocation state.
    reg [63:0] diagnostic_cycle = 0;
    always @(posedge clk) diagnostic_cycle <= diagnostic_cycle + 1'b1;
""" + monitor
    if original.count("endmodule") != 1:
        raise ValueError(f"diagnostic injection requires one module: {source.name}")
    modified = original.replace("endmodule", monitor + "\nendmodule")
    destination.write_text(modified)
    return {
        "original_sha256": hashlib.sha256(original.encode()).hexdigest(),
        "diagnostic_sha256": hashlib.sha256(modified.encode()).hexdigest(),
        "functional_text_unchanged": modified.replace(monitor + "\n", "") == original,
    }
