module SupSubscription::subscription {
    use std::ascii::{String as AsciiString};
    use std::string::String;
    use sui::{
        object::{Self, UID, ID},
        transfer,
        tx_context::TxContext,
        event,
        clock::Clock,
    };
    use std::option;
    use payment_kit::payment_kit::{Self as paykit, PaymentRegistry};
    use SupWallet::wallet::{Self, Wallet};
    use SupWallet::intent;

    const EChargeDateNotPassed: u64 = 0;
    const EWrongServiceId: u64 = 1;
    const EYearlyPctOutOfRange: u64 = 2;
    const ENotYourWallet: u64 = 18;
    const ENotServiceOwner: u64 = 19;

    const THIRTY_DAYS: u64 = 30 * 24 * 60 * 60 * 1000;
    const THREE_SIX_FIVE_DAYS: u64 = 365 * 24 * 60 * 60 * 1000;

    /// SubscriptionService witness — used to authenticate the module to `intent` and to
    /// `wallet::grant_service_coin`. `has drop` is fine because the hot-potato flow in
    /// `intent` (not the witness itself) is what enforces request → pay → verify.
    public struct SubscriptionService has drop {}

    public struct ServiceCap has key, store {
        id: UID,
        service_id: ID,
    }

    /// `yearly_price_pct` is the percentage of (price * 12) charged for an annual subscription.
    /// 100 = full price (no discount); 90 = 10% off; etc. Range enforced 0..=100 at creation.
    public struct Service<phantom CoinType> has key {
        id: UID,
        price: u64,
        service_name: String,
        service_owner: address,
        yearly_price_pct: u8,
    }

    public struct Receipt<phantom CoinType> has key, store {
        id: UID,
        serviceID: ID,
        expire_date: u64,
        receipt_owner: address,
        paid_amount: u64,
    }

    public struct ChargeCap has key, store {
        id: UID,
        walletID: ID,
        serviceID: ID,
        charge_date: u64,
        is_year: bool,
        subscriber: address,
    }

    /// ===== events =====

    public struct ServiceCreated has copy, drop {
        service_id: ID,
        service_owner: address,
        price: u64,
    }

    public struct Subscribed has copy, drop {
        wallet_id: ID,
        service_id: ID,
        payment_registry: ID,
        payment_nonce: AsciiString,
        subscriber: address,
        is_year: bool,
        amount_paid: u64,
        next_charge_date: u64,
    }

    public struct FeeCharged has copy, drop {
        wallet_id: ID,
        service_id: ID,
        payment_registry: ID,
        payment_nonce: AsciiString,
        subscriber: address,
        amount_paid: u64,
        next_charge_date: u64,
    }

    /// create a subscription service
    public fun create_service<CoinType>(
        price: u64,
        service_name: String,
        service_owner: address,
        yearly_price_pct: u8,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == service_owner, ENotServiceOwner);
        assert!(yearly_price_pct <= 100, EYearlyPctOutOfRange);

        let service = Service<CoinType> {
            id: object::new(ctx),
            price,
            service_name,
            service_owner,
            yearly_price_pct,
        };
        let service_id = object::id(&service);
        let service_cap = ServiceCap {
            id: object::new(ctx),
            service_id,
        };
        transfer::public_transfer(service_cap, service_owner);
        transfer::share_object(service);

