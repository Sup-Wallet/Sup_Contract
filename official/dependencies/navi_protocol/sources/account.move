module navi_protocol::account;

public struct AccountCap has key, store {
    id: UID,
    owner: address,
}

public fun account_owner(_account_cap: &AccountCap): address {
    abort 0
}
