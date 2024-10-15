# TEST OF THE SENDANDCALL FUNCTION IN THE AVALANCHEICTTROUTER

## Set the environnement

Follow the instructions of this [branch](https://github.com/AshAvalanche/awm-dev-env/tree/update-bridge-ui) of the `awm-dev-env` repo until the router deployment part and switch to this one.

## Deploy the router on the source and destination chains

```bash
forge script --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	script/Teleporter/Router/DeployAvalancheICTTRouter.s.sol:DeployAvalancheICTTRouter \
	--broadcast --skip-simulation

export TOKEN_BRIDGE_ROUTER_HOME=$(jq -r '.returns."0".value' broadcast/DeployAvalancheICTTRouter.s.sol/$HOME_CHAIN_ID/run-latest.json)

forge script --rpc-url "$REMOTE_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	script/Teleporter/Router/DeployAvalancheICTTRouter.s.sol:DeployAvalancheICTTRouter \
	--broadcast --skip-simulation

export TOKEN_BRIDGE_ROUTER_REMOTE=$(jq -r '.returns."0".value' broadcast/DeployAvalancheICTTRouter.s.sol/$REMOTE_CHAIN_ID/run-latest.json)
```

## Register the bridge instances

```bash
export IS_MULTIHOP=false

# ERC20
cast send --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_HOME" \
	'registerSourceTokenBridge(address,address)' \
	"$ERC20_TOKEN_CONTRACT_ADDR" "$BRIDGE_HOME_ADDR"

cast send --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_HOME" \
	'registerDestinationTokenBridge(address,bytes32,address,uint256,bool)' \
	"$ERC20_TOKEN_CONTRACT_ADDR" "$REMOTE_CHAIN_HEX" "$BRIDGE_REMOTE_ADDR" "$REQUIRED_GAS_LIMIT" "$IS_MULTIHOP"

cast send --rpc-url "$REMOTE_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_REMOTE" \
	'registerSourceTokenBridge(address,address)' \
	"$BRIDGE_REMOTE_ADDR" "$BRIDGE_REMOTE_ADDR"

cast send --rpc-url "$REMOTE_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_REMOTE" \
	'registerDestinationTokenBridge(address,bytes32,address,uint256,bool)' \
	"$BRIDGE_REMOTE_ADDR" "$HOME_CHAIN_HEX" "$BRIDGE_HOME_ADDR" "$REQUIRED_GAS_LIMIT" "$IS_MULTIHOP"

# Native
export ADDR_0=0x0000000000000000000000000000000000000000

cast send --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_HOME" \
	'registerSourceTokenBridge(address,address)' \
	"$ADDR_0" "$BRIDGE_HOME_ADDR"

cast send --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_HOME" \
	'registerDestinationTokenBridge(address,bytes32,address,uint256,bool)' \
	"$ADDR_0" "$REMOTE_CHAIN_HEX" "$BRIDGE_REMOTE_ADDR" "$REQUIRED_GAS_LIMIT" "$IS_MULTIHOP"

cast send --rpc-url "$REMOTE_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_REMOTE" \
	'registerSourceTokenBridge(address,address)' \
	"$ADDR_0" "$BRIDGE_REMOTE_ADDR"

cast send --rpc-url "$REMOTE_CHAIN_RPC" \
	--private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
	"$TOKEN_BRIDGE_ROUTER_REMOTE" \
	'registerDestinationTokenBridge(address,bytes32,address,uint256,bool)' \
	"$ADDR_0" "$HOME_CHAIN_HEX" "$BRIDGE_HOME_ADDR" "$REQUIRED_GAS_LIMIT" "$IS_MULTIHOP"
```

## Create the mock smart contract you want to interact with on the destination chain

```bash
# ERC20
export USERS_MOCK_CONTRACT=$(
  forge create --rpc-url "$REMOTE_CHAIN_RPC" \
    --private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
    src/contracts/mocks/UsersMock.sol:ERC20UsersMock --json | jq -r '.deployedTo'
)

# Native
export USERS_MOCK_CONTRACT=$(
  forge create --rpc-url "$REMOTE_CHAIN_RPC" \
    --private-key "$BRIDGE_DEPLOYER_PRIV_KEY" \
    src/contracts/mocks/UsersMock.sol:NativeUsersMock --json | jq -r '.deployedTo'
)
```

## Use the test script to call the router function to interact with it

```bash
# set the bool param to true if erc20 and false otherwise
forge script --rpc-url "$HOME_CHAIN_RPC" \
	--private-key "$BRIDGER_PRIV_KEY" \
	script/Teleporter/Router/TestSendAndCallFunctionICTTRouter.s.sol:TestSendAndCallFunctionICTTRouter \
	--sig "run(bool)" true --broadcast --skip-simulation
```

## Check the result

```bash
# you should see a new id in the list: 123
cast call --rpc-url "$REMOTE_CHAIN_RPC" --private-key "$BRIDGER_PRIV_KEY" "$USERS_MOCK_CONTRACT" "getUsers()(uint256[])"

# you can also see some tokens in your balance on the destination chain
# ERC20
cast call --rpc-url "$REMOTE_CHAIN_RPC" "$BRIDGE_REMOTE_ADDR" "balanceOf(address)(uint256)" "$BRIDGER_ADDR"

# Native
cast balance "$BRIDGER_ADDR" --rpc-url "$REMOTE_CHAIN_RPC"
```
