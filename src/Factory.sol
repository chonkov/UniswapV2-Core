// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable2Step, Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {Pair} from "./Pair.sol";

contract Factory is IFactory, Ownable2Step {
    error Factory_Identical_Addresses();
    error Factory_Zero_Address();
    error Factory_Pair_Already_Exists();

    address private _feeTo;
    mapping(address => mapping(address => address)) private _pairs;
    address[] private _allPairs;

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @dev Creates a new liquidity pool/pair unless it already exists
     * @param tokenA Address of the first provided token.
     * @param tokenB Address of the second provided token.
     * @return pair Address of the newly created pair
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert Factory_Identical_Addresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert Factory_Zero_Address();
        if (_pairs[token0][token1] != address(0)) revert Factory_Pair_Already_Exists();

        bytes memory bytecode = abi.encodePacked(type(Pair).creationCode, abi.encode(token0, token1));
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // pair = address(new Pair{salt: salt}(token0,token1)); // the same as create2 opcode
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        _pairs[token0][token1] = pair;
        // _pairs[token1][token0] = pair; // redundant
        _allPairs.push(pair);

        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    /**
     * @dev Owner can set a new address to receive fees
     * @param feeTo_ Reciever of the accumulated fees.
     */
    function setFeeTo(address feeTo_) external onlyOwner {
        _feeTo = feeTo_;
    }

    /**
     * @return Reciever of the accumulated fees.
     */
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    /**
     * @return Returns the number of created pairs.
     */
    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    /**
     * @dev Does not matter in what order the pair of tokens will be provided since it is sorted before the lookup
     * @return Returns the address of the pool for a given pair of tokens.
     */
    function getPair(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _pairs[token0][token1];
    }

    /**
     * @param _index The index of the pair stored in the array of pair addresses
     * @return Returns the address of the pair.
     */
    function allPairs(uint256 _index) external view returns (address) {
        return _allPairs[_index];
    }
}
