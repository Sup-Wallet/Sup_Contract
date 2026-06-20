module bucket_framework::account;

use std::option::Option;
use std::string::String;

public struct ACCOUNT has drop {}

public struct Account has key, store {
    id: UID,
}

public struct AccountRequest has drop {}

public fun new(_name: Option<String>, _ctx: &mut TxContext): Account {
    abort 0
}

public fun request_with_account(_account: &Account): AccountRequest {
    abort 0
}

public fun account_address(_account: &Account): address {
    abort 0
}
