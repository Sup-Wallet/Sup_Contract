module magma_clmm::acl {
    use move_stl::linked_table::{Self, LinkedTable};

    const ErrInvalidRole: u64 = 1;

    public struct ACL has store {
        permissions: LinkedTable<address, u128>,
    }

    public struct Member has copy, drop, store {
        address: address,
        permission: u128,
    }

    public fun new(_ctx: &mut TxContext): ACL {
        abort (0)
    }

    public fun add_role(_acl: &mut ACL, _member: address, _role: u8) {
        abort (0)
    }

    public fun get_members(_acl: &ACL): vector<Member> {
        abort (0)
    }

    public fun get_permission(_acl: &ACL, _member: address): u128 {
        abort (0)
    }

    public fun has_role(_acl: &ACL, _member: address, _role: u8): bool {
        abort (0)
    }

    public fun remove_member(_acl: &mut ACL, _member: address) {
        abort (0)
    }

    public fun remove_role(_acl: &mut ACL, _member: address, _role: u8) {
        abort (0)
    }

    public fun set_roles(_acl: &mut ACL, _member: address, _roles: u128) {
        abort (0)
    }
}
