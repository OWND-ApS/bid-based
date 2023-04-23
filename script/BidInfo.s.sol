// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/BidProtocol.sol";

contract BidInfo is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BidProtocol bidPool = BidProtocol(
            vm.envAddress("BID_POOL_CONTRACT_ADDRESS")
        );

        uint256 state = bidPool.poolSize();
        console.log(state);

        vm.stopBroadcast();
    }
}
