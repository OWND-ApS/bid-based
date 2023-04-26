// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Inspired by https://github.com/ZeframLou/trustus
abstract contract ReservoirOracle {
    // --- Structs ---

    struct Message {
        bytes32 id;
        bytes payload;
        // The UNIX timestamp when the message was signed by the oracle
        uint256 timestamp;
        // ECDSA signature or EIP-2098 compact signature
        bytes signature;
    }

    // --- Errors ---

    error InvalidMessage();

    // --- Fields ---

    address public RESERVOIR_ORACLE_ADDRESS;

    // --- Constructor ---

    constructor(address reservoirOracleAddress) {
    // @audit Lack of 0 address check 
        RESERVOIR_ORACLE_ADDRESS = reservoirOracleAddress;
    }

    // --- Public methods ---

    function updateReservoirOracleAddress(
        address newReservoirOracleAddress
    ) public virtual;

    // --- Internal methods ---

    function _verifyMessage(
        bytes32 id,
        uint256 validFor,
        Message memory message
    ) internal view virtual returns (bool success) {
        // Ensure the message matches the requested id
        if (id != message.id) {
            return false;
        }

        // Ensure the message timestamp is valid
        if (
            message.timestamp > block.timestamp ||
            message.timestamp + validFor < block.timestamp
        ) {
            return false;
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Extract the individual signature fields from the signature
        bytes memory signature = message.signature;
        if (signature.length == 64) {
            // EIP-2098 compact signature
            bytes32 vs;
            assembly {
                r := mload(add(signature, 0x20))
                vs := mload(add(signature, 0x40))
                s := and(
                    vs,
                    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                )
                v := add(shr(255, vs), 27)
            }
        } else if (signature.length == 65) {
            // ECDSA signature
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
        } else {
            return false;
        }

        // @audit Wrong EIP 712 implementation .
// Use DOMAIN_SEPERATOR TYPEHASH 
// bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256(
        // "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    // );
    //  bytes32 DOMAIN_SEPARATOR;

    // function _hashDomain(EIP712Domain memory eip712Domain)
    //     internal
    //     pure
    //     returns (bytes32)
    // {
    //     return keccak256(
    //         abi.encode(
    //             EIP712DOMAIN_TYPEHASH,
    //             keccak256(bytes(eip712Domain.name)),
    //             keccak256(bytes(eip712Domain.version)),
    //             eip712Domain.chainId,
    //             eip712Domain.verifyingContract
    //         )
    //     );
    // }

    // DOMAIN_SEPARATOR = _hashDomain(EIP712Domain({
    //         name              : name,
    //         version           : version,
    //         chainId           : chainId,
    //         verifyingContract : address(this)
    //     }));

    //  address signerAddress = ecrecover(
    //         keccak256(
    //             abi.encodePacked(
    //                 "\x19Ethereum Signed Message:\n32",
    //                 DOMAIN_SEPARATOR,
    //                 keccak256(
    //                     abi.encode(
    //                         keccak256(
    //                             "Message(bytes32 id,bytes payload,uint256 timestamp)"
    //                         ),
    //                         message.id,
    //                         keccak256(message.payload),
    //                         message.timestamp
    //                     )
    //                 )
    //             )
    //         ),
    //         v,
    //         r,
    //         s
    //     );
        address signerAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    // EIP-712 structured-data hash
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Message(bytes32 id,bytes payload,uint256 timestamp)"
                            ),
                            message.id,
                            keccak256(message.payload),
                            message.timestamp
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        // Ensure the signer matches the designated oracle address
        return signerAddress == RESERVOIR_ORACLE_ADDRESS;
    }
}
