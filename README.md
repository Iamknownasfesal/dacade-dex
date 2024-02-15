# DacadeDEX - Decentralized Exchange Module

DacadeDEX is a decentralized exchange (DEX) module designed for use within the SUI blockchain ecosystem. This module facilitates the creation, management, and execution of token swaps and liquidity provisions in a decentralized manner. Inspired by Uniswap's constant product formula, DacadeDEX ensures fair and efficient trading within the SUI blockchain.

## Features

- **Liquidity Pool Creation:** DacadeDEX allows users to create new liquidity pools for trading different tokens. When creating a pool, users specify the fee percentage for transactions within the pool, ensuring flexibility and customization.

- **Token Swapping:** Users can swap tokens within a liquidity pool, enabling seamless exchange between different token pairs. The swap functionality follows the constant product formula, ensuring liquidity remains balanced.

- **Liquidity Provision:** The module supports the addition of liquidity to existing pools. Users can contribute both tokens in a pair, receiving pool shares in return. This provides an opportunity for users to become liquidity providers and earn fees based on the trading activity in the pool.

- **Liquidity Removal:** Liquidity providers can withdraw their funds from a pool by burning their pool shares. This action returns the corresponding amounts of the tokens initially provided to the liquidity provider.

- **Fee Calculation:** DacadeDEX implements a fee calculation mechanism to ensure fairness and sustainability. The fee percentage is specified during pool creation and affects every swap executed within the pool.


## How to Use

This guide assumes you have a key, already have faucet coins in testnet or devnet and two coins pre deployed.

To build:

```bash
sui move build
```

To publish:

```bash
sui client publish --gas-budget 100000000 --json
```

You can interact with the DacadeDEX module using the sui explorer or with Sui CLI.

To create a new pool:

```bash
sui client call --package $PACKAGE_ID --module dex --function create_pool --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $FEE_PERCENTAGE --gas-budget 10000000000 --json
```

To swap tokens:

```bash
sui client call --package $PACKAGE_ID --module dex --function swap --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $POOL_ID $BASE_COIN_ID --gas-budget 10000000000 --json
```

To add liquidity:

```bash
sui client call --package $PACKAGE_ID --module dex --function add_liquidity --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $POOL_ID $BASE_COIN_ID $QUOTE_COIN_ID --gas-budget 10000000000 --json
```

To remove liquidity:

```bash
sui client call --package $PACKAGE_ID --module dex --function remove_liquidity_ --type-args $BASE_COIN_TYPE $QUOTE_COIN_TYPE --args $POOL_ID $LSP_COIN_ID --gas-budget 10000000000 --json
```
