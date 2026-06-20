module bucket_cdp::vault;

use bucket_cdp::request::UpdateRequest;
use bucket_cdp::response::UpdateResponse;
use bucket_framework::account::AccountRequest;
use bucket_oracle::result::PriceResult;
use bucket_usdb::usdb::{Treasury, USDB};
use std::option::Option;
use sui::clock::Clock;
use sui::coin::Coin;

public struct Vault<phantom T> has key, store {
    id: UID,
}

public fun debtor_request<T>(
    _vault: &mut Vault<T>,
    _account_request: &AccountRequest,
    _treasury: &Treasury,
    _collateral: Coin<T>,
    _borrow_amount: u64,
    _repay_coin: Coin<USDB>,
    _withdraw_amount: u64,
): UpdateRequest<T> {
    abort 0
}

public fun update_position<T>(
    _vault: &mut Vault<T>,
    _treasury: &mut Treasury,
    _clock: &Clock,
    _price: &Option<PriceResult<T>>,
    _request: UpdateRequest<T>,
    _ctx: &mut TxContext,
): (Coin<T>, Coin<USDB>, UpdateResponse<T>) {
    abort 0
}

public fun destroy_response<T>(
    _vault: &mut Vault<T>,
    _treasury: &Treasury,
    _response: UpdateResponse<T>,
) {
    abort 0
}
