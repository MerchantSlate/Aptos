module MerchantSlate::message {

    /// TODO UPDATE CONTRACT SYNTAX TO ADHERE TO MOVE REQUIREMENTS

    use aptos_framework::coin;
    use aptos_framework::signer;
    use aptos_framework::event;
    use aptos_framework::table;
    use aptos_std::string;
    use std::option;
    use std::vector;

    /// Structs for TokenData, Product, and Payment
    struct TokenData {
        address: address,
        name: String,
        symbol: String,
        decimals: u8,
    }

    struct Product {
        id: u64,
        amount: u64,
        qty: u64,
        qty_cap: bool,
        token: TokenData,
    }

    struct Payment {
        id: u64,
        time: u64,
        prod: u64,
        buyer: address,
        token: TokenData,
        amount: u64,
        qty: u64,
        paid: u64,
        comm: u64,
    }

    struct StakeOffer {
        offer_id: u64,
        owner: address,
        value: u64,
    }

    /// Constants
    const ONE_ETHER: u64 = 1_000_000_000_000_000_000;
    const DEFAULT_DECIMALS: u8 = 18;
    const PERCENT_100: u8 = 100;
    const FEE_DENOM: u64 = 1_000;
    const TOTAL_STAKES: u64 = 10;
    const PRODUCT_FEE: u64 = 1_000_000_000_000_000;
    const MERCHANT_FEE: u64 = 10_000_000_000_000_000;

    /// Storage for product details, merchant mappings, etc.
    struct MerchantSlateStorage has key {
        base_id: u64,
        new_offer_id: u64,
        new_pay_id: u64,
        new_prod_id: u64,
        new_merchant_id: u64,
        in_progress: bool,
        product_details: table::Table<u64, Product>,
        payments: table::Table<u64, Payment>,
        stake_holders: table::Table<address, u64>,
        merchants: table::Table<address, u64>,
        product_merchant: table::Table<u64, address>,
        merchant_products: table::Table<u64, vector<u64>>,
        merchant_payments: table::Table<u64, vector<u64>>,
        buyer_payments: table::Table<address, vector<u64>>,
        stake_offers: table::Table<u64, StakeOffer>,
        stake_holder_addresses: vector<address>,
    }

    /// Initialize the contract
    public fun initialize(account: &signer) {
        let storage = MerchantSlateStorage {
            base_id: 0,
            new_offer_id: 0,
            new_pay_id: 0,
            new_prod_id: 0,
            new_merchant_id: 0,
            in_progress: false,
            product_details: table::new<u64, Product>(),
            payments: table::new<u64, Payment>(),
            stake_holders: table::new<address, u64>(),
            merchants: table::new<address, u64>(),
            product_merchant: table::new<u64, address>(),
            merchant_products: table::new<u64, vector<u64>>(),
            merchant_payments: table::new<u64, vector<u64>>(),
            buyer_payments: table::new<address, vector<u64>>(),
            stake_offers: table::new<u64, StakeOffer>(),
            stake_holder_addresses: vector::empty<address>(),
        };
        table::add(&storage.stake_holders, signer::address_of(account), TOTAL_STAKES);
        vector::push_back(&storage.stake_holder_addresses, signer::address_of(account));
    }

    /// Modifier to check if function is in progress
    fun progress_check(storage: &mut MerchantSlateStorage) {
        assert!(!storage.in_progress, ERROR_TASK_IN_PROGRESS);
        storage.in_progress = true;
    }

    /// Merchant signup function
    public fun merchant_signup(account: &signer) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.merchants, sender) == false);
        table::add(&storage.merchants, sender, storage.new_merchant_id);
        storage.new_merchant_id = storage.new_merchant_id + 1;
        distribute_fee(storage, MERCHANT_FEE);
    }

    /// Add a new product
    public fun add_product(account: &signer, token_address: address, amount: u64, qty: u64) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.merchants, sender));
        let product_id = storage.new_prod_id + 1;
        storage.new_prod_id = product_id;
        let product = Product {
            id: product_id,
            amount: amount,
            qty: qty,
            qty_cap: qty > 0,
        };
        table::add(&storage.product_details, product_id, product);
        distribute_fee(storage, PRODUCT_FEE);
    }

    /// Make a payment for a product
    public fun pay_product(account: &signer, product_id: u64, quantity: u64) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.product_details, product_id));

        let product = table::borrow(&storage.product_details, product_id);
        let total_amount = product.amount * quantity;

        let payment_id = storage.new_pay_id + 1;
        storage.new_pay_id = payment_id;

        let payment = Payment {
            id: payment_id,
            time: 0,
            prod: product_id,
            buyer: sender,
            token: product.token,
            amount: product.amount,
            qty: quantity,
            paid: total_amount,
            comm: 0,
        };

        table::add(&storage.payments, payment_id, payment);
        distribute_fee(storage, total_amount / FEE_DENOM);
    }

    /// Offer stake for sale
    public fun offer_stake(account: &signer, stake_units: u64, value_per_stake: u64) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.stake_holders, sender));

        let offer_id = storage.new_offer_id + 1;
        storage.new_offer_id = offer_id;

        let offer = StakeOffer {
            offer_id: offer_id,
            owner: sender,
            value: value_per_stake,
        };

        table::add(&storage.stake_offers, offer_id, offer);
    }

    /// Transfer stake between accounts
    public fun transfer_stake(account: &signer, recipient: address, stake_units: u64) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.stake_holders, sender));

        let sender_stake = table::borrow_mut(&storage.stake_holders, sender);
        assert!(*sender_stake >= stake_units);
        *sender_stake = *sender_stake - stake_units;

        if (table::contains(&storage.stake_holders, recipient)) {
            let recipient_stake = table::borrow_mut(&storage.stake_holders, recipient);
            *recipient_stake = *recipient_stake + stake_units;
        } else {
            table::add(&storage.stake_holders, recipient, stake_units);
            vector::push_back(&storage.stake_holder_addresses, recipient);
        }
    }

    /// Take stake from the marketplace
    public fun take_stake(account: &signer, offer_id: u64) {
        let sender = signer::address_of(account);
        assert!(table::contains(&storage.stake_offers, offer_id));

        let offer = table::borrow(&storage.stake_offers, offer_id);
        let owner = offer.owner;
        let value = offer.value;

        coin::transfer(&owner, value);
        transfer_stake(account, sender, 1);

        table::remove(&storage.stake_offers, offer_id);
    }

    /// Distribute fees among stakeholders
    fun distribute_fee(storage: &mut MerchantSlateStorage, amount: u64) {
        let total_stakes = TOTAL_STAKES;
        let share = amount / total_stakes;
        let addresses = &storage.stake_holder_addresses;
        let len = vector::length(addresses);

        while (i < len) {
           let addr = *vector::borrow(addresses, i);
            let stake_amount = table::borrow(&storage.stake_holders, addr) * share;
            coin::transfer(&addr, stake_amount);
            i = i + 1;
        }
    }
}