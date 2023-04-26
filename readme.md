## Bid-based NFT pricing control

# TL;DR

When a LP start a bid-based NFT pool they buy the NFT specified and provide "extra" capital of 25% or over of intial NFT price. This is referred to as the "swap pool". Because of this extra capital besides the NFT (and never promising more than 100% of the NFT away), an LP can provide the functionaliy of allowing users to swap in and out at market bid-price instantly. In return, the LP receives trading fees. In case of sell offs > "swap pool" and no buys in-between the NFT will be liquidated and all participants will get the money they're owed.

# Swap In

When swapping in we read reservoirs latest bid-price (which is signed off-chain and provided as Message) and msg.value. By taking percentage of msg.value compared to bid-price we save how many percentage a user owns. We can never promise more than 100% of an NFT away. We save msg.value to "swap pool".

# Swap Out

At swap out the extra liquidity from the "swap" pool allows us to (in most cases) provide instant-sell for the user. This means they can swap out at market price and get the amount owed from the swap pool. The percentage they owed before will be returned to the contract/LP which in theory will still have the same value at that moment.

If the users request to swap out exceeds the swap out pool the contract will enter PendingLiquidation state. Here the LP/Owner will sell of the NFT they bought when they started the pool to the highest bid and return liqudidity. This will be done via the smart contract automatically before public launch. When the NFT is liquidated the contracts state will update and users + LP can now claim what they're owed based on %.

# Additional info

The protocol uses Reservoir's offchain oracle to get top bid on an NFT collection. The endpoint uses to retrieve a valid signed message can be found here: [reservoir top bid oracle](https://docs.reservoir.tools/reference/getoraclecollectionstopbidv2)

# Testing

To run foundry tests make sure to either supply a valid message or change the BidProtocol temporarily to return a fixed bid-price

# Todo:

-   Finish audit
-   Add proxy pattern to allow for upgradeability

# Thank you🙏

Thank you to everybody helping out with feedback/audit.

-   @supernova
