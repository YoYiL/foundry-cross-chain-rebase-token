// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
// Import your project-specific contracts
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
// Import the Chainlink Local simulator
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";

contract CrossChainTest is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    uint256 SEND_VALUE = 1e5;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        // 1. Create and select the initial (source) fork (Sepolia)
        // This uses the "sepolia" alias defined in foundry.toml
        sepoliaFork = vm.createSelectFork("sepolia");
        // 2. Create the destination fork (Arbitrum Sepolia) but don't select it yet
        // This uses the "arb-sepolia" alias defined in foundry.toml
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // 3. Deploy the CCIP Local Simulator contract
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // 4. Make the simulator's address persistent across all active forks
        // This is crucial so both the Sepolia and Arbitrum Sepolia forks
        // can interact with the *same* instance of the simulator.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        //Deploy and configure on Sepolia
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)), // Cast token via address
            new address[](0), // Empty allowlist
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );

        vm.stopPrank();

        //Deploy and configure on ArbSepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)), // Cast token via address
            new address[](0), // Empty allowlist
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();
        // Configure Sepolia Pool to interact with Arbitrum Sepolia Pool
        configureTokenPool(
            sepoliaFork, // Local chain: Sepolia
            address(sepoliaPool), // Local pool: Sepolia's TokenPool
            arbSepoliaNetworkDetails.chainSelector, // Remote chain selector: Arbitrum Sepolia's
            address(arbSepoliaPool), // Remote pool address: Arbitrum Sepolia's TokenPool
            address(arbSepoliaToken) // Remote token address: Arbitrum Sepolia's Token
        );

        // Configure Arbitrum Sepolia Pool to interact with Sepolia Pool
        configureTokenPool(
            arbSepoliaFork, // Local chain: Arbitrum Sepolia
            address(arbSepoliaPool), // Local pool: Arbitrum Sepolia's TokenPool
            sepoliaNetworkDetails.chainSelector, // Remote chain selector: Sepolia's
            address(sepoliaPool), // Remote pool address: Sepolia's TokenPool
            address(sepoliaToken) // Remote token address: Sepolia's Token
        );
    }

    function configureTokenPool(
        uint256 forkId, // The fork ID of the local chain
        address localPoolAddress, // Address of the pool being configured
        uint64 remoteChainSelector, // Chain selector of the remote chain
        address remotePoolAddress, // Address of the pool on the remote chain
        address remoteTokenAddress // Address of the token on the remote chain
    ) public {
        // 1. Select the correct fork (local chain context)
        vm.selectFork(forkId);

        // 2. Prepare arguments for applyChainUpdates
        // An empty array as we are only adding, not removing.
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);

        // Construct the chainsToAdd array (with one ChainUpdate struct)
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        // The remote pool address needs to be ABI-encoded as bytes.
        // CCIP expects an array of remote pool addresses, even if there's just one primary.
        bytes[] memory remotePoolAddressesBytesArray = new bytes[](1);
        remotePoolAddressesBytesArray[0] = abi.encode(remotePoolAddress);
        // Populate the ChainUpdate struct
        // Refer to TokenPool.sol for the ChainUpdate struct definition:

        // struct ChainUpdate {
        // uint64 remoteChainSelector; // Remote chain selector
        // bytes[] remotePoolAddresses; // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        // bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
        // RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        // RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        // }
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddressesBytesArray, // ABI-encode the array of bytes
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            // For this example, rate limits are disabled.
            // Consult CCIP documentation for production rate limit configurations.
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        // 3. Execute applyChainUpdates as the owner
        // applyChainUpdates is typically an owner-restricted function.
        vm.prank(owner); // The 'owner' variable should be the deployer/owner of the localPoolAddress
        TokenPool(localPoolAddress).applyChainUpdates(remoteChainSelectorsToRemove, chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork, // Source chain fork ID
        uint256 remoteFork, // Destination chain fork ID
        Register.NetworkDetails memory localNetworkDetails, // Struct with source chain info
        Register.NetworkDetails memory remoteNetworkDetails, // Struct with dest. chain info
        RebaseToken localToken, // Source token contract instance
        RebaseToken remoteToken // Destination token contract instance
    ) public {
        // -- On localFork, pranking as user --
        vm.selectFork(localFork);

        // Note: We use vm.prank(user) before each state-changing call instead of vm.startPrank/vm.stopPrank blocks.

        // 1. Initialize tokenAmounts array
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(localToken), // Token address on the local chain
            amount: amountToBridge // Amount to transfer
        });

        // 2. Construct the EVM2AnyMessage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // Receiver on the destination chain
            data: "", // No additional data payload in this example
            tokenAmounts: tokenAmounts, // The tokens and amounts to transfer
            feeToken: localNetworkDetails.linkAddress, // Using LINK as the fee token
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000}) // Use default gas limit
            )
        });

        // 3. Get the CCIP fee
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(
            remoteNetworkDetails.chainSelector, // Destination chain ID
            message
        );
        // 4. Fund the user with LINK (for testing via CCIPLocalSimulatorFork)
        // This step is specific to the local simulator
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);
        // 5. Approve LINK for the Router
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        // 6. Approve the actual token to be bridged
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        // 7. Get user's balance on the local chain BEFORE sending
        uint256 localBalanceBefore = localToken.balanceOf(user);
        vm.prank(user);
        // 8. Send the CCIP message
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector, // Destination chain ID
            message
        );

        // 9. Get user's balance on the local chain AFTER sending and assert
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge, "Local balance incorrect after send");
        //uint256 localUserInterestRate = localToken.getUserInterestRate(user);
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 1 hours); // Simulate time passage for interest accrual
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        // 12. Process the message on the remote chain (using CCIPLocalSimulatorFork)
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // 13. Get user's balance on the remote chain AFTER message processing and assert
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge, "Remote balance incorrect after receive");
        // 14. Check interest rates (specific to RebaseToken logic)
        // IMPORTANT: localUserInterestRate should be fetched *before* switching to remoteFork
        // Example: Fetch localUserInterestRate while still on localFork
        // vm.selectFork(localFork);
        // uint256 localUserInterestRate = localToken.getUserInterestRate(user);
        // vm.selectFork(remoteFork); // Switch back if necessary or rely on switchChainAndRouteMessage

        // uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user); // Called on remoteFork
        // assertEq(remoteUserInterestRate, localUserInterestRate, "Interest rates do not match");
    }

    function testBridgeAllTokens() public {
        // 1. Deposit into Vault on Sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE); // Give user some ETH to deposit

        vm.prank(user);
        // To send ETH (msg.value) with a contract call in Foundry:
        // Cast contract instance to address, then to payable, then back to contract type.
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE, "User Sepolia token balance after deposit incorrect");

        // 2. Bridge Tokens: Sepolia -> Arbitrum Sepolia
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // Assertions for this step are within bridgeTokens

        // 3. Bridge All Tokens Back: Arbitrum Sepolia -> Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes); // Advance time on Arbitrum Sepolia before bridging back

        uint256 arbBalanceToBridgeBack = arbSepoliaToken.balanceOf(user);
        assertTrue(arbBalanceToBridgeBack > 0, "User Arbitrum balance should be non-zero before bridging back");

        bridgeTokens(
            SEND_VALUE,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );

        // Final state check: User on Sepolia should have their initial deposit back
        // (minus any very small precision differences if applicable to tokenomics, or fees not covered by faucet)
        vm.selectFork(sepoliaFork);
        // Note: Exact final balance might depend on tokenomics if any fees were burnt from principal.
        // For this example, assume full amount returns.
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE, "User Sepolia token balance after bridging back incorrect");
    }
}
