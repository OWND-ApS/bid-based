// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "src/ReservoirOracle.sol";

//TODO: Make upgradeable through proxy contract
contract BidProtocol is Ownable, ReservoirOracle, ReentrancyGuard {
    event NftLiquidated();

    event SwapIn(address indexed user, uint256 amountIn, uint256 percentIn);
    event SwapOut(address indexed user, uint256 percentOut, uint256 amountOwed);
    event Withdrawn(
        address indexed user,
        uint256 percentOut,
        uint256 amountOwed
    );

    uint256 private constant MAX_POOL_PERCENT = 100 * 1e18;
    uint256 private constant MAX_PERCENT_OWNERSHIP = 1 * 1e18;

    address private immutable BID_ORACLE;
    address public immutable NFT_CONTRACT;
    uint256 public immutable TOKEN_ID;
    uint256 public immutable SWAP_FEE;
    uint256 public immutable INITIAL_NFT_PRICE;

    uint256 public poolSize;
    uint256 public percentInPool = 100 * 1e18;
    uint256 public liquidatedPool;
    uint256 public feePool;

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
        uint256 _SWAP_FEE,
        uint256 _INITIAL_NFT_PRICE
    ) ReservoirOracle(_BID_ORACLE) {
        require(_NFT_CONTRACT != address(0), "Invalid NFT contract");
        require(_BID_ORACLE != address(0), "Invalid oracle address");
        require(_INITIAL_NFT_PRICE > 0, "Initial NFT price can't be 0");
        require(
            _SWAP_FEE >= 0 && _SWAP_FEE <= 1e4,
            "Invalid swap fee percentage"
        );

        NFT_CONTRACT = _NFT_CONTRACT;
        TOKEN_ID = _TOKEN_ID;
        BID_ORACLE = _BID_ORACLE;
        INITIAL_NFT_PRICE = _INITIAL_NFT_PRICE;

        //Remember: Swap fee should be in bps format (10**2)
        SWAP_FEE = _SWAP_FEE * 1e16;
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
     * LP/Owner functions
     */

    function updateReservoirOracleAddress(
        address newAddress
    ) public override onlyOwner {
        RESERVOIR_ORACLE_ADDRESS = newAddress;
    }

    function init() public payable onlyOwner {
        require(state == State.Inactive, "Pool is already active");
        require(msg.value > 0, "Initial capital can't be 0");

        uint256 percentOfNFTValue = getPercentOf(msg.value, INITIAL_NFT_PRICE);
        require(
            percentOfNFTValue >= 25 * 1e18,
            "Initial capital needs to be 25% or above of initial NFT value"
        );

        poolSize = msg.value;
        state = State.Active;
    }

    function lpDeployMore() public payable onlyOwner isActive {
        require(msg.value > 0, "Capital can't be 0");
        poolSize += msg.value;
    }

    function lpPoolWithdraw(uint256 amount) public onlyOwner nonReentrant {
        require(amount <= poolSize, "Can't withdraw more than pool");
        poolSize -= amount;
        (bool lpSent, ) = msg.sender.call{value: amount}("");
        if (!lpSent) revert("Withdraw failed");
    }

    function lpLiquidatedWithdraw() public isLiquidated onlyOwner nonReentrant {
        require(percentInPool > 0, "No percent left in pool");
        uint256 amountOwed = getValueOwed(percentInPool, liquidatedPool);

        percentInPool = 0;
        (bool lpSent, ) = msg.sender.call{value: amountOwed}("");
        if (!lpSent) revert("Withdraw failed");
    }

    function lpFeeWithdraw() public onlyOwner nonReentrant {
        //Q: This is necessary to avoid reentrancy attack?
        uint256 feePoolCopy = feePool;
        feePool = 0;
        (bool lpSent, ) = msg.sender.call{value: feePoolCopy}("");
        if (!lpSent) revert("Withdraw failed");
    }

    //When NFT is liquidated this function will be called with the amount of ETH it was sold to bid pool for (reason: blur don't allow smart contracts to accept bids)
    //Aware that this is a centralization issue and will be fixed before public release of protocol
    function nftLiquidate() public payable onlyOwner {
        require(
            state == State.PendingLiquidation,
            "Pool is not expecting liquidation"
        );
        require(msg.value > 0, "Liquidated amount needs to be > 0");
        liquidatedPool = msg.value;
        state = State.Liquidated;
    }

    /**
     * User functions
     */

    function swapIn(Message calldata message) public payable isActive {
        require(percentInPool > 0, "No percent left in pool");
        require(msg.value > 0, "Value needs to be above 0");

        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(
            currentUserPercent <= MAX_PERCENT_OWNERSHIP,
            "User already owns max percent"
        );

        //Calculate swap in value
        uint256 feeValue = getValueOwed(SWAP_FEE, msg.value);
        uint256 swapInValue = msg.value - feeValue;

        //Get bid price in wei from Reservoir oracle
        uint256 bidPrice = getBid(message);

        //Calculate percent without decimals
        uint256 newPercent = getPercentOf(swapInValue, bidPrice);
        require(newPercent > 0, "Value is below minimum swap in value");
        uint256 totalPercent = currentUserPercent + newPercent;

        require(
            totalPercent <= MAX_PERCENT_OWNERSHIP,
            "This swap will cause User to exceed max percent"
        );
        require(
            totalPercent <= percentInPool,
            "This swap will exceed percent in pool"
        );

        //All checks out, update pool and percent
        poolSize += swapInValue;
        percentInPool -= newPercent;
        addressToPercent[msg.sender] = totalPercent;

        //Save fee
        if (feeValue > 0) feePool += feeValue;

        emit SwapIn(msg.sender, msg.value, newPercent);
    }

    //Note: For now we'll only allow swapping out 100% of stake
    function swapOut(Message calldata message) public isActive nonReentrant {
        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(currentUserPercent > 0, "User doesn't own any percent");

        uint256 bidPrice = getBid(message);
        uint256 amountOwed = getValueOwed(currentUserPercent, bidPrice);

        uint256 feeValue = getValueOwed(SWAP_FEE, amountOwed);
        uint256 userValue = amountOwed - feeValue;

        if (amountOwed > poolSize) {
            state = State.PendingLiquidation;
            emit NftLiquidated();
        } else {
            poolSize -= amountOwed;
            percentInPool += currentUserPercent;
            addressToPercent[msg.sender] = 0;

            //Save fee
            if (feeValue > 0) feePool += feeValue;

            (bool userSent, ) = msg.sender.call{value: userValue}("");
            if (!userSent) revert("Swap out failed");

            emit SwapOut(msg.sender, currentUserPercent, amountOwed);
        }
    }

    function userWithdraw() public isLiquidated nonReentrant {
        uint256 currentUserPercent = addressToPercent[msg.sender];
        require(currentUserPercent > 0, "User doesn't own any percent");

        uint256 amountOwed = getValueOwed(currentUserPercent, liquidatedPool);

        addressToPercent[msg.sender] = 0;
        (bool userSent, ) = msg.sender.call{value: amountOwed}("");
        if (!userSent) revert("Withdraw failed");

        emit Withdrawn(msg.sender, currentUserPercent, amountOwed);
    }

    /**
     * Returns bid price from signed message
     */

    function getBid(Message calldata message) internal view returns (uint256) {
        return 100 ether;
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
            revert("Bid Oracle failed");
        }

        (, uint256 price) = abi.decode(message.payload, (address, uint256));

        return price;
    }

    /**
     * Percentage calculations
     */

    function getPercentOf(uint256 x, uint256 y) public pure returns (uint256) {
        return (x * 100e18) / y;
    }

    function getValueOwed(uint256 x, uint256 y) public pure returns (uint256) {
        return (((y * 1e18) * x) / (100 * 1e18)) / 1e18;
    }

    /**
     * Easy getters
     */

    function getPoolSize() public view returns (uint256) {
        if (INITIAL_NFT_PRICE > poolSize) return poolSize;
        else {
            return poolSize - INITIAL_NFT_PRICE;
        }
    }

    function getState() public view returns (State) {
        return state;
    }
}
