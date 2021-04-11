
## Requirements

- NPM

## Installation

1. Install truffle

```bash
npm install truffle -g
```

2. Clone Repo

```bash
git clone https://github.com/properly-finance/ProperlyProtocolZipContracts.git
```

4. Install dependencies by running:

```bash
npm install

# OR...

yarn install
```

## Test

```bash
npm test
```

## Deploy

For deploying to the kovan network, Truffle will use `truffle-hdwallet-provider` for your mnemonic and an RPC URL. Set your environment variables `$RPC_URL`, `$ETHERSCAN_API_KEY` and `$MNEMONIC` before running:

```bash
truffle migrate --network kovan --reset
```
## Verify

To verify the conracts run:
```bash
truffle run verify CollateralAndMint Properlytoken Farm SyntheticToken --network kovan --license MIT
```


