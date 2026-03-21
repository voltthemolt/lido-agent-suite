#!/bin/bash
# Deploy AgentTreasury to Ethereum Mainnet
# Requires: MAINNET_RPC_URL and PRIVATE_KEY in .env
# Requires: ~0.01 ETH for deployment gas

set -e

cd "$(dirname "$0")/.."

# Check for required env vars
if [ -z "$MAINNET_RPC_URL" ]; then
    echo "Error: MAINNET_RPC_URL not set"
    echo "Add to .env: MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set"
    echo "Add to .env: PRIVATE_KEY=your_private_key"
    exit 1
fi

# Check balance
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY 2>/dev/null)
BALANCE=$(cast balance $DEPLOYER --rpc-url $MAINNET_RPC_URL 2>/dev/null)
echo "Deployer: $DEPLOYER"
echo "Balance: $(cast from-wei $BALANCE) ETH"

if [ "$BALANCE" -lt 5000000000000000 ]; then
    echo "Error: Insufficient balance. Need at least 0.005 ETH for deployment."
    exit 1
fi

# Estimate gas
echo "Estimating deployment gas..."
GAS=$(cast estimate --rpc-url $MAINNET_RPC_URL --from $DEPLOYER --create $(cat src/AgentTreasury.sol | forge build --silent && cat out/AgentTreasury.sol/AgentTreasury.json | jq -r '.bytecode.object') "" 2>/dev/null || echo "3000000")
echo "Estimated gas: $GAS"

# Deploy
echo "Deploying AgentTreasury to mainnet..."
forge script script/DeployMainnet.s.sol:DeployMainnet \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv

echo "Deployment complete!"
