# Spending Guard Smart Account

ERC-4337 smart account with policy controls (daily caps, allowlists, freeze) and session keys. Frontend is a console for Arbitrum Sepolia.

## Prereqs

- Node.js 20+
- pnpm
- Foundry (`forge`) for tests

## Install

```sh
pnpm install
```

## Contracts

Compile with Hardhat:

```sh
pnpm hardhat compile
```

Run Foundry tests:

```sh
/home/alexwormbs/.foundry/bin/forge test
```

## Frontend (Svelte 5 runes)

Start the dev server:

```sh
pnpm dev
```

Required inputs in the UI:

- RPC URL (Arbitrum Sepolia)
- Bundler URL (ERC-4337 RPC)
- EntryPoint address
- PolicyManager address
- SessionKeyManager address
- SmartAccount address

Optional: toggle "Use session key for signing" after creating one.

## Deploy contracts (Arbitrum Sepolia)

Set env vars (example):

```sh
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
export ARBITRUM_SEPOLIA_PRIVATE_KEY="0x..."
export ENTRYPOINT_ADDRESS="0x..."
export OWNER_ADDRESS="0x..." # optional, defaults to deployer
```

Deploy:

```sh
pnpm hardhat compile
pnpm hardhat run scripts/deploy.ts --network arbitrumSepolia
```

This prints the deployed `PolicyManager`, `SessionKeyManager`, and `SmartAccount` addresses.

## Demo flows

- **Landing**: connect wallet, paste addresses, fund the smart account
- **Policies**: set daily cap, allowlist targets/selectors, freeze/unfreeze
- **Session Keys**: generate a key, set scope/expiry, create/revoke
- **Actions**: send ETH, call DemoDapp.safeFunction(), attempt malicious call
- **UserOp Monitor**: submit ops to the bundler, refresh status
