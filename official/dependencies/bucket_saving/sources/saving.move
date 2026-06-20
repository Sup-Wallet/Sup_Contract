module bucket_saving::saving;

use bucket_framework::account::AccountRequest;
use bucket_usdb::usdb::{Treasury, USDB};
use sui::clock::Clock;
use sui::coin::Coin;

public struct SavingPool<phantom LP> has key, store {
    id: UID,
}

public struct DepositResponse<phantom LP> {}

public struct WithdrawResponse<phantom LP> {}

public fun deposit<LP>(
    _pool: &mut SavingPool<LP>,
    _treasury: &mut Treasury,
    _account: address,
    _coin: Coin<USDB>,
    _clock: &Clock,
    _ctx: &mut TxContext,
): DepositResponse<LP> {
    abort 0
}

public fun withdraw<LP>(
    _pool: &mut SavingPool<LP>,
    _treasury: &mut Treasury,
    _account_request: &AccountRequest,
    _amount: u64,
    _clock: &Clock,
    _ctx: &mut TxContext,
): (Coin<USDB>, WithdrawResponse<LP>) {
    abort 0
}

public fun check_deposit_response<LP>(
    _response: DepositResponse<LP>,
    _pool: &mut SavingPool<LP>,
    _treasury: &Treasury,
) {
    abort 0
}

public fun check_withdraw_response<LP>(
    _response: WithdrawResponse<LP>,
    _pool: &mut SavingPool<LP>,
    _treasury: &Treasury,
) {
    abort 0
}

public fun deposit_response_deposited_usdb_amount<LP>(
    _response: &DepositResponse<LP>,
): u64 {
    abort 0
}

public fun withdraw_response_withdrawal_usdb_amount<LP>(
    _response: &WithdrawResponse<LP>,
): u64 {
    abort 0
}