        event::emit(ServiceCreated { service_id, service_owner, price });
    }

    fun create_receipt<CoinType>(service: &Service<CoinType>, paid_amount: u64, expire_date: u64, ctx: &mut TxContext): Receipt<CoinType> {
        Receipt<CoinType> {
            id: object::new(ctx),
            serviceID: object::id(service),
            receipt_owner: ctx.sender(),
            expire_date,
            paid_amount,
        }
    }

    /// Delegate subscribes on behalf of the wallet — Mode A intent flow.
    /// authorisation is the (a) service-coin allowlist entry the owner installed via
    /// `grant_service_coin` and (b) the per-delegate allowance the owner set via
    /// `delegate::set_service_allowance` + `delegate::set_coin_allowance`.
    /// `ctx.sender()` is the agent and pays from their own allowance under `SubscriptionService`.
    public fun subscribe<CoinType>(
        wallet: &mut Wallet,
        service: &Service<CoinType>,
        registry: &mut PaymentRegistry,
        payment_nonce: AsciiString,
        is_year: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let (payment_amount, next_date) = compute_payment(service, is_year, clock.timestamp_ms());
        let subscriber = ctx.sender();
        let recipient = service.service_owner;
        let payment_registry = object::id(registry);

        let sig = intent::request_payment<SubscriptionService, CoinType>(
            SubscriptionService {},
            payment_amount,
            recipient,
        );
        let (payment, wallet_witness) = intent::validate_and_pay<SubscriptionService, CoinType>(
            wallet,
            sig,
            ctx,
        );
        let _payment_receipt = paykit::process_registry_payment<CoinType>(
            registry,
            payment_nonce,
            payment_amount,
            payment,
            option::some(recipient),
            clock,
            ctx,
        );

        let receipt_sig = intent::create_receipt_sig<SubscriptionService, CoinType>(
            SubscriptionService {},
            payment_amount,
            recipient,
        );
        intent::verify_and_clear(wallet_witness, receipt_sig);

        let charge_cap = ChargeCap {
            id: object::new(ctx),
            walletID: object::id(wallet),
            serviceID: object::id(service),
            charge_date: next_date,
            is_year,
            subscriber,
        };
        transfer::public_transfer(charge_cap, service.service_owner);

        let receipt = create_receipt(service, payment_amount, next_date, ctx);
        transfer::public_transfer(receipt, subscriber);

        event::emit(Subscribed {
            wallet_id: object::id(wallet),
            service_id: object::id(service),
            payment_registry,
            payment_nonce,
            subscriber,
            is_year,
            amount_paid: payment_amount,
            next_charge_date: next_date,
        });
    }

    /// Service owner charges recurring fee — Mode B intent flow.
    /// Sender (caller) is the service owner; the allowance debit targets the original subscriber.
    public fun charge_fee<CoinType>(
        charge_cap: &mut ChargeCap,
        wallet: &mut Wallet,
        service: &Service<CoinType>,
        registry: &mut PaymentRegistry,
        payment_nonce: AsciiString,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == service.service_owner, ENotServiceOwner);
        assert!(clock.timestamp_ms() > charge_cap.charge_date, EChargeDateNotPassed);
        assert!(charge_cap.walletID == object::id(wallet), ENotYourWallet);
        assert!(charge_cap.serviceID == object::id(service), EWrongServiceId);

        let (payment_amount, _) = compute_payment(service, charge_cap.is_year, charge_cap.charge_date);
        if (charge_cap.is_year) {
            charge_cap.charge_date = charge_cap.charge_date + THREE_SIX_FIVE_DAYS;
        } else {
            charge_cap.charge_date = charge_cap.charge_date + THIRTY_DAYS;
        };

        let recipient = service.service_owner;
        let payment_registry = object::id(registry);

        let sig = intent::request_payment_for_payer<SubscriptionService, CoinType>(
            SubscriptionService {},
            payment_amount,
            recipient,
            charge_cap.subscriber,
        );
        let (payment, wallet_witness) = intent::validate_and_pay_for_payer<SubscriptionService, CoinType>(
            wallet,
            sig,
            ctx,
        );
        let _payment_receipt = paykit::process_registry_payment<CoinType>(
            registry,
            payment_nonce,
            payment_amount,
            payment,
            option::some(recipient),
            clock,
            ctx,
        );

        let receipt_sig = intent::create_receipt_sig<SubscriptionService, CoinType>(
            SubscriptionService {},
            payment_amount,
            recipient,
        );
        intent::verify_and_clear(wallet_witness, receipt_sig);

        let receipt = create_receipt(service, payment_amount, charge_cap.charge_date, ctx);
        transfer::public_transfer(receipt, charge_cap.subscriber);

        event::emit(FeeCharged {
            wallet_id: object::id(wallet),
            service_id: object::id(service),
            payment_registry,
            payment_nonce,
            subscriber: charge_cap.subscriber,
            amount_paid: payment_amount,
            next_charge_date: charge_cap.charge_date,
        });
    }

    /// Returns (amount_to_pay, next_charge_date_after_this_payment).
    fun compute_payment<CoinType>(service: &Service<CoinType>, is_year: bool, base_time: u64): (u64, u64) {
        if (is_year) {
            let amount = service.price * 12 * (service.yearly_price_pct as u64) / 100;
            (amount, base_time + THREE_SIX_FIVE_DAYS)
        } else {
            (service.price, base_time + THIRTY_DAYS)
        }
    }

    /// ===== getters =====

    public fun get_service_price<CoinType>(service: &Service<CoinType>): u64 {
        service.price
    }

    public fun get_service_name<CoinType>(service: &Service<CoinType>): String {
        service.service_name
    }

    public fun get_service_owner<CoinType>(service: &Service<CoinType>): address {
        service.service_owner
    }

    public fun get_yearly_price_pct<CoinType>(service: &Service<CoinType>): u8 {
        service.yearly_price_pct
    }
}
