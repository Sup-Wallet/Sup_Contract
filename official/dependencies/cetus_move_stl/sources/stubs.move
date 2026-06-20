module move_stl::random {
    public struct Random has key, store {
        id: UID,
    }
}

module move_stl::option_u64 {
    public struct OptionU64 has copy, drop, store {}
}

module move_stl::option_u128 {
    public struct OptionU128 has copy, drop, store {}
}

module move_stl::linked_table {
    public struct LinkedTable<phantom K: copy + drop + store, phantom V: store> has key, store {
        id: UID,
    }

    public struct Node<phantom K: copy + drop + store, phantom V: store> has store {}
}

module move_stl::skip_list {
    public struct SkipList<phantom K: copy + drop + store, phantom V: store> has key, store {
        id: UID,
    }

    public struct Node<phantom K: copy + drop + store, phantom V: store> has store {}

    public struct Item<phantom K: copy + drop + store, phantom V: store> has store {}
}

module move_stl::skip_list_u128 {
    public struct SkipList<phantom V: store> has key, store {
        id: UID,
    }

    public struct SkipListNode<phantom V: store> has store {}

    public struct Item<phantom V: store> has store {}
}
