// === Imports ===

use sui::object::{Self, UID};
use sui::coin::{Self, Coin};
use sui::balance::{Self, Supply, Balance};
use sui::transfer;
use sui::math;
use sui::tx_context::{Self, TxContext};

// === Errors ===

/// Error code for when supplied Coin is zero.
const E_ZERO_AMOUNT: u64 = 0;

/// Error code for when pool fee is set incorrectly.
/// Allowed values are: [0-10000).
const E_WRONG_FEE: u64 = 1;

/// Error code for when someone tries to swap in an empty pool.
const E_RESERVES_EMPTY: u64 = 2;

/// Error code for when initial LSP amount is zero.
const E_SHARE_FULL: u64 = 3;

/// Error code for when someone attempts to add more liquidity than allowed.
const E_POOL_FULL: u64 = 4;

// === Constants ===

/// The integer scaling setting for fees calculation.
const FEE_SCALING: u128 = 10000;

/// The maximum value that can be held in one of the Balances of a Pool.
const MAX_POOL_VALUE: u64 = 18446744073709551615 / 10000;

// === Structs ===

/// The Pool token that marks the pool share of a liquidity provider.
struct LSP<X, Y> has drop {}

/// The pool with exchange.
///
/// - `fee_percent` should be in the range: [0-10000), meaning that 1000 is 10% and 1 is 0.01%.
struct Pool<X, Y> has key {
    id: UID,
    reserve_x: Balance<X>,
    reserve_y: Balance<Y>,
    lsp_supply: Supply<LSP<X, Y>>,
    fee_percent: u64,
}

// === Init Function ===

fun init(_: &mut TxContext) {}

// === Public-Mutative Functions ===

/// Create a new `Pool` for token `X` and token `Y`.
///
/// Share is calculated based on Uniswap's constant product formula:
/// liquidity = sqrt(X * Y)
public entry fun create_pool<X, Y>(
    fee_percent: u64,
    ctx: &mut TxContext,
) {
    assert!(fee_percent < 10000, E_WRONG_FEE);

    let lsp_supply = balance::create_supply(LSP<X, Y> {});
    transfer::share_object(Pool {
        id: object::new(ctx),
        reserve_x: balance::zero<X>(),
        reserve_y: balance::zero<Y>(),
        lsp_supply,
        fee_percent,
    });
}

/// Create a new `Pool` for token `X` and token `Y` directly by providing initial amounts.
/// Returns the pool share.
public fun create_pool_direct<X, Y>(
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    fee_percent: u64,
    ctx: &mut TxContext,
): Coin<LSP<X, Y>> {
    assert!(coin::value(&coin_x) > 0 && coin::value(&coin_y) > 0, E_ZERO_AMOUNT);
    assert!(coin::value(&coin_x) < MAX_POOL_VALUE && coin::value(&coin_y) < MAX_POOL_VALUE, E_POOL_FULL);
    assert!(fee_percent < 10000, E_WRONG_FEE);

    let share = math::sqrt(coin::value(&coin_x) * coin::value(&coin_y));
    let lsp_supply = balance::create_supply(LSP<X, Y> {});
    let lsp = balance::increase_supply(&mut lsp_supply, share);

    transfer::share_object(Pool {
        id: object::new(ctx),
        reserve_x: coin::into_balance(coin_x),
        reserve_y: coin::into_balance(coin_y),
        lsp_supply,
        fee_percent,
    });

    coin::from_balance(lsp, ctx)
}

/// Swap token `X` for token `Y`.
/// Returns the amount of token `Y` received.
public entry fun swap_x_to_y<X, Y>(
    pool: &mut Pool<X, Y>,
    coin_x: Coin<X>,
    ctx: &mut TxContext,
): Coin<Y> {
    let output_amount = swap_x_to_y_direct(pool, coin_x, ctx);
    coin::from_balance(output_amount, ctx)
}

/// Swap token `Y` for token `X`.
/// Returns the amount of token `X` received.
public entry fun swap_y_to_x<X, Y>(
    pool: &mut Pool<X, Y>,
    coin_y: Coin<Y>,
    ctx: &mut TxContext,
): Coin<X> {
    let output_amount = swap_y_to_x_direct(pool, coin_y, ctx);
    coin::from_balance(output_amount, ctx)
}

