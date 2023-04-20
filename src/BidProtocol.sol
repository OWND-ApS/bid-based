// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BidProtocol is Ownable {
    using SafeMath for uint256;

    event NftLiquidated();

    event SwapIn(address indexed user, uint256 amountIn, uint256 percentIn);
    event SwapOut(address indexed user, uint256 percentOut, uint256 amountOwed);

    error FeeFailed();

    uint256 private constant MAX_POOL_PERCENT = 100 * 1e18;
    uint256 private constant MAX_PERCENT_OWNERSHIP = 1 * 1e18;

    address private immutable BID_ORACLE;
    address public immutable NFT_CONTRACT;
    uint256 public immutable TOKEN_ID;
    uint256 public immutable SWAP_FEE;

    uint256 public poolSize;
    uint256 public percentInPool = 100 * 1e18;
    uint256 public liquidatedPool;

    mapping(address => uint256) public addressToPercent;

    enum State {
        Inactive,
        Active,
        PendingLiquidation,
        Liquidated
    }

    State public state;

    constructor(
        address _NFT_CONTRACT,
        uint256 _TOKEN_ID,
        address _BID_ORACLE,
        uint256 _SWAP_FEE
    ) {
        NFT_CONTRACT = _NFT_CONTRACT;
        TOKEN_ID = _TOKEN_ID;
        BID_ORACLE = _BID_ORACLE;

        //Remember: Swapp fee should be in bps format (10**2)
        SWAP_FEE = _SWAP_FEE * 1e16;
        // Will ownable constructor still be autocalled?
    }

    modifier isActive() {
        require(state == State.Active, "Pool is not active for swapping");
        _;
    }

    /**
     * @dev Owner functions
     */

    function init() public payable onlyOwner returns (State) {
        require(state == State.Inactive, "Pool is already active");
        require(msg.value > 0, "Initial capital can't be 0");
        poolSize = msg.value;
        state = State.Active;
        return state;
    }

    /**
     * @dev User functions
     */

    //TODO: Add signed message as argument here
    function swapIn() public payable isActive {
        require(percentInPool > 0, "No percent left in pool");
        require(msg.value > 0, "Value needs to be above 0");

        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(
            currentUserPercent <= MAX_PERCENT_OWNERSHIP,
            "User already owns max percent"
        );

        //Swap in value
        uint256 feeValue = msg.value.mul(SWAP_FEE).div(100 * 1e18);
        uint256 swapInValue = msg.value.sub(feeValue);

        //Get bid price in wei
        uint256 bidPrice = getBid();

        uint256 newPercent = swapInValue
            .mul(1e18)
            .div(bidPrice)
            .mul(100 * 1e18)
            .div(1e18);
        uint256 totalPercent = newPercent.add(currentUserPercent);
        require(
            totalPercent <= MAX_PERCENT_OWNERSHIP,
            "This swap will cause User to exceed max percent"
        );
        require(
            totalPercent < percentInPool,
            "This swap will exceed percent in pool"
        );

        //All checks out, update pool and percent
        poolSize += swapInValue;
        percentInPool -= totalPercent;
        addressToPercent[msg.sender] = totalPercent;

        //TODO: Should I instead just save fee value?
        (bool feeSent, ) = owner().call{value: feeValue}("");
        if (!feeSent) revert FeeFailed();

        emit SwapIn(msg.sender, msg.value, newPercent);
    }

    function swapOut(uint256 _percentOut) public isActive {
        uint256 percentOut = _percentOut * 1e16;

        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(
            percentOut <= currentUserPercent,
            "You can't swap out more percent than you own"
        );

        uint256 bidPrice = getBid();
        uint256 amountOwed = bidPrice.mul(percentOut).div(100 * 1e18);
        uint256 feeValue = amountOwed.mul(SWAP_FEE).div(100 * 1e18);
        uint256 userValue = amountOwed.sub(feeValue);

        if (amountOwed > poolSize) {
            state = State.PendingLiquidation;
            emit NftLiquidated();
        } else {
            (bool userSent, ) = msg.sender.call{value: userValue}("");
            require(userSent, "Failed to send Ether to User");

            poolSize -= amountOwed;
            percentInPool += percentOut;
            addressToPercent[msg.sender] -= percentOut;

            (bool feeSent, ) = owner().call{value: feeValue}("");
            if (!feeSent) revert FeeFailed();

            emit SwapOut(msg.sender, percentOut, amountOwed);
        }
    }

    /**
     * @dev Return bid price from signed message?
     * @return twap bid from reservoir oracle
     */

    function getBid() internal pure returns (uint256) {
        return 1 ether;
    }

    function getState() public view returns (State) {
        return state;
    }
}
