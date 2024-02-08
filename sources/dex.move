module dacadedex::dex {
    // === Imports ===

    use 0x1::Account;
    use 0x1::Token;
    use 0x1::Coin;
    use 0x1::Balance;
    use 0x1::Transaction;
    use 0x1::Vector;
    use 0x1::math::*;
    use 0x1::tx_context::*;

    // === Errors ===

    /// Error code for zero amount supplied.
    pub const E_ZERO_AMOUNT: u64 = 0;

    /// Error code for incorrect fee percentage.
    pub const E_WRONG_FEE: u64 = 1;

    /// Error code for attempting to swap in an empty pool.
    pub const E_RESERVES_EMPTY: u64 = 2;

    /// Error code for zero initial liquidity.
    pub const E_SHARE_FULL: u64 = 3;

    /// Error code for exceeding maximum pool value.
    pub const E_POOL_FULL: u64 = 4;

    // === Constants ===

    /// Integer scaling factor for fee calculation.
    const FEE_SCALING: u128 = 10000;

    /// Maximum value that can be held in a pool balance.
    const MAX_POOL_VALUE: u64 = u64::MAX / FEE_SCALING;

    // === Structs ===

    /// Liquidity pool share token.
    struct LSP;

    /// Liquidity pool.
    struct Pool<T> {
        id: account_address,
        reserve_x: Balance<T>,
        reserve_y: Balance<T>,
        lsp_supply: Balance<LSP>,
        fee_percent: u64,
    }

    // === Public-Mutative Functions ===

    /// Create a new liquidity pool for token T.
    public fun create_pool<T>(
        fee_percent: u64,
        ctx: &mut TxContext,
    ) {
        assert!(fee_percent < 10000, E_WRONG_FEE);

        let lsp_supply = Balance<LSP>::new();
        let pool_id = ctx.get_sender();
        let pool = Pool {
            id: pool_id,
            reserve_x: Balance<T>::new(),
            reserve_y: Balance<T>::new(),
            lsp_supply: lsp_supply,
            fee_percent: fee_percent,
        };

        // Initialize the pool with sender's account.
        Account::create_default_account();
        move_to(pool_id, pool);
    }

    /// Swap token X for token Y.
    public fun swap<T>(
        pool: &mut Pool<T>,
        token_x: Coin<T>,
        ctx: &mut TxContext,
    ) -> Coin<T> {
        let reserve_x = pool.reserve_x.value();
        let reserve_y = pool.reserve_y.value();
        let input_amount = token_x.value();
        assert!(input_amount > 0, E_ZERO_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, E_RESERVES_EMPTY);

        let output_amount = get_output_amount(input_amount, reserve_x, reserve_y, pool.fee_percent);
        pool.reserve_x += input_amount;
        pool.reserve_y -= output_amount;

        Coin::<T>::new(output_amount)
    }

    /// Add liquidity to the pool.
    public fun add_liquidity<T>(
        pool: &mut Pool<T>,
        token_x: Coin<T>,
        token_y: Coin<T>,
        ctx: &mut TxContext,
    ) -> Coin<LSP> {
        let reserve_x = pool.reserve_x.value();
        let reserve_y = pool.reserve_y.value();
        let liquidity_supply = pool.lsp_supply.value();
        let input_amount_x = token_x.value();
        let input_amount_y = token_y.value();

        assert!(input_amount_x > 0 && input_amount_y > 0, E_ZERO_AMOUNT);
        assert!(reserve_x < MAX_POOL_VALUE && reserve_y < MAX_POOL_VALUE, E_POOL_FULL);

        let share = calculate_share(input_amount_x, input_amount_y, reserve_x, reserve_y, liquidity_supply);
        pool.reserve_x += input_amount_x;
        pool.reserve_y += input_amount_y;
        pool.lsp_supply += share;

        Coin::<LSP>::new(share)
    }

    /// Remove liquidity from the pool.
    public fun remove_liquidity<T>(
        pool: &mut Pool<T>,
        lsp_token: Coin<LSP>,
        ctx: &mut TxContext,
    ) -> (Coin<T>, Coin<T>) {
        let reserve_x = pool.reserve_x.value();
        let reserve_y = pool.reserve_y.value();
        let lsp_supply = pool.lsp_supply.value();
        let lsp_amount = lsp_token.value();
        assert!(lsp_amount > 0, E_ZERO_AMOUNT);

        let output_amount_x = (reserve_x * lsp_amount) / lsp_supply;
        let output_amount_y = (reserve_y * lsp_amount) / lsp_supply;
        pool.reserve_x -= output_amount_x;
        pool.reserve_y -= output_amount_y;
        pool.lsp_supply -= lsp_amount;

        (Coin::<T>::new(output_amount_x), Coin::<T>::new(output_amount_y))
    }

    // === Public-View Functions ===

    /// Get the price of token X in terms of token Y.
    public fun price_x_to_y<T>(
        pool: &Pool<T>,
        delta_y: u64,
    ) -> u64 {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_y, reserve_y, reserve_x, pool.fee_percent) // Swapped reserve_y and reserve_x
    }

    public fun price_y_to_x<T>(pool: &Pool<T>, delta_x: u64): u64 {
        let (reserve_x, reserve_y, _) = get_amounts(pool);
        get_input_price(delta_x, reserve_x, reserve_y, pool.fee_percent)
    }


    /// Get most used values in a handy way:
    /// - amount of CoinX
    /// - amount of CoinY
    /// - total supply of LSP
    public fun get_amounts<T>(pool: &Pool<T>): (u64, u64, u64) {
        (
            balance::value(&pool.reserve_x),
            balance::value(&pool.reserve_y),
            balance::supply_value(&pool.lsp_supply)
        )
    }

    /// Calculate the output amount minus the fee - 0.3%
    public fun get_input_price(
        input_amount: u64, input_reserve: u64, output_reserve: u64, fee_percent: u64
    ): u64 {
        // up casts
        let (
            input_amount,
            input_reserve,
            output_reserve,
            fee_percent
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128),
            (fee_percent as u128)
        );

        let input_amount_with_fee = input_amount * (FEE_SCALING - fee_percent);
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * FEE_SCALING) + input_amount_with_fee;

        (numerator / denominator as u64)
    }
}
