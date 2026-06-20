module bucket_saving_incentive::saving_incentive;

use bucket_saving::saving::{DepositResponse, SavingPool, WithdrawResponse};
use bucket_saving_incentive::incentive_config::GlobalConfig;
use sui::clock::Clock;

public struct RewardManager<phantom LP> has key, store {
    id: UID,
}

public struct DepositResponseChecker<phantom LP> {}

public struct WithdrawResponseChecker<phantom LP> {}

public fun new_checker_for_deposit_action<LP>(
    _reward_manager: &RewardManager<LP>,
    _config: &GlobalConfig,
    _response: DepositResponse<LP>,
): DepositResponseChecker<LP> {
    abort 0
}

public fun update_deposit_action<LP, Reward>(
    _checker: &mut DepositResponseChecker<LP>,
    _config: &GlobalConfig,
    _reward_manager: &mut RewardManager<LP>,
    _pool: &SavingPool<LP>,
    _clock: &Clock,
) {
    abort 0
}

public fun destroy_deposit_checker<LP>(
    _checker: DepositResponseChecker<LP>,
    _config: &GlobalConfig,
): DepositResponse<LP> {
    abort 0
}

public fun new_checker_for_withdraw_action<LP>(
    _reward_manager: &RewardManager<LP>,
    _config: &GlobalConfig,
    _response: WithdrawResponse<LP>,
): WithdrawResponseChecker<LP> {
    abort 0
}

public fun update_withdraw_action<LP, Reward>(
    _checker: &mut WithdrawResponseChecker<LP>,
    _config: &GlobalConfig,
    _reward_manager: &mut RewardManager<LP>,
    _pool: &SavingPool<LP>,
    _clock: &Clock,
) {
    abort 0
}

public fun destroy_withdraw_checker<LP>(
    _checker: WithdrawResponseChecker<LP>,
    _config: &GlobalConfig,
): WithdrawResponse<LP> {
    abort 0
}
