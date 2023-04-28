// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/BidProtocol.sol";

contract BidStateChange is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        BidProtocol bidPool = BidProtocol(
            vm.envAddress("BID_POOL_CONTRACT_ADDRESS")
        );

        //bidPool.lpPoolWithdraw(1013168984407922460 wei);
        bidPool.nftLiquidate{value: 1 ether}();

        vm.stopBroadcast();
    }
}
