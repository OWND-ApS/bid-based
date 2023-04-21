// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "src/ReservoirOracle.sol";

//TODO: Add proxy contract so it's upgradeable
contract BidProtocol is Ownable, ReservoirOracle {
    using SafeMath for uint256;

    event NftLiquidated();

    event SwapIn(address indexed user, uint256 amountIn, uint256 percentIn);
    event SwapOut(address indexed user, uint256 percentOut, uint256 amountOwed);
    event Withdrawn(
        address indexed user,
        uint256 percentOut,
        uint256 amountOwed
    );

    error FeeFailed();
    error BidOracleFailed();
    error NothingToWithdraw();

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

    enum PriceKind {
        SPOT,
        TWAP,
        LOWER,
        UPPER
    }

    State public state;

    constructor(
        address _NFT_CONTRACT,
        uint256 _TOKEN_ID,
        address _BID_ORACLE,
        uint256 _SWAP_FEE
    ) ReservoirOracle(_BID_ORACLE) {
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

    modifier isLiquidated() {
        require(state == State.Liquidated, "Pool is not active for withdraw");
        _;
    }

    /**
     * @dev Owner functions
     */

    function updateReservoirOracleAddress(address) public pure override {
        // TODO: Should allow owner to update the oracle address
        revert();
    }

    function init() public payable onlyOwner {
        require(state == State.Inactive, "Pool is already active");
        require(msg.value > 0, "Initial capital can't be 0");
        poolSize = msg.value;
        state = State.Active;
    }

    function nftLiquidate() public payable onlyOwner {
        require(
            state == State.PendingLiquidation,
            "Pool is not expecting liquidation"
        );
        require(msg.value > 0, "Liquidated amount needs to be > 0");
        liquidatedPool = msg.value;
        state = State.Liquidated;
    }

    function lpWithdraw() public isLiquidated onlyOwner {
        uint256 amountOwed = 0;

        if (poolSize > 0) amountOwed += poolSize;
        if (percentInPool > 0) {
            amountOwed += liquidatedPool.mul(percentInPool).div(100 * 1e18);
        }

        if (amountOwed > 0) {
            (bool lpSent, ) = msg.sender.call{value: amountOwed}("");
            require(lpSent, "Failed to send Ether to LP");

            poolSize = 0;
            percentInPool = 0;
        } else {
            revert NothingToWithdraw();
        }
    }

    /**
     * @dev User functions
     */

    function swapIn(Message calldata message) public payable isActive {
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

        uint256 bidPrice = getBid(message);

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

    //For now we'll only allow swapping out 100% of stake
    function swapOut(Message calldata message) public isActive {
        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(currentUserPercent > 0, "User doesn't own any percent");

        uint256 bidPrice = getBid(message);
        uint256 amountOwed = bidPrice.mul(currentUserPercent).div(100 * 1e18);

        uint256 feeValue = amountOwed.mul(SWAP_FEE).div(100 * 1e18);
        uint256 userValue = amountOwed.sub(feeValue);

        if (amountOwed > poolSize) {
            state = State.PendingLiquidation;
            emit NftLiquidated();
        } else {
            (bool userSent, ) = msg.sender.call{value: userValue}("");
            require(userSent, "Failed to send Ether to User");

            poolSize -= amountOwed;
            percentInPool += currentUserPercent;
            addressToPercent[msg.sender] = 0;

            (bool feeSent, ) = owner().call{value: feeValue}("");
            if (!feeSent) revert FeeFailed();

            emit SwapOut(msg.sender, currentUserPercent, amountOwed);
        }
    }

    function userWithdraw() public isLiquidated {
        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(currentUserPercent > 0, "User doesn't own any percent");

        uint256 amountOwed = liquidatedPool.mul(currentUserPercent).div(
            100 * 1e18
        );
        (bool userSent, ) = msg.sender.call{value: amountOwed}("");
        require(userSent, "Failed to send Ether to User");

        liquidatedPool -= amountOwed;
        addressToPercent[msg.sender] = 0;

        emit Withdrawn(msg.sender, currentUserPercent, amountOwed);
    }

    /**
     * @dev Return bid price from signed message?
     * @return twap bid from reservoir oracle
     */

    function getBid(Message calldata message) internal view returns (uint256) {
        // Construct the message id on-chain (using EIP-712 structured-data hashing)
        bytes32 id = keccak256(
            abi.encode(
                keccak256(
                    "ContractWideCollectionTopBidPrice(uint8 kind,uint256 twapSeconds,address contract)"
                ),
                PriceKind.SPOT,
                86400,
                NFT_CONTRACT
            )
        );

        // Validate the message
        uint256 maxMessageAge = 5 minutes;

        if (!_verifyMessage(id, maxMessageAge, message)) {
            revert BidOracleFailed();
        }

        (, uint256 price) = abi.decode(message.payload, (address, uint256));

        return price;
    }

    function getState() public view returns (State) {
        return state;
    }
}
