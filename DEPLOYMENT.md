# Presale Contract Deployment Guide

## Prerequisites

1. Install Foundry (already done ✓)
2. Get Sepolia testnet ETH from a faucet
3. Create accounts on:
   - [Alchemy](https://www.alchemy.com/) or [Infura](https://infura.io/) for RPC access
   - [Etherscan](https://etherscan.io/) for contract verification

## Setup

### 1. Create .env file

Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

### 2. Fill in your environment variables in .env:

```bash
# Get from Alchemy or Infura
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# Your wallet private key (NEVER share this!)
PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE

# Get from Etherscan account
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```

### 3. Load environment variables:
```bash
source .env
```

## Deployment

### Deploy to Sepolia Testnet

```bash
forge script script/DeployPresale.s.sol:DeployPresale \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    -vvvv
```

### Deploy without verification (faster):
```bash
forge script script/DeployPresale.s.sol:DeployPresale \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
```

### Verify contract later:
```bash
forge verify-contract <PROXY_ADDRESS> \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    TransparentUpgradeableProxy
```

## After Deployment

The script will output three addresses:
1. **Implementation**: The logic contract
2. **ProxyAdmin**: Controls upgrades
3. **Proxy**: Main contract address to interact with

### Important Notes

- Use the **Proxy address** for all user interactions
- Keep the **ProxyAdmin address** secure (only owner can upgrade)
- The deployment uses TransparentUpgradeableProxy pattern for upgradeability

### Interact with deployed contract:

```bash
# Start presale (replace <PROXY_ADDRESS> with your actual proxy address)
cast send <PROXY_ADDRESS> "startPresale(uint256)" <END_TIMESTAMP> \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Check if presale started
cast call <PROXY_ADDRESS> "presaleStarted()" --rpc-url $SEPOLIA_RPC_URL

# Get current token price
cast call <PROXY_ADDRESS> "getCurrentTokenPrice()" --rpc-url $SEPOLIA_RPC_URL
```

## Contract Addresses (Sepolia Testnet)

The Presale contract uses these hardcoded addresses:
- USDT: `0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0`
- USDC: `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- PSHIBA: `0xA0F7551c5EfbCDf13A2975F257185aC5D9634dD1`
- Uniswap V2 Router: `0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D`
- Collect Wallet: `0x6De1644863a8fca0eD20dbD76Cff30C44f104dac`

## Troubleshooting

### Insufficient funds
Make sure your deployer address has enough Sepolia ETH. Get testnet ETH from:
- https://sepoliafaucet.com/
- https://www.alchemy.com/faucets/ethereum-sepolia

### RPC errors
If you get RPC errors, try:
- Using a different RPC provider
- Increasing the timeout
- Adding `--legacy` flag if gas estimation fails

### Verification fails
If verification fails during deployment:
1. Deploy without `--verify` flag first
2. Verify manually using `forge verify-contract` command

## Security Reminders

⚠️ **NEVER commit your .env file to git**
⚠️ **NEVER share your private key**
⚠️ **Use a separate wallet for testnet deployments**
