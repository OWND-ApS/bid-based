// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/BidProtocol.sol";
import "../src/ReservoirOracle.sol";

contract BidTest is Test {
    BidProtocol public bidPool;
    ReservoirOracle.Message message =
        ReservoirOracle.Message(
            0xf0e3c933e571a6ed56b569838684309bb69ba3a039372a3d15a3dd0fe715fef5,
            "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001354ee1e9c1e8000",
            1682448083,
            "0x4ddc00f663cf965476ecba368361506ecf4cac7f5622d614c53115f64e2bf2370425b8958044493c7410e624592dcd3fbf78e36caf1feb97d7b2b6a38efdcb411c"
        );

    function test_init() public {
        bidPool = new BidProtocol(address(1), 0, address(1), 0, 4 ether);

        uint256 state = uint256(bidPool.state());
        assertEq(state, 0);

        bidPool.init{value: 1 ether}();

        uint256 newState = uint256(bidPool.state());
        assertEq(newState, 1);
    }

    //Swap in and out tests

    function test_swapInPercent(uint256 a, uint256 b, uint256 c) public {
        //Can't be more than 1% of bid price which is 10 ether
        if (a <= 0 || b <= 0 || c <= 0) {
            return;
        }
        if (a > 1e17 || b > 1e17 || c > 1e17) {
            return;
        }

        bidPool = new BidProtocol(address(1), 0, address(1), 0, 4 ether);
        bidPool.init{value: 1 ether}();

        uint256 currentPercent = bidPool.percentInPool();

        address aUser = vm.addr(1);
        vm.prank(aUser);
        vm.deal(aUser, 1 ether);

        bidPool.swapIn{value: a}(message);
        uint256 aExpected = bidPool.getPercentOf(a, 100 ether);
        uint256 aPercent = bidPool.addressToPercent(aUser);

        assertEq(aPercent, aExpected);

        address bUser = vm.addr(2);
        vm.prank(bUser);
        vm.deal(bUser, 1 ether);

        bidPool.swapIn{value: b}(message);
        uint256 bExpected = bidPool.getPercentOf(b, 100 ether);
        uint256 bPercent = bidPool.addressToPercent(bUser);
        assertEq(bPercent, bExpected);

        address cUser = vm.addr(3);
        vm.prank(cUser);
        vm.deal(cUser, 1 ether);

        bidPool.swapIn{value: c}(message);
        uint256 cExpected = bidPool.getPercentOf(c, 100 ether);
        uint256 cPercent = bidPool.addressToPercent(cUser);

        assertEq(cPercent, cExpected);

        uint256 percentNow = bidPool.percentInPool();
        assertEq(currentPercent - (cPercent + bPercent + aPercent), percentNow);
    }

    function test_swapInPoolSize(uint256 a, uint256 b, uint256 c) public {
        //Can't be more than 1% of bid price which is 10 ether
        if (a <= 0 || b <= 0 || c <= 0) {
            return;
        }
        if (a > 1e17 || b > 1e17 || c > 1e17) {
            return;
        }

        bidPool = new BidProtocol(address(1), 0, address(1), 0, 4 ether);
        bidPool.init{value: 1 ether}();

        uint256 currentPool = bidPool.poolSize();

        address aUser = vm.addr(1);
        vm.prank(aUser);
        vm.deal(aUser, 1 ether);

        bidPool.swapIn{value: a}(message);

        address bUser = vm.addr(2);
        vm.prank(bUser);
        vm.deal(bUser, 1 ether);

        bidPool.swapIn{value: b}(message);

        address cUser = vm.addr(3);
        vm.prank(cUser);
        vm.deal(cUser, 1 ether);

        bidPool.swapIn{value: c}(message);

        uint256 poolNow = bidPool.poolSize();
        assertEq(poolNow - a - b - c, currentPool);
    }

    function test_swapOut(uint256 a, uint256 b) public {
        //Can't be more than 1% of bid price which is 10 ether
        if (a <= 0 || b <= 0) {
            return;
        }
        if (a > 1e17 || b > 1e17) {
            return;
        }

        bidPool = new BidProtocol(address(1), 0, address(1), 0, 4 ether);
        bidPool.init{value: 1 ether}();

        address aUser = vm.addr(1);
        vm.deal(aUser, 1 ether);

        address bUser = vm.addr(2);
        vm.deal(bUser, 1 ether);

        vm.prank(aUser);
        bidPool.swapIn{value: a}(message);

        vm.prank(bUser);
        bidPool.swapIn{value: b}(message);

        uint256 newPool = bidPool.poolSize();

        vm.prank(aUser);
        bidPool.swapOut(message);
        assertEq(bidPool.poolSize(), newPool - a);

        vm.prank(bUser);
        bidPool.swapOut(message);
        assertEq(bidPool.poolSize(), newPool - a - b);

        vm.expectRevert();
        bidPool.swapOut(message);
    }

    //Owner/LP tests
    function test_ownership() public {
        bidPool = new BidProtocol(address(1), 0, address(1), 0, 4 ether);
        vm.prank(address(0));
        vm.expectRevert();
        bidPool.init{value: 1 ether}();
    }

    function test_fees() public {
        bidPool = new BidProtocol(address(1), 0, address(1), 5000, 4 ether);
        bidPool.init{value: 1 ether}();

        address aUser = vm.addr(1);
        vm.deal(aUser, 1 ether);
        vm.prank(aUser);
        bidPool.swapIn{value: 1 ether}(message);

        uint256 fee = bidPool.feePool();
        assertEq(fee, 1 ether / 2);

        //Only owner can withdraw
        vm.prank(aUser);
        vm.expectRevert();
        bidPool.lpFeeWithdraw();

        //Now it should work
        bidPool.lpFeeWithdraw();
        assertEq(bidPool.feePool(), 0);
    }

    function test_lpDeployAndWithdraw(uint256 a) public {
        if (a <= 0) {
            return;
        }

        if (a > address(this).balance) {
            return;
        }

        bidPool = new BidProtocol(address(1), 0, address(1), 5000, 4 ether);
        bidPool.init{value: 1 ether}();

        uint initialPool = bidPool.poolSize();
        bidPool.lpDeployMore{value: a}();
        assertEq(bidPool.poolSize(), initialPool + a);

        bidPool.lpPoolWithdraw(a);
        assertEq(bidPool.poolSize(), initialPool);

        //Can't withdraw more
        vm.expectRevert();
        bidPool.lpPoolWithdraw(2 ether);

        //Only owner can deploy and withdraw
        vm.prank(address(2));
        vm.expectRevert();
        bidPool.lpDeployMore{value: a}();

        vm.prank(address(2));
        vm.expectRevert();
        bidPool.lpDeployMore{value: a}();
    }

    //Not testing right now --> private
    function test_Percent(uint256 x, uint256 y) private {
        bidPool = new BidProtocol(address(0), 0, address(0), 0, 0);

        if (x == 0 || y == 0) {
            return;
        }

        if (x > y) {
            return;
        }

        uint256 yTotal = y * x * 1e18;
        uint256 newX = x * 1e18;

        uint256 percent = bidPool.getPercentOf(newX, yTotal);

        console.log(yTotal);
        console.log(newX);
        console.log(percent);

        console.log("------");

        uint256 amount = bidPool.getValueOwed(percent, yTotal);

        console.log(amount);
        assertEq(amount, newX);
    }

    receive() external payable {}
}
