// Copyright 2020-present Open Networking Foundation
// SPDX-License-Identifier: Apache-2.0

#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "shared/define.p4"
#include "shared/header.p4"

control Acl (inout ingress_headers_t hdr,
             inout fabric_ingress_metadata_t fabric_md,
             in ingress_intrinsic_metadata_t ig_intr_md,
             inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
             inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm) {

    FabricPortId_t ig_port = (FabricPortId_t)ig_intr_md.ingress_port;
    /*
     * ACL Table.
     */
    DirectCounter<bit<64>>(CounterType_t.PACKETS_AND_BYTES) acl_counter;

    action set_next_id_acl(next_id_t next_id) {
        fabric_md.next_id = next_id;
        acl_counter.count();
        // FIXME: We have to rewrite other fields to perform correct override action
        // e.g. forwarding type == "ROUTING" while we want to override the action to "BRIDGE" in NEXT table
        ig_intr_md_for_dprsr.drop_ctl = 0;
        fabric_md.skip_next = false;
    }

    action copy_to_cpu_post_ingress() {
        ig_intr_md_for_tm.copy_to_cpu = 1;
        acl_counter.count();
    }

    action punt_to_cpu_post_ingress() {
        copy_to_cpu_post_ingress();
        ig_intr_md_for_dprsr.drop_ctl = 1;
        fabric_md.skip_next = true;
        fabric_md.punt_to_cpu = true;
    }

    action copy_to_cpu() {
#if __TARGET_TOFINO__ == 2
        ig_intr_md_for_dprsr.mirror_type = (bit<4>)FabricMirrorType_t.PACKET_IN;
#else
        ig_intr_md_for_dprsr.mirror_type = (bit<3>)FabricMirrorType_t.PACKET_IN;
#endif    
        fabric_md.mirror.bmd_type = BridgedMdType_t.INGRESS_MIRROR;
        fabric_md.mirror.mirror_session_id = PACKET_IN_MIRROR_SESSION_ID;
        acl_counter.count();
    }

    action punt_to_cpu() {
        copy_to_cpu();
        ig_intr_md_for_dprsr.drop_ctl = 1;
        fabric_md.skip_next = true;
        fabric_md.punt_to_cpu = true;
    }

    action drop() {
        ig_intr_md_for_dprsr.drop_ctl = 1;
        fabric_md.skip_next = true;
#ifdef WITH_INT
        fabric_md.bridged.int_bmd.drop_reason = IntDropReason_t.DROP_REASON_ACL_DENY;
#endif // WITH_INT
        acl_counter.count();
    }

    /*
     * The next_mpls and next_vlan tables are applied before the acl table.
     * So, if this action is applied, even though skip_next is set to true
     * the packet might get forwarded with unexpected MPLS and VLAG tags.
     */
    action set_output_port(FabricPortId_t port_num) {
        ig_intr_md_for_tm.ucast_egress_port = (PortId_t)port_num;
        fabric_md.egress_port_set = true;
        fabric_md.skip_next = true;
        acl_counter.count();
        // FIXME: If the forwarding type is ROUTING, although we have overriden the action to Bridging here
        // ttl will still -1 in the egress pipeline
        ig_intr_md_for_dprsr.drop_ctl = 0;
    }

    action nop_acl() {
        acl_counter.count();
    }

    table acl {
        key = {
            ig_port                  : ternary @name("ig_port");   // 9
            fabric_md.lkp.eth_dst    : ternary @name("eth_dst");   // 48
            fabric_md.lkp.eth_src    : ternary @name("eth_src");   // 48
            fabric_md.lkp.vlan_id    : ternary @name("vlan_id");   // 12
            fabric_md.lkp.eth_type   : ternary @name("eth_type");  // 16
            fabric_md.lkp.ipv4_src   : ternary @name("ipv4_src");  // 32
            fabric_md.lkp.ipv4_dst   : ternary @name("ipv4_dst");  // 32
            fabric_md.lkp.ip_proto   : ternary @name("ip_proto");  // 8
            fabric_md.lkp.icmp_type  : ternary @name("icmp_type"); // 8
            fabric_md.lkp.icmp_code  : ternary @name("icmp_code"); // 8
            fabric_md.lkp.l4_sport   : ternary @name("l4_sport");  // 16
            fabric_md.lkp.l4_dport   : ternary @name("l4_dport");  // 16
            fabric_md.ig_port_type   : ternary @name("ig_port_type"); // 2
        }

        actions = {
            set_next_id_acl;
            punt_to_cpu;
            copy_to_cpu;
            punt_to_cpu_post_ingress;
            copy_to_cpu_post_ingress;
            drop;
            set_output_port;
            nop_acl;
        }

        const default_action = nop_acl();
        size = ACL_TABLE_SIZE;
        counters = acl_counter;
    }

    apply {
        acl.apply();
    }
}