/// Add liquidity to the pool and return the pool share.
public fun add_liquidity<X, Y>(
    pool: &mut Pool<X, Y>,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    ctx: &mut TxContext,
): Coin<LSP<X, Y>> {
    assert!(coin::value(&coin_x) > 0 && coin::value(&coin_y) > 0, E_ZERO_AMOUNT);
    assert!(coin::value(&coin_x) < MAX_POOL_VALUE && coin::value(&coin_y) < MAX_POOL_VALUE, E_POOL_FULL);

    let (reserve_x, reserve_y, lsp_supply) = get_amounts(pool);

    let x_added = coin::value(&coin_x);
    let y_added = coin::value(&coin_y);
    let share_minted = if reserve_x * reserve_y > 0 {
        math::min(
            x_added * lsp_supply / reserve_x,
            y_added * lsp_supply / reserve_y,
        )
    } else {
        math::sqrt(x_added) * math::sqrt(y_added)
    };

    let coin_amount_x = balance::join(&mut pool.reserve_x, coin::into_balance(coin_x));
    let coin_amount_y = balance::join(&mut pool.reserve_y, coin::into_balance(coin_y));

    assert!(coin_amount_x < MAX_POOL_VALUE, E_POOL_FULL);
    assert!(coin_amount_y < MAX_POOL_VALUE, E_POOL_FULL);

    let balance = balance::increase_supply(&mut pool.lsp_supply, share_minted);
    coin::from_balance(balance, ctx)
}

/// Remove liquidity from the `Pool` by burning `Coin<LSP>`.
/// Returns `Coin<X>` and `Coin<Y>`.
public fun remove_liquidity<X, Y>(
    pool: &mut Pool<X, Y>,
    lsp: Coin<LSP<X, Y>>,
    ctx: &mut TxContext,
): (Coin<X>, Coin<Y>) {
    let lsp_amount = coin::value(&lsp);

    assert!(lsp_amount > 0, E_ZERO_AMOUNT);

    let (reserve_x, reserve_y, lsp_supply) = get_amounts(pool);
    let x_removed = reserve_x * lsp_amount / lsp_supply;
    let y_removed = reserve_y * lsp_amount / lsp_supply;

    balance::decrease_supply(&mut pool.lsp_supply, coin::into_balance(lsp));

    (
        coin::take(&mut pool.reserve_x, x_removed, ctx),
        coin::take(&mut pool.reserve_y, y_removed, ctx),
    )
}

// === Public-View Functions ===

/// Public getter for the price of Y in X.
public fun price_x_to_y<X, Y>(pool: &Pool<X, Y>, delta_y: u64): u64 {
    let (reserve_x, reserve_y, _) = get_amounts(pool);
    get_input_price(delta_y, reserve_y, reserve_x, pool.fee_percent)
}

/// Public getter for the price of X in Y.
public fun price_y_to_x<X, Y>(pool: &Pool<X, Y>, delta_x: u64): u64 {
    let (reserve_x, reserve_y, _) = get_amounts(pool);
    get_input_price(delta_x, reserve_x, reserve_y, pool.fee_percent)
}

/// Get the amounts of CoinX, CoinY, and total supply of LSP.
public fun get_amounts<X, Y>(pool: &Pool<X, Y>): (u64, u64, u64) {
    (
        balance::value(&pool.reserve_x),
        balance::value(&pool.reserve_y),
        balance::supply_value(&pool.lsp_supply),
    )
}

/// Calculate the output amount minus the fee.
public fun get_input_price(
    input_amount: u64, input_reserve: u64, output_reserve: u64, fee_percent: u64
): u64 {
    let input_amount = input_amount as u128;
    let input_reserve = input_reserve as u128;
    let output_reserve = output_reserve as u128;
    let fee_percent = fee_percent as u128;

    let input_amount_with_fee = input_amount * (FEE_SCALING - fee_percent);
    let numerator = input_amount_with_fee * output_reserve;
    let denominator = input_reserve * FEE_SCALING + input_amount_with_fee;

    (numerator / denominator as u64)
}
